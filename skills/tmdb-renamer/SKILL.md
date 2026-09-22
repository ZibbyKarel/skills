---
name: tmdb-renamer
description: "Rename and organize movies and TV shows on the NAS (Holly) using the TMDB database into Plex/Kodi standard naming. Use this skill whenever the user says \"rename my movies\", \"organize my shows\", \"put this into the right format\", \"sort these videos\", \"fix the filenames\", \"rename by TMDB\", or wants to work with a movie/TV library. Also trigger on mentions of \"movie-library\", \"renaming videos\", \"organizing media\", or moving files into a media folder with movies and shows."
---

# TMDB Renamer – Movie & TV Show Renaming Skill

This skill scans video files on the NAS, identifies them via the TMDB API, and renames them into
the standard Plex/Kodi naming format.

---

## TMDB API configuration

The API token lives in `~/.zibby/zibby-skills/config.yml` under a `tmdb:` key — this is a
**global** config, not the per-repo one `zibby:jira` reads:

```yaml
tmdb:
  token: <bearer token>
```

If the file or the `tmdb:` key is missing, ask the user for the token and write it there
(creating `~/.zibby/` and `~/.zibby/zibby-skills/` if needed). **Never hardcode the token in this
file or print it back to the user** — it's a credential, treat it like one.

```
Base URL: https://api.themoviedb.org
```

Send every API call with this header, using the token from the config file:
```
Authorization: Bearer <token>
Accept: application/json
```

---

## Connecting to Holly (the NAS)

This skill reaches the NAS exactly the way `zibby:holly` does — read that skill for the full
picture. In short:

- Holly (192.168.1.4) is on the home LAN – a cloud sandbox (the plain `Bash` tool) can **never**
  reach it. All SSH commands must go through `device_bash` (mcp__remote-devices__device_bash),
  since that runs on Zibby's Mac, on the same network.
- Always connect with the persistent key, never a password:
  ```bash
  ssh -p 4444 -i ~/mnt/Workspace/.holly-ssh/id_ed25519_holly -o BatchMode=yes zibby@192.168.1.4 "<command>"
  ```
- **Port 4444** is non-standard – always add `-p 4444` (for `scp`, use `-P 4444`).
- Paths on the NAS are under `/volume1/`.
- Synology DSM 7 uses BusyBox – some GNU commands have limited flags.

The commands below are written shorthand as `ssh -p 4444 zibby@192.168.1.4 "..."` for readability
– in practice they always run through `device_bash` and with the key, as shown above.

---

## Workflow

### 1. Determine the target folder

Ask the user which folder to process, or suggest default options from the NAS:
- `/volume1/home/Downloads` – newly downloaded files waiting to be processed
- `/volume1/movie-library` – the main library (movies, shows, etc.)

If the user says e.g. "process Downloads", use `/volume1/home/Downloads`.

### 2. List video files on the NAS

```bash
ssh -p 4444 zibby@192.168.1.4 "find /volume1/PATH -maxdepth 2 -type f \( -name '*.mkv' -o -name '*.mp4' -o -name '*.avi' -o -name '*.m4v' -o -name '*.mov' \) | sort"
```

Use `maxdepth 2` for the first pass. If the folder is deeply nested, adjust the depth as needed.

### 3. Parse each filename

Extract from each filename:

**a) Detect show vs. movie**
If the name contains patterns like `S01E01`, `s01e01`, `1x01`, `Season.1.Episode.1` → it's a
**TV show**. Otherwise → a **movie**.

**b) Clean the name for searching**
Strip from the name (but not from the final rename – that comes from TMDB):
- Dots and underscores → replace with spaces
- Year in parentheses or bare: `(2019)`, `.2019.`
- Quality/technical tags: `1080p`, `720p`, `4K`, `UHD`, `HDR`, `BluRay`, `BDRip`, `DVDRip`,
  `WEBRip`, `WEB-DL`, `HDTV`, `REMUX`
- Video codecs: `x264`, `x265`, `HEVC`, `H264`, `H265`, `AV1`
- Audio codecs: `DTS`, `AC3`, `DD5.1`, `AAC`, `TrueHD`, `Atmos`
- Release groups: anything in square brackets `[GROUP]` or after the last `-` (if followed by a
  single-word tag)
- For shows: strip `S01E01` and everything after it → leaves just the show name

**c) Extract the year**
Look for a 4-digit number that looks like a year (1900–2029). Use it to narrow the TMDB search.

**d) For shows: extract season and episode**
From a pattern like `S01E03` extract: season=1, episode=3.

### 4. Search the TMDB API

**For movies:**
```
GET /3/search/movie?query=NAME&year=YEAR&language=en-US
```
If no year was found, retry without the `year` parameter.

**For shows:**
```
GET /3/search/tv?query=NAME&language=en-US
```

**Picking the right result:**
- If there are multiple results, take the top one by `popularity` with `vote_count > 10`.
- If unsure (similar names, no year to narrow it down), show the user the top 3 results and let
  them pick.
- If TMDB finds nothing, mark the file `❓ NOT FOUND` and skip it.

For show episodes:
```
GET /3/tv/{tv_id}/season/{season}/episode/{episode}?language=en-US
```

### 5. Build the new name per the Plex/Kodi standard

**Movies:**
```
Target folder: /volume1/movie-library/Movies/
Filename format: Title (Year).ext
Examples:
  - Inception.2010.mkv       → "Inception (2010).mkv"
  - The.Matrix.1999.mkv      → "The Matrix (1999).mkv"
  - Interstellar.2014.mkv    → "Interstellar (2014).mkv"
```

**Shows:**
```
Target folder: /volume1/movie-library/Shows/Show Title/Season XX/
Filename format: Show Title - SXXEXX - Episode Title.ext
Examples:
  - Breaking Bad/Season 01/Breaking Bad - S01E01 - Pilot.mkv
  - Chernobyl/Season 01/Chernobyl - S01E03 - Open Wide, O Earth.mkv
  - Game of Thrones/Season 03/Game of Thrones - S03E05 - Kissed by Fire.mkv
```

Rules:
- Always use the `title`/`name` field from TMDB.
- Season is always written with two digits: `Season 01`, `S01E03`.
- Keep the original file extension (`.mkv`, `.mp4`, etc.).
- If an episode has no title in TMDB at all, omit that part: `Breaking Bad - S01E01.mkv`.

### 6. Show the user a preview of the proposed changes

Before renaming or moving anything, print a clear table:

```
📋 PROPOSED CHANGES (12 files total)

MOVIES (8):
  ✅ The.Matrix.1999.1080p.BluRay.mkv
     → /volume1/movie-library/Movies/The Matrix (1999).mkv

  ✅ Inception.2010.BDRip.x264.mkv
     → /volume1/movie-library/Movies/Inception (2010).mkv

  ❓ Unknown.Movie.2023.mkv
     → NOT FOUND in TMDB – skipped

SHOWS (4):
  ✅ Breaking.Bad.S01E01.720p.mkv
     → /volume1/movie-library/Shows/Breaking Bad/Season 01/Breaking Bad - S01E01 - Pilot.mkv

FILES ALREADY IN THE CORRECT FORMAT (0): –

Continue? (Confirm or adjust individual items.)
```

Wait for confirmation. Never rename anything without the user's approval.

### 7. Perform the rename and move on the NAS

Once confirmed, go file by file:

1. Create the target folder if it doesn't exist:
   ```bash
   ssh -p 4444 zibby@192.168.1.4 "mkdir -p '/volume1/movie-library/Movies/'"
   ```

2. Move (and rename) the file:
   ```bash
   ssh -p 4444 zibby@192.168.1.4 "mv '/volume1/home/Downloads/Breaking.Bad.S01E01.720p.mkv' '/volume1/movie-library/Shows/Breaking Bad/Season 01/Breaking Bad - S01E01 - Pilot.mkv'"
   ```

3. Report progress as you go: `✅ Done (3/12): Breaking Bad - S01E01 - Pilot.mkv`

When finished, print a summary: how many files were renamed, how many skipped, how many failed.

---

## Error handling and edge cases

- **Filename with diacritics or spaces:** Always wrap paths in single quotes in SSH commands.
- **Target file already exists:** Warn the user and skip – never overwrite automatically.
- **Folder is very large (100+ files):** Process in batches of 20 and report progress as you go.
- **TMDB API rate limit:** the API allows ~40 requests per 10 seconds. For larger batches, add a
  short pause or process sequentially.
- **Wrong year in the name:** if TMDB finds nothing with that year, retry without it.
- **Show vs. movie unclear:** without an SxxExx pattern, assume a movie; if still unsure, ask the
  user.

---

## Examples

| Input filename | Result |
|---|---|
| `The.Matrix.1999.1080p.BluRay.x264.mkv` | `The Matrix (1999).mkv` |
| `Inception.2010.BDRip.mkv` | `Inception (2010).mkv` |
| `Interstellar.2014.WEBRip.1080p.mkv` | `Interstellar (2014).mkv` |
| `Breaking.Bad.S01E01.720p.HDTV.mkv` | `Breaking Bad/Season 01/Breaking Bad - S01E01 - Pilot.mkv` |
| `Chernobyl.S01E03.WEBRip.mkv` | `Chernobyl/Season 01/Chernobyl - S01E03 - Open Wide, O Earth.mkv` |
| `game.of.thrones.3x05.mkv` | `Game of Thrones/Season 03/Game of Thrones - S03E05 - Kissed by Fire.mkv` |
| `some_random_file_2023.mkv` | `❓ NOT FOUND – skipped` |
