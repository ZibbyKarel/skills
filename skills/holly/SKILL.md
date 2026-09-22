---
name: holly
description: "Access to Zibby's Synology NAS (DSM 7) over SSH at zibby@192.168.1.4. Use this skill whenever the user wants to work with files on the NAS, move files, find duplicates, browse folders, reorganize content, or do any kind of file management on the Synology. Also trigger on mentions of \"holly\", \"NAS\", \"Synology\", or \"files on the server\"."
---

# Holly – Synology NAS Skill

This skill describes how to connect to Zibby's Synology NAS and work with files over SSH.

---

## IMPORTANT: where to connect from

Holly (192.168.1.4) is on the home LAN – a cloud sandbox (the plain `Bash` tool) can **never**
reach it. All SSH commands to Holly must go through `device_bash`
(mcp__remote-devices__device_bash), because that runs on Zibby's Mac, which is on the same
network.

If `device_bash` reports "No folders are connected", the session needs at least one folder
connected – ideally `~/Documents/.zibby` specifically, not all of `~/Documents` (that's also
where the persistent SSH key lives, see below, and it's synced via iCloud Drive across Zibby's
Macs — no reason to grant a cloud session the rest of Documents just to reach it). Ask for it to
be connected via `device_request_folder_access`.

## Connecting – persistent SSH key (don't use a password, don't regenerate the key every time)

There's a persistent keypair for this NAS stored at `~/Documents/.zibby/ssh/id_ed25519_holly` (and
`.pub`) on Zibby's Mac – it survives across sessions because it lives in a connected folder, not
in the ephemeral sandbox, and it's synced via iCloud Drive (`~/Documents`) so every one of Zibby's
Macs sees the same key without needing its own entry in `authorized_keys`. It's authorized in
`authorized_keys` on Holly. **Always connect with this key via `device_bash`:**

```bash
ssh -p 4444 -i ~/mnt/Documents/.zibby/ssh/id_ed25519_holly -o BatchMode=yes zibby@192.168.1.4 "<command>"
```

(The path `~/mnt/Documents/...` is the view from `device_bash` – on the Mac itself, inside the
folder, it's `~/Documents/.zibby/ssh/...`.)

The password is never used or entered on the user's behalf.

- **Host:** 192.168.1.4
- **Port:** 4444 (non-standard – always `-p 4444`; for `scp` use `-P 4444`)
- **User:** zibby
- **System:** Synology DSM 7

**iCloud sync note:** iCloud Drive can reset a file's Unix permissions after it re-downloads a
fresh copy on another Mac (or after being evicted and pulled back down locally). If `ssh` refuses
the key citing permissions ("UNPROTECTED PRIVATE KEY FILE" / "bad permissions"), just
`chmod 600 ~/mnt/Documents/.zibby/ssh/id_ed25519_holly` and retry — this is expected on iCloud-synced
keys, not a sign anything is actually wrong.

### If the key is missing (new Mac, iCloud not synced down yet, key deleted, etc.)

1. Check via `device_bash` whether `~/mnt/Documents/.zibby/ssh/id_ed25519_holly` exists. If
   `~/Documents/.zibby` was only just created on another Mac, give iCloud a minute to sync it down
   before assuming it's really missing.
2. If it's genuinely not there, generate a new one:
   `ssh-keygen -t ed25519 -f ~/mnt/Documents/.zibby/ssh/id_ed25519_holly -N "" -C "zibby-holly-persistent"`
   (first `mkdir -p ~/mnt/Documents/.zibby/ssh && chmod 700 ...`).
3. Print the public key and ask the user to add it to Holly **just once** (with their password,
   themselves):
   ```bash
   ssh -p 4444 zibby@192.168.1.4 "mkdir -p ~/.ssh && echo '<public key>' >> ~/.ssh/authorized_keys"
   ```
4. Once confirmed, verify the connection (`echo OK`) and continue with the task.

NEVER generate a new key if the persistent one in `~/Documents/.zibby/ssh/` already exists and
works (even if it takes a moment to appear because iCloud is still syncing it down) – that's
exactly the duplicate step this setup avoids, and a second key would need its own
`authorized_keys` entry on Holly.

### Cleaning up old keys

Because a new key used to be generated in every session (and never deleted),
`~/.ssh/authorized_keys` on Holly likely contains several old, unused keys (comments like
`cowork-session-holly`). If the user notices this or asks, help them review `authorized_keys` on
Holly (`cat ~/.ssh/authorized_keys`) and delete everything except the current
`zibby-holly-persistent` key – but only ever delete entries from authorized_keys with the user's
explicit confirmation.

---

## Typical operations

The commands below are written shorthand as `ssh -p 4444 zibby@192.168.1.4 "..."` for
readability – in practice they always run through `device_bash` and with the key, i.e.
`ssh -p 4444 -i ~/mnt/Documents/.zibby/ssh/id_ed25519_holly -o BatchMode=yes zibby@192.168.1.4 "..."`,
see the section above.

### Browsing files and folders
```bash
ssh -p 4444 zibby@192.168.1.4 "ls -lh /volume1/path/to/folder"
ssh -p 4444 zibby@192.168.1.4 "find /volume1/path -type f -name '*.ext'"
ssh -p 4444 zibby@192.168.1.4 "du -sh /volume1/path/*"
```

### Moving files
```bash
ssh -p 4444 zibby@192.168.1.4 "mv /volume1/source/file.ext /volume1/dest/"
# Bulk move:
ssh -p 4444 zibby@192.168.1.4 "mv /volume1/source/*.ext /volume1/dest/"
```

### Copying files
```bash
ssh -p 4444 zibby@192.168.1.4 "cp -r /volume1/source /volume1/dest"
```

### Deleting files
```bash
# CAUTION: always list what will be deleted first, only then delete
ssh -p 4444 zibby@192.168.1.4 "ls /volume1/path/files-to-delete"
ssh -p 4444 zibby@192.168.1.4 "rm /volume1/path/file.ext"
```

### Finding duplicate files
Synology DSM 7 doesn't come with `fdupes` preinstalled. Use hash-based detection instead:

```bash
# Find duplicates by MD5 hash in a folder
ssh -p 4444 zibby@192.168.1.4 "find /volume1/path -type f | xargs md5sum | sort | awk 'seen[\$1]++ {print}'"

# For an overview: list files with the same size (first pass)
ssh -p 4444 zibby@192.168.1.4 "find /volume1/path -type f -printf '%s %p\n' | sort -n | uniq -Dw10"
```

### Creating a folder
```bash
ssh -p 4444 zibby@192.168.1.4 "mkdir -p /volume1/path/new-folder"
```

---

## Safety rules

1. **Before every deletion**, list the files that will be deleted first and ask the user to
   confirm.
2. **Never use or enter a password** – connect exclusively with the persistent SSH key (see
   above); the user only ever enters a password themselves, once, when adding a new key to
   `authorized_keys`.
3. **Destructive operations** (rm, mv over an existing file) should always be simulated or
   planned out first.
4. **On moves**, check that the destination folder exists (`ls` or `mkdir -p`).

---

## NAS structure

### Volumes
- Main volume: `/volume1/`

### Folders
This is a list of the important folders, not the complete structure. Folders may contain further
subfolders and files.

- /volume1/homes - contains one home folder per NAS user (zibby, anicka, honza, terka, ...)
- /volume1/homes/zibby - my home folder. Also has tmdb_renamer.py and tv_move.sh, the scripts
  behind the tmdb-renamer skill
- /volume1/homes/zibby/Downloads - folder where I download all sorts of things (movies, TV shows,
  porn), unsorted, waiting to be moved into onrop/movie-library
- /volume1/onrop - porn, sorted into one subfolder per performer/studio
- /volume1/media-backup - contains RAW photos and video
- /volume1/movie-library - contains movies, TV shows, concerts, theater recordings and more, sorted
  into subfolders: Movies, "Movies - Kids", "TV Shows", "TV Shows - Kids", Concerts, Theater,
  Standups. Whenever you move files into this folder, always use the tmdb-renamer skill and rename
  the file before moving it
- /volume1/@download - Download Station's own working directory (torrents, transmissiond, pyload),
  separate from homes/zibby/Downloads

---

## Notes on Synology DSM 7

- Synology uses BusyBox – some GNU commands have limited flags.
- `find -printf` may not work; alternative: `find ... | xargs stat`
- `md5sum` is available.
- Root access isn't needed for normal operations on `/volume1/`.
- If a command fails due to permissions, tell the user – don't try to escalate privileges
  yourself.
