#!/usr/bin/env bash
#
# One-time setup for running the laserbeamFoam solvers in Docker.
#
# This repository targets OpenFOAM-10 (the openfoam.org fork). Rather than
# asking you to build OpenFOAM-10 yourself, this script installs Docker, pulls
# the official OpenFOAM-10 image, and drops a small launcher called `of10` into
# your PATH.
#
# Usage:
#   ./setup.sh              install Docker if needed, pull the image, install of10
#   ./setup.sh --build      the above, then compile the solvers in the container
#   ./setup.sh --help
#
# Afterwards, from any directory under your home:
#   of10                    open an OpenFOAM-10 shell
#   of10 blockMesh          run a single OpenFOAM command
#
# Safe to run more than once; every step is skipped if it is already done.

set -euo pipefail

IMAGE="openfoam/openfoam10-paraview56"
BIN_DIR="$HOME/.local/bin"
OF10="$BIN_DIR/of10"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DO_BUILD=false

# --------------------------------------------------------------------------- #
# Output helpers
# --------------------------------------------------------------------------- #

if [ -t 1 ]; then
    C_BOLD=$'\033[1m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_OFF=$'\033[0m'
else
    C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_OFF=""
fi

step() { printf '\n%s==>%s %s%s%s\n' "$C_BLUE" "$C_OFF" "$C_BOLD" "$*" "$C_OFF"; }
ok()   { printf '    %s[ok]%s %s\n'   "$C_GREEN"  "$C_OFF" "$*"; }
note() { printf '    %s[..]%s %s\n'   "$C_YELLOW" "$C_OFF" "$*"; }
die()  { printf '\n%serror:%s %s\n\n' "$C_RED"    "$C_OFF" "$*" >&2; exit 1; }

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's|^# \{0,1\}||'; exit 0; }

# --------------------------------------------------------------------------- #
# Arguments
# --------------------------------------------------------------------------- #

for arg in "$@"; do
    case "$arg" in
        --build)     DO_BUILD=true ;;
        -h|--help)   usage ;;
        *)           die "unknown option '$arg' (try --help)" ;;
    esac
done

# --------------------------------------------------------------------------- #
# Sanity checks
# --------------------------------------------------------------------------- #

step "Checking your system"

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not as root.
       The script calls sudo by itself where it needs to. Running the whole
       thing as root would install the of10 launcher into root's home."

case "$REPO_DIR/" in
    "$HOME"/*) ;;
    *) die "This repository lives at
           $REPO_DIR
       which is outside your home directory ($HOME). Only your home is
       shared with the container, so the solver would not be able to see
       these files. Move the repository somewhere under $HOME and rerun." ;;
esac

if [ "$(uname -s)" = "Darwin" ]; then
    die "This script only installs Docker on Linux.
       On macOS, install Docker Desktop from https://docker.com/products/docker-desktop
       first, then rerun this script -- it will skip the install and just set
       up the image and the of10 launcher."
fi

[ "$(uname -s)" = "Linux" ] || die "Unsupported operating system: $(uname -s)"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || die "sudo is not installed, and it is needed to install Docker."
    SUDO="sudo"
fi

ok "Linux, running as $(id -un), repository under \$HOME"

# --------------------------------------------------------------------------- #
# 1. Docker
# --------------------------------------------------------------------------- #

step "Installing Docker"

if command -v docker >/dev/null 2>&1; then
    ok "Docker is already installed ($(docker --version 2>/dev/null || echo 'version unknown'))"
else
    distro="unknown"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        distro="$(. /etc/os-release && echo "${ID:-unknown}")"
    fi
    note "Docker not found; installing for '$distro'"

    case "$distro" in
        arch|manjaro|endeavouros|garuda)
            $SUDO pacman -Sy --needed --noconfirm docker
            ;;
        ubuntu|debian|linuxmint|pop|raspbian|elementary|zorin|kali|fedora|centos|rhel|rocky|almalinux|ol|sles|opensuse*)
            # Docker's own install script. Downloaded first so you can read it.
            script="$(mktemp)"
            note "Downloading Docker's official install script to $script"
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL https://get.docker.com -o "$script"
            elif command -v wget >/dev/null 2>&1; then
                wget -qO "$script" https://get.docker.com
            else
                die "Neither curl nor wget is installed; cannot download the Docker installer."
            fi
            note "Running it (this needs sudo and takes a few minutes)"
            $SUDO sh "$script"
            rm -f "$script"
            ;;
        *)
            die "Do not know how to install Docker on '$distro'.
       Install it by hand -- see https://docs.docker.com/engine/install/ --
       then rerun this script. Everything else will still be set up for you."
            ;;
    esac
    ok "Docker installed"
fi

# --------------------------------------------------------------------------- #
# 2. Docker service
# --------------------------------------------------------------------------- #

step "Starting the Docker service"

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    if systemctl is-active --quiet docker; then
        ok "Docker is already running"
    else
        $SUDO systemctl enable --now docker
        ok "Docker started, and set to start on boot"
    fi
else
    # WSL without systemd, or a container-in-container setup.
    note "No systemd here; assuming Docker is managed some other way"
fi

# --------------------------------------------------------------------------- #
# 3. Run Docker without sudo
# --------------------------------------------------------------------------- #

step "Letting you run Docker without sudo"

if id -nG "$(id -un)" | tr ' ' '\n' | grep -qx docker; then
    ok "You are already in the 'docker' group"
    IN_GROUP_ALREADY=true
else
    getent group docker >/dev/null 2>&1 || $SUDO groupadd docker
    $SUDO usermod -aG docker "$(id -un)"
    ok "Added $(id -un) to the 'docker' group"
    IN_GROUP_ALREADY=false
fi

# Group changes only apply to new logins, so this shell may still need sudo.
NEEDS_RELOGIN=false
if docker info >/dev/null 2>&1; then
    DOCKER=(docker)
    ok "Docker works without sudo"
else
    if $SUDO docker info >/dev/null 2>&1; then
        DOCKER=($SUDO docker)
        NEEDS_RELOGIN=true
        note "Using sudo for the rest of this script (group change is not live yet)"
    else
        die "Docker is installed but not responding, with or without sudo.
       Try:  sudo systemctl status docker"
    fi
fi

# --------------------------------------------------------------------------- #
# 4. The OpenFOAM-10 image
# --------------------------------------------------------------------------- #

step "Fetching the OpenFOAM-10 image"

if "${DOCKER[@]}" image inspect "$IMAGE" >/dev/null 2>&1; then
    ok "$IMAGE is already downloaded"
else
    note "Pulling $IMAGE (about 2 GB, this takes a while)"
    "${DOCKER[@]}" pull "$IMAGE"
    ok "Image downloaded"
fi

# --------------------------------------------------------------------------- #
# 5. The of10 launcher
# --------------------------------------------------------------------------- #

step "Installing the 'of10' launcher"

mkdir -p "$BIN_DIR"

cat > "$OF10" <<'OF10'
#!/usr/bin/env bash
#
# Run OpenFOAM-10 in Docker, in whatever directory you are standing in.
#
#   of10                 open an interactive OpenFOAM-10 shell
#   of10 blockMesh       run one command and exit
#   of10 ./Allrun        run a case script
#
# Your home directory is mounted at the same path inside the container, and
# the container runs as you, so files it writes belong to you. The container
# itself is thrown away on exit -- anything written outside your home is lost.
#
# Override the image with:  OF10_IMAGE=some/other:tag of10

set -euo pipefail

IMAGE="${OF10_IMAGE:-openfoam/openfoam10-paraview56}"

case "$PWD/" in
    "$HOME"/*) ;;
    *)  echo "of10: only directories under $HOME are visible inside the container." >&2
        echo "of10: you are currently in $PWD" >&2
        exit 1 ;;
esac

run=(
    run --rm
    -u "$(id -u):$(id -g)"
    -e HOME="$HOME"
    -e USER="$(id -un)"
    -v "$HOME:$HOME"
    -w "$PWD"
)

# Keep stdin attached always, so `of10 cmd < input` and `echo ... | of10`
# work. Only ask for a terminal when there really is one on both ends,
# otherwise Docker mangles the output of piped and scripted runs.
run+=(-i)
have_tty=false
if [ -t 0 ] && [ -t 1 ]; then
    run+=(-t)
    have_tty=true
fi

# Both branches below override the image's entrypoint. The image ships
# ENTRYPOINT ["/bin/sh","-c","/bin/sh -c \"/entry.sh\""], a fixed string, so
# any command you hand to `docker run` is silently thrown away.

if [ "$#" -eq 0 ] && $have_tty; then
    # Interactive shell. Go through the image's own /entry.sh: it sets up
    # nss_wrapper (so your numeric user id resolves to a name inside the
    # container) and then execs bash, which reads /etc/bash.bashrc, which is
    # where the image sources the OpenFOAM settings. It has to be started as
    # `sh /entry.sh` because its shebang line reads "#/bin/sh" -- the "!" is
    # missing, so the kernel cannot run it on its own.
    exec docker "${run[@]}" --entrypoint /bin/sh "$IMAGE" /entry.sh
else
    # No terminal, so `of10` on its own means a script is being fed in on
    # stdin. Run that through bash below rather than through /entry.sh: a
    # non-interactive bash never reads /etc/bash.bashrc, so it would not
    # have the OpenFOAM settings.
    [ "$#" -eq 0 ] && set -- bash

    # A single command. /entry.sh prints a welcome banner on stdout, which
    # would corrupt anything you pipe or capture, so do its nss_wrapper setup
    # here instead and stay quiet. A non-interactive bash also skips
    # /etc/bash.bashrc, so the OpenFOAM settings are sourced explicitly.
    exec docker "${run[@]}" --entrypoint /bin/bash "$IMAGE" -c '
        u=$(id -u); g=$(id -g)
        if [ "$u" != 0 ] && [ -f /usr/lib/libnss_wrapper.so ]; then
            sed -e "s/^openfoam:/ignore:/" /etc/passwd > /tmp/passwd.nss_wrapper
            echo "openfoam:x:$u:$g:openfoam,,,:/home/openfoam:/bin/bash" \
                >> /tmp/passwd.nss_wrapper
            sed -e "s/^openfoam:/ignore:/" /etc/group > /tmp/group.nss_wrapper
            echo "openfoam:x:$g:" >> /tmp/group.nss_wrapper
            export NSS_WRAPPER_PASSWD=/tmp/passwd.nss_wrapper
            export NSS_WRAPPER_GROUP=/tmp/group.nss_wrapper
            export LD_PRELOAD=/usr/lib/libnss_wrapper.so
        fi
        . /opt/openfoam10/etc/bashrc >/dev/null
        exec "$@"' of10 "$@"
fi
OF10

chmod +x "$OF10"
ok "Wrote $OF10"

# --------------------------------------------------------------------------- #
# 6. PATH
# --------------------------------------------------------------------------- #

step "Making sure $BIN_DIR is on your PATH"

if printf '%s' ":$PATH:" | grep -q ":$BIN_DIR:"; then
    ok "Already on your PATH"
    PATH_ADDED=""
else
    case "$(basename "${SHELL:-/bin/bash}")" in
        zsh)  rcfile="$HOME/.zshrc" ;;
        bash) rcfile="$HOME/.bashrc" ;;
        *)    rcfile="$HOME/.profile" ;;
    esac
    if [ -f "$rcfile" ] && grep -q 'laserbeamFoam setup.sh' "$rcfile"; then
        ok "Already added to $rcfile by an earlier run"
    else
        {
            echo ""
            echo "# added by laserbeamFoam setup.sh"
            echo 'export PATH="$HOME/.local/bin:$PATH"'
        } >> "$rcfile"
        ok "Added to $rcfile"
    fi
    PATH_ADDED="$rcfile"
    export PATH="$BIN_DIR:$PATH"
fi

# --------------------------------------------------------------------------- #
# 7. Check it works
# --------------------------------------------------------------------------- #

step "Checking the container"

version="$("${DOCKER[@]}" run --rm --entrypoint /bin/bash "$IMAGE" \
    -c '. /opt/openfoam10/etc/bashrc >/dev/null; echo "$WM_PROJECT_VERSION"' 2>/dev/null || true)"

if [ "$version" = "10" ]; then
    ok "OpenFOAM-$version responds inside the container"
else
    die "The container started but did not report OpenFOAM-10.
       Got: '${version:-nothing}'"
fi

# --------------------------------------------------------------------------- #
# 8. Optionally build the solvers
# --------------------------------------------------------------------------- #

if $DO_BUILD; then
    step "Compiling the solvers (this takes 10-30 minutes)"
    if $NEEDS_RELOGIN; then
        note "Your 'docker' group membership is not active in this shell yet,"
        note "so the build cannot run through of10 right now."
        note "Log out and back in, then run:  cd $REPO_DIR && of10 ./Allwmake -j"
        DO_BUILD=false
    else
        ( cd "$REPO_DIR" && of10 ./Allwmake -j )
        ok "Solvers compiled"
    fi
fi

# --------------------------------------------------------------------------- #
# Done
# --------------------------------------------------------------------------- #

printf '\n%s%s Setup finished. %s\n\n' "$C_BOLD" "$C_GREEN" "$C_OFF"

n=0
next() { n=$((n + 1)); printf '  %d. %s\n' "$n" "$1"; }

if $NEEDS_RELOGIN; then
    next "Log out and log back in (or reboot). This is what makes your new
     'docker' group membership take effect. Until you do, docker only
     works with sudo."
elif [ -n "$PATH_ADDED" ]; then
    next "Open a new terminal, or run:  source $PATH_ADDED"
fi

if ! $DO_BUILD; then
    next "Build the solvers, once:
       cd $REPO_DIR && of10 ./Allwmake -j"
fi

next "Run a tutorial:
       cd $REPO_DIR/tutorials/ss316L_1track_bp && of10 ./Allrun"

printf '\n  Day to day, %sof10%s on its own gives you an OpenFOAM-10 shell in the\n' "$C_BOLD" "$C_OFF"
printf '  current directory, and %sof10 <command>%s runs one command and exits.\n\n' "$C_BOLD" "$C_OFF"
