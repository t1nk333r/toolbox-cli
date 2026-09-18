# toolbox

A portable CLI toolbox Docker image based on Ubuntu 24.04, packed with common
system administration and media processing tools. Built for always-on hosts
like TrueNAS SCALE, where installing native packages is not an option.

## Included tools

- **Files & disk**: ncdu, dua-cli, eza, fd-find, file, 7zip, zstd, pigz, unzip, unrar, rsync
- **Media**: ffmpeg, ffmpegthumbnailer, mediainfo, exiftool, imagemagick, pdftoppm
- **Text & search**: neovim, ripgrep, bat, jq, fzf, less, glow
- **System**: htop, tmux, curl, wget, git, openssh
- **Navigation**: yazi (terminal file manager)

## Quick start

```bash
docker compose up -d
docker exec -it -u toolbox toolbox bash
```

By default your home directory is mounted at `/work` inside the container,
which is also the working directory. To mount somewhere else, copy
`.env.example` to `.env` and set `TOOLBOX_MOUNT`:

```bash
cp .env.example .env
# then edit .env, e.g. TOOLBOX_MOUNT=/home/you/projects
```

`.env` is gitignored — keep local overrides there, not in `compose.yaml`.

## Remote access (SSH)

The image runs a key-only SSH server, so you can reach the container directly
instead of going through `docker exec`. The same session carries the reverse
tunnel that [`open`](#opening-files-on-your-own-machine) uses.

Authorize a public key — nothing else grants access — either inline via the
`SSH_PUBKEY` environment variable or by mounting a file at `/authorized_keys`:

```bash
# compose.yaml wires SSH_PUBKEY from TOOLBOX_SSH_PUBKEY in .env
echo "TOOLBOX_SSH_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)" >> .env
```

Host `2222` maps to container `22`, since `22` is usually taken by the host:

```bash
ssh -p 2222 toolbox@<host>       # plain shell
scripts/toolbox-ssh           # shell + the reverse tunnel `open` needs
```

Host keys are generated on first start into `/etc/ssh/host_keys`, which
`compose.yaml` keeps on a named volume. Without that volume every redeploy
would present a new host identity and your client would refuse to connect until
you cleared the old `known_hosts` entry.

## Opening files on your own machine

The container has no GUI, so viewers run on **your** machine. The helper
scripts live in `scripts/` and are run locally, never installed in the image.

| Script | Runs on | Purpose |
|---|---|---|
| `toolbox-ssh` | Linux, macOS | SSH plus the reverse tunnel `open` needs |
| `toolbox-opend` | Linux, macOS | Listener that opens whatever `open` sends |
| `toolbox-opend.ps1` | Windows | Same listener, PowerShell |
| `toolbox-view` | Linux, macOS | Pull one remote file and open it |
| `toolbox-view.ps1` | Windows | Same, PowerShell |

> **TODO**: the two `.ps1` scripts have never been executed — they were written
> on a machine with no PowerShell. Every other part of this workflow is verified
> at runtime. Run them against a real host before relying on them.

### `open <file>` inside the container (recommended)

Work in the container and just `open` things — no paths to retype locally.

```bash
# Once, on your local machine:
scripts/toolbox-opend &      # listener
scripts/toolbox-ssh          # ssh + reverse tunnel

# Then, inside the container:
cd /mnt/pool/docs
open report.pdf              # appears in YOUR pdf viewer
open photo.png               # appears in YOUR image viewer
```

Yazi uses this too: `<Enter>` on an image, PDF, or other non-text file sends it
to your local viewer.

`open` is installed in the image (also as `xdg-open`, so tools that shell out to
it work). It is a pure shell script using bash's `/dev/tcp` — no GUI libraries,
no extra packages.

`toolbox-ssh` adds `-R 17654:127.0.0.1:17654`, so port 17654 inside the
container points back at the `toolbox-opend` listener on your machine. `open`
streams the file into that tunnel; the listener saves it to a temp file and
hands it to your desktop's default application. Change the port with
`TOOLBOX_OPEN_PORT` on both ends.

This deliberately gives the container **no** access to your machine: it holds no
credentials for you and can reach nothing but that one loopback port, only for
as long as your SSH session lives.

On Windows, run the PowerShell listener and forward the port yourself:

```powershell
.\scripts\toolbox-opend.ps1
ssh -R 17654:127.0.0.1:17654 -p 2222 toolbox@<host>
```

### Pulling a single file from the client side

When you already know the path and don't want a listener running, fetch it
directly. Images render inline if your terminal supports a graphics protocol;
otherwise the file is downloaded and opened.

```bash
# Linux / macOS
export TOOLBOX_HOST=toolbox@<host>                 # or pass -H
scripts/toolbox-view /mnt/pool/docs/report.pdf  # download + xdg-open/open
scripts/toolbox-view -d /mnt/pool/pics/x.png    # force download instead of inline
```

```powershell
# Windows
$env:TOOLBOX_HOST = "toolbox@<host>"
.\scripts\toolbox-view.ps1 /mnt/pool/docs/report.pdf
```

Openers used: `xdg-open` (Linux), `open` (macOS), `Start-Process` (Windows).
Override the destination with `-H`/`-p` (`-SshHost`/`-Port` on Windows) or the
`TOOLBOX_HOST` / `TOOLBOX_PORT` environment variables.

### Previewing in the terminal

With a graphics-capable terminal (kitty, ghostty, foot, WezTerm, iTerm2),
images and the first page of PDFs render inline over SSH:

```bash
ssh -p 2222 -t toolbox@<host> yazi /mnt                       # browse with previews
ssh -p 2222 toolbox@<host> 'cat /path/img.png' | kitten icat   # one image, kitty
```

Terminals without a graphics protocol get no inline preview; use one of the
options above instead.

### Mounting the whole tree

For heavy browsing, mount it and use your normal tools (needs sshfs/macFUSE):

```bash
sshfs -p 2222 toolbox@<host>:/mnt ~/toolbox
```

## Configuration

Yazi configuration lives in `config/yazi/` and is baked into the image at build
time. To customize, edit those files and rebuild.

Openers use yazi's `%s` placeholders (`%s1` for the first selected file). The
older `"$@"` convention was removed in yazi 25.12 and silently passes no files.

## Deploying on TrueNAS SCALE

TrueNAS SCALE can't install native packages, and anything you did install
wouldn't survive an OS update. A persistent container you `docker exec` or SSH
into is the durable way to keep these tools around.

Two things differ from a desktop setup:

**Mount your datasets, not your home directory.** The default mount is the host
`$HOME`, which on a NAS is not where your data lives. Either set `TOOLBOX_MOUNT`
in `.env` to a pool path:

```bash
TOOLBOX_MOUNT=/mnt/tank
```

or uncomment and edit the per-dataset examples in `compose.yaml` for finer
control over what the container can reach. Pool and dataset names are specific
to your installation, so nothing is mounted by default.

**Match `PGID` to your datasets.** Files the toolbox writes carry the login
user's ownership — see [Running as non-root](#running-as-non-root). The default
`568:568` is TrueNAS SCALE's `apps` id, which is what its datasets normally use.

## Running as non-root

You log in as an unprivileged user (`toolbox`, uid/gid `568:568` by default), so
anything written into a mounted dataset carries that ownership instead of
root's. Root SSH login is disabled.

**Find the right id for your host** — the dataset owner is authoritative:

```bash
ls -ln /mnt/<pool>/<dataset>
```

TrueNAS SCALE commonly uses `568` (`apps`). This matters more than it looks:
those datasets are typically mode `770` owned by `root:568`, granting **no**
access to "others", so a login user outside group 568 cannot read them at all.
Set `PUID`/`PGID` in `.env` if your host differs.

**The identity is baked at build time.** Changing `PUID`/`PGID` needs
`docker compose build`, not a restart — a restart silently keeps the old id.

**Root is still reachable**, it is just not the login user. `apt-get` and other
privileged work go through:

```bash
docker exec -u 0 toolbox bash      # root shell inside the container
```

Nothing installed that way survives a rebuild; add lasting tools to the
`Dockerfile`. The image ships no `sudo`, deliberately.

The container's PID 1 remains root because sshd needs it — for host keys,
privilege separation, and binding port 22. Only your *session* is unprivileged.

## Image tags and rollback

Every push to `main` publishes two tags:

- `:latest` — moves with every build
- `:<commit-sha>` — immutable, never overwritten

To roll back, point `compose.yaml` at a SHA tag and re-pull:

```bash
docker compose pull && docker compose up -d
```

Tool versions are pinned with build `ARG`s (`EZA_VERSION`, `DUA_VERSION`,
`YAZI_VERSION`, `GLOW_VERSION`, `LAZYVIM_REF`), so a given commit always builds
the same image. Without them, two builds of one commit a month apart produce
different images and there is nothing to roll back *to*.

Dependabot watches the `FROM` line and the GitHub Actions, but **not** those
release `ARG`s, so bumping them is deliberate:

```bash
scripts/latest-versions.sh           # show pinned vs. latest
scripts/latest-versions.sh --check   # exit 1 if any pin is behind
```

Edit the `ARG`s, then let CI's smoke test vet the result — a withdrawn or
mistyped tag fails the build rather than reaching the registry.

## Using the published image

```bash
docker compose pull
```

Because `compose.yaml` defines a build context, `docker compose up` builds the
image locally if it is not already present. Run `docker compose pull` first if
you want the prebuilt image from the registry instead.

## Building

```bash
docker compose build
```

This takes several minutes — it installs the full ffmpeg and imagemagick
suites. Packages are installed with `--no-install-recommends`, which keeps out
roughly 340MB of GPU, GUI and speech dependencies that those two suites
otherwise pull in. The image is tagged for GitHub Container Registry by
default; update the `image:` field in `compose.yaml` to point at your registry.

## Aliases (included in image)

- `cat` -> `batcat --paging=never`
- `bat` -> `batcat --paging=never`
- `ls` -> `eza --icons`
- `ll` -> `eza -la --icons`
- `la` -> `eza -a --icons`
- `fd` -> `fdfind`

## License

MIT
