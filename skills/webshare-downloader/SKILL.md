---
name: webshare-downloader
description: "Download files from Webshare.cz or FastShare.cloud via JDownloader. Use this skill whenever the user wants to download a file, video, archive, adult content, or other content and add it to JDownloader (my.jdownloader.org). Also trigger on mentions of \"webshare\", \"fastshare\", \"download via jdownloader\", \"add to jdownloader\", \"search webshare/fastshare\", or \"put this in jdownloader\". Supports regular videos (category=video) and adult 18+ content (category=adult). Default quality is 1080p, default language is Czech (CZ dub), falling back to English with subtitles."
---

# Webshare / FastShare → JDownloader Skill

This skill searches for files first on Webshare.cz (via API), and falls back to FastShare.cloud
(via browser) if that fails. Found URLs get added to JDownloader.

**Key facts:**
- JDownloader has a native plugin for both **webshare.cz** and **fastshare.cloud** — just paste
  the direct file URL
- Webshare URL format: `https://webshare.cz/file/IDENT/`
- FastShare URL format: `https://fastshare.cloud/FILE_ID/filename`

---

## Step 1: Figure out what to download

If the user hasn't specified a filename, ask.

**Default settings (always use these unless the user says otherwise):**
- Quality: **1080p (Full HD)**
- File type: **mkv** or **mp4**
- Language: **Czech (CZ dub)** — if CZ isn't available, look for EN with subtitles

---

## Step 2: Search Webshare.cz

Webshare has a REST API. Use bash/curl — it's fast and doesn't need a browser.

### Determine the category

First decide which category to use:

- **Adult content (18+):** use `category=adult`
  — use this if the user explicitly asks for 18+ content, mentions a studio name (Brazzers,
  Reality Kings, Mofos, Bangbros, etc.), or it's otherwise clear from context that it's adult
  content
- **Regular videos (movies, shows):** use `category=video`
- **Archives, documents, audio:** use the matching category (`archive`, `document`, `audio`)

> **Important:** `category=adult` returns exclusively 18+ content, which does not show up under
> `category=video` and vice versa. These categories don't overlap — always use the right one for
> the context.

### Search strategy for videos (in this order)

For **regular videos**, search with a language preference:
1. First search for **CZ dub + requested quality**: `"Title CZ 1080p"`
2. If nothing found (fewer than 1 result without a password), search **CZ subtitles**:
   `"Title CZ tit 1080p"` or `"Title CZ sub 1080p"`
3. If still nothing, search **EN + subtitles**: `"Title 1080p EN"` or just `"Title 1080p"`

For **adult content**, don't apply the language strategy — search directly by
title/studio/performer: `"Title or studio or performer + 1080p"`

### API call

```bash
curl -s -X POST "https://webshare.cz/api/search/" \
  -d "what=QUERY&category=CATEGORY&sort=rating&limit=20" \
  -H "Content-Type: application/x-www-form-urlencoded"
```

**Parameters:**
- `what` — the search term (title, year, language, quality, studio, performers)
- `category` — `video`, `adult`, `audio`, `archive`, `document`, or omit for everything
- `sort` — `rating` (recommended), `recent`, `largest`
- `limit` — max 100

**XML response:**
```xml
<file>
  <ident>abc123xyz</ident>       <!-- unique file ID -->
  <name>Movie.2024.1080p.CZ.mkv</name>
  <size>4294967296</size>        <!-- size in bytes -->
  <positive_votes>42</positive_votes>
  <negative_votes>0</negative_votes>
  <password>0</password>         <!-- 0 = no password, 1 = skip -->
</file>
```

### Ideal file sizes

When picking a file, prefer files in these size ranges — files that are too small tend to be low
quality or just a trailer/sample:

| Resolution | Ideal size |
|---|---|
| **Full HD (1080p)** | **5–6 GB** |
| **4K (2160p / UHD)** | **15 GB and up** |
| 720p | 2–4 GB |
| SD (480p and below) | under 2 GB |

Size is in bytes in the XML (`<size>`). To convert: 1 GB ≈ 1,073,741,824 bytes.

### Picking the right file

Prefer files that (in order of importance):
1. Contain the search term in the name
2. Contain `CZ` or `Czech` in the name (dub/subtitles)
3. Contain the requested quality (`1080p`, `BluRay`, `BDRip`, ...)
4. Have no password (`password=0`)
5. Have the most `positive_votes`
6. Are close to the ideal size for that resolution (see table above)

### Presenting results to the user — MANDATORY step before downloading

**Before adding anything to JDownloader, show the user the found files and let them choose.**

Sort the candidates (password-free files relevant to the query) from best to worst and show a
table:

```
Files found for "Inception CZ 1080p":

#  Name                                     Size        Votes  Note
1  Inception.2010.CZ.1080p.BluRay.mkv       5.8 GB      47 👍  ✅ recommended
2  Inception.2010.CZ.1080p.WEB-DL.mkv       4.2 GB      12 👍
3  Inception.2010.CZ.1080p.HDTV.avi         1.9 GB       3 👍  ⚠️ small file

Which file do you want to download? (enter a number or several, e.g. "1" or "1,3")
```

Rules for presenting results:
- Add **✅ recommended** to the file that best matches the criteria (right size, CZ, high votes)
- Add **⚠️ small file** if a file is significantly smaller than the ideal for its resolution
- Wait for the user's answer — **only download what the user picked**

### URL for JDownloader

For each chosen ident, build the URL:
```
https://webshare.cz/file/IDENT/
```

---

## Step 3: If Webshare finds nothing — try FastShare.cloud

If Webshare returns no suitable result (no password-free file matching the query), move on to
FastShare.cloud using the Chrome browser tools (`mcp__claude-in-chrome__*`, or the built-in
browser pane's `mcp__Claude_Browser__*` tools if that's what this session has).

### FastShare search

**Search URL format:** `https://fastshare.cloud/SLUG/s`

Build SLUG from the query like this:
```bash
echo "Inception 1080p CZ" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-'
# result: inception-1080p-cz
```

Examples:
- "Inception 1080p CZ" → `https://fastshare.cloud/inception-1080p-cz/s`
- "The Office S01" → `https://fastshare.cloud/the-office-s01/s`

### Procedure with the browser

1. Navigate to the search URL.
2. Wait 3-4 seconds for results to load (they're rendered by JavaScript).
3. Take a screenshot, or read the page, and check the results visually.
4. From the results, find files matching the criteria (title, CZ, 1080p).
5. Click the matching file — the file URL will be in the format:
   `https://fastshare.cloud/FILE_ID/filename`
6. Use that URL for JDownloader.

**Filter FastShare results the same way as Webshare:**
- Prefer CZ dub, then CZ subtitles, then EN
- Prefer 1080p BluRay/BDRip over HDTV or WEB-DL

---

## Step 4: If not found on FastShare either

If FastShare also returns nothing suitable, **tell the user**:

> "Unfortunately I couldn't find [filename] on either Webshare.cz or FastShare.cloud. The file is
> probably not currently available on either platform."

---

## Step 5: Add the links to JDownloader

Use the browser tools to work with `my.jdownloader.org`.

### 5a. Navigate to JDownloader

```
https://my.jdownloader.org/index.html
```

Wait 2-3 seconds.

### 5b. Select the connected device

Click the instance icon under "YOUR JDOWNLOADERS" (usually **JDOWNLOADER@ROOT**).
Wait 3 seconds for it to load.

### 5c. Open "Add links"

Click the yellow **"Add links"** button in the bottom-right corner.

### 5d. Paste the URLs and confirm

1. Click into the text field ("Enter Links, URLs, Websites...")
2. Paste the file URLs — one per line:
   ```
   https://webshare.cz/file/abc123/
   https://fastshare.cloud/11241215/filename.mkv
   ```
3. Click the yellow **"Continue"** button.

JDownloader switches to the **LINKCOLLECTOR** tab and shows the added files.

### 5e. Add the files to the download queue

After landing on LINKCOLLECTOR:
1. Right-click the added package in the list.
2. Click **"Add to downloads"** in the context menu.

The files move to the **DOWNLOADS** tab.

### 5f. Start the download (if not running)

Check the buttons in JDownloader's top bar:
- If you see a **▶ (Play / Start)** button — click it to start downloading.
- If downloads are already running (the pause ⏸ button is active), there's nothing else to do.

---

## Full workflow overview

```
User gives a request
        ↓
Search the Webshare.cz API
  → Found? → Build the webshare.cz/file/IDENT/ URL
  → Not found?
        ↓
Search FastShare.cloud (browser)
  → Found? → Take the fastshare.cloud/ID/filename URL
  → Not found? → Tell the user, done
        ↓
⭐ SHOW A TABLE OF FOUND FILES (name, size, votes, notes)
   Wait for the user to pick a file number(s)
        ↓
Open JDownloader (my.jdownloader.org)
Click the device → Add links → paste the chosen URLs → Continue
        ↓
LINKCOLLECTOR: right-click → "Add to downloads"
        ↓
DOWNLOADS: if not running → click Play ▶
```

---

## Bash helper scripts

```bash
# Webshare: search for the CZ version
search_webshare() {
  local query="$1"
  curl -s -X POST "https://webshare.cz/api/search/" \
    -d "what=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$query'))")&category=video&sort=rating&limit=20" \
    -H "Content-Type: application/x-www-form-urlencoded"
}

# Extract idents and names from the XML response
parse_results() {
  echo "$1" | grep -oP '<ident>[^<]+</ident>|<name>[^<]+</name>|<password>[^<]+</password>' | \
    paste - - - | sed 's/<[^>]*>//g'
}

# Generate a FastShare search URL
fastshare_url() {
  local query="$1"
  local slug=$(echo "$query" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  echo "https://fastshare.cloud/${slug}/s"
}
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Webshare: no results | Try a different query (no diacritics, just title + year) |
| File has `password=1` | Skip it, look for another |
| FastShare: page didn't load | Wait 5s and try again |
| FastShare: no results | Try a shorter slug (just the title, no quality) |
| JDownloader: "Offline" in LinkCollector | The file was deleted, look for another |
| JDownloader doesn't see the device | The JDownloader app must be running and signed in |
| LINKCOLLECTOR is empty | Check the URL format — webshare needs a trailing slash |

---

## Examples

| User says | 1st attempt (Webshare) | 2nd attempt (FastShare) |
|---|---|---|
| "download Inception" | `Inception CZ 1080p` | `inception-cz-1080p/s` |
| "I want The Office S01 CZ" | `The Office S01 CZ 1080p` | `the-office-s01-cz/s` |
| "download Dune in English" | `Dune 2021 EN 1080p` | `dune-2021-en-1080p/s` |
| "I want the XYZ zip archive" | query without category=video | same query |
