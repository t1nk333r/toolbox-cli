# toolbox

A portable CLI toolbox Docker image based on Ubuntu 24.04, packed with common system administration and media processing tools.

## Included tools

- **Files & disk**: ncdu, dua-cli, eza, fd-find, file, 7zip, zstd, pigz, unzip, unrar
- **Media**: ffmpeg, ffmpegthumbnailer, mediainfo, exiftool, imagemagick
- **Text & search**: neovim, ripgrep, bat, jq, fzf, less, glow
- **System**: htop, tmux, curl, wget, git
- **Navigation**: yazi (terminal file manager)

## Quick start

```bash
docker compose up -d
docker exec -it toolbox bash
```

By default your home directory is mounted at `/work` inside the container,
which is also the working directory. To mount somewhere else, copy
`.env.example` to `.env` and set `TOOLBOX_MOUNT`:

```bash
cp .env.example .env
# then edit .env, e.g. TOOLBOX_MOUNT=/home/you/projects
```

`.env` is gitignored — keep local overrides there, not in `compose.yaml`.

## Using the published image

```bash
docker compose pull
```

Because `compose.yaml` defines a build context, `docker compose up` will build
the image locally if it is not already present. Run `docker compose pull` first
if you want the prebuilt image from the registry instead.

## Building

```bash
docker compose build
```

This takes several minutes — it installs the full ffmpeg and imagemagick
suites. The image is tagged for GitHub Container Registry by default; update
the `image:` field in `compose.yaml` to point at your registry of choice.

## Configuration

Yazi configuration lives in `config/yazi/` and is baked into the image at build
time. To customize, edit the files in `config/yazi/` and rebuild.

## Deploying on TrueNAS SCALE

This image targets TrueNAS SCALE, an always-on storage appliance where you
can't install native packages and anything you did install wouldn't survive an
OS update. A persistent container you `docker exec` into is the durable way to
keep these tools around.

Two things differ from a desktop setup:

**Mount your datasets, not your home directory.** The default mount is the
host `$HOME`, which on a NAS is not where your data lives. Either set
`TOOLBOX_MOUNT` in `.env` to a pool path:

```bash
TOOLBOX_MOUNT=/mnt/tank
```

or uncomment and edit the per-dataset examples in `compose.yaml` for finer
control over what the container can reach. Pool and dataset names are specific
to your installation, so nothing is mounted by default.

**Files are created as root.** The container runs as root, so anything it
writes into a mounted dataset is owned by `root`. If that conflicts with how
other apps access those datasets, you will need to `chown` afterwards. Running
as a non-root user with a matching UID/GID is tracked as a separate change.

## Remote access (SSH)

The image runs a key-only SSH server, so you can reach the container directly.
The same session also carries the reverse tunnel that `open` uses to put files
on your desktop.

Authorize a public key (nothing else grants access) either inline via the
`SSH_PUBKEY` environment variable or by mounting a file at `/authorized_keys`:

```bash
# compose.yaml already wires SSH_PUBKEY from TOOLBOX_SSH_PUBKEY in .env
echo "TOOLBOX_SSH_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)" >> .env
```

Ports: host `2222` -> container `22` (`22` is usually taken by the host).

```bash
ssh -p 2222 root@<host>       # plain shell
scripts/toolbox-ssh           # shell + the reverse tunnel that `open` needs
```

## Viewing PDFs and images in your local environment

The container has no GUI — viewers run on **your** machine. Two ways:

### Inline in the terminal (no copy)

If your terminal speaks a graphics protocol (kitty, ghostty, foot, WezTerm,
iTerm2), images and the first page of PDFs (via `pdftoppm`) render inline:

```bash
ssh -p 2222 -t root@<host> yazi /mnt          # browse; previews appear inline
ssh -p 2222 root@<host> 'cat /path/img.png' | kitten icat   # one image, kitty
```

### `open <file>` from inside the container (recommended)

The most natural way: work in the container and just `open` things, with no
paths to retype on the client side.

```bash
# Once, on your local machine:
scripts/toolbox-opend &      # listener that opens whatever arrives
scripts/toolbox-ssh          # ssh + the reverse tunnel, in one command

# Then, inside the container:
cd /mnt/deimos/media/docs
open report.pdf              # appears in YOUR pdf viewer
open photo.png               # appears in YOUR image viewer
```

`open` is installed in the image (also as `xdg-open`, so tools that shell out
to it work). It is a pure shell script using bash's `/dev/tcp` — no GUI
libraries, no extra packages.

How it works: `toolbox-ssh` adds `-R 17654:127.0.0.1:17654`, so port 17654
inside the container points back at the `toolbox-opend` listener on your
machine. `open` streams the file into that tunnel; the listener saves it to a
temp file and hands it to your desktop's default application.

This deliberately gives the container **no** access to your machine: it holds
no credentials for you and cannot reach anything except the one loopback port,
only for as long as your SSH session lives.

On Windows, use the PowerShell listener with the built-in OpenSSH client:

```powershell
.\scripts\toolbox-opend.ps1
ssh -R 17654:127.0.0.1:17654 -p 2222 root@<host>
```

Change the port with `TOOLBOX_OPEN_PORT` on both ends.

Yazi is wired to this too: pressing `<Enter>` on an image, PDF, or any other
non-text file runs the same `open`, so it lands in your local viewer.

### Open in your desktop's default app — Linux, macOS, Windows

`scripts/toolbox-view` (Linux/macOS) and `scripts/toolbox-view.ps1` (Windows)
stream a remote file to your machine and hand it to the OS default application
(multi-page/interactive PDFs, or any non-graphics terminal). They install
nothing on the container.

```bash
# Linux / macOS
export TOOLBOX_HOST=root@<host>          # or pass -H
scripts/toolbox-view /mnt/tank/docs/report.pdf        # download + xdg-open/open
scripts/toolbox-view /mnt/tank/pics/photo.png         # inline if terminal supports it
scripts/toolbox-view -d /mnt/tank/pics/photo.png      # force download + open
```

```powershell
# Windows (PowerShell, built-in OpenSSH client)
$env:TOOLBOX_HOST = "root@<host>"
.\scripts\toolbox-view.ps1 /mnt/tank/docs/report.pdf  # scp + Start-Process
```

Per-OS opener: `xdg-open` (Linux), `open` (macOS), `Start-Process` (Windows).
Override host/port with `-H`/`-p` (`-SshHost`/`-Port` on Windows) or the
`TOOLBOX_HOST` / `TOOLBOX_PORT` environment variables.

Prefer mounting the whole tree instead? `sshfs -p 2222 root@<host>:/mnt
~/toolbox` (Linux/macOS, needs sshfs/macFUSE) then open files normally.

## Aliases (included in image)

- `cat` -> `batcat --paging=never`
- `bat` -> `batcat --paging=never`
- `ls` -> `eza --icons`
- `ll` -> `eza -la --icons`
- `la` -> `eza -a --icons`
- `fd` -> `fdfind`

## License

MIT
