#!/usr/bin/env bash
# latest-versions.sh — report the newest upstream version of every tool the
# Dockerfile pins, so the ARG values can be bumped deliberately.
#
# Tool versions are pinned (plan 007) so a given commit always builds the same
# image. Dependabot tracks `FROM` lines and GitHub Actions, not release ARGs, so
# these bumps are manual: run this, compare with the Dockerfile, edit the ARGs,
# and let CI's smoke test vet the result.
#
# Usage: scripts/latest-versions.sh [--check]
#   --check  exit 1 if any pin is behind, for use in a scheduled job
set -euo pipefail

REPOS="
EZA_VERSION eza-community/eza
DUA_VERSION Byron/dua-cli
YAZI_VERSION sxyazi/yazi
GLOW_VERSION charmbracelet/glow
"

DOCKERFILE="$(dirname "$0")/../Dockerfile"
check=0
[ "${1:-}" = "--check" ] && check=1
stale=0

latest_tag() {
    # Follow the /releases/latest redirect; needs no authentication, so no
    # token ever enters the build or this script (see plan 002).
    curl -sILo /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | sed 's#.*/tag/##'
}

pinned() { sed -n "s/^ARG $1=\(.*\)$/\1/p" "$DOCKERFILE"; }

printf '%-14s %-24s %-12s %-12s %s\n' ARG REPO PINNED LATEST STATUS
printf '%s\n' "----------------------------------------------------------------------------"

echo "$REPOS" | while read -r arg repo; do
    [ -z "$arg" ] && continue
    have=$(pinned "$arg")
    want=$(latest_tag "$repo")
    if [ -z "$want" ]; then
        status="UNRESOLVED"
    elif [ "$have" = "$want" ]; then
        status="current"
    else
        status="BEHIND"
        echo "$want" > "/tmp/.stale-$arg"
    fi
    printf '%-14s %-24s %-12s %-12s %s\n' "$arg" "$repo" "$have" "${want:-?}" "$status"
done

# LazyVim is a branch, not a release: compare the pinned commit with HEAD.
lv_have=$(pinned LAZYVIM_REF)
lv_want=$(git ls-remote https://github.com/LazyVim/starter HEAD | cut -f1)
if [ "$lv_have" = "$lv_want" ]; then lv_status="current"; else lv_status="BEHIND"; fi
printf '%-14s %-24s %-12s %-12s %s\n' LAZYVIM_REF LazyVim/starter \
    "${lv_have:0:9}" "${lv_want:0:9}" "$lv_status"

if [ "$check" -eq 1 ]; then
    for arg in EZA_VERSION DUA_VERSION YAZI_VERSION GLOW_VERSION; do
        if [ -f "/tmp/.stale-$arg" ]; then stale=1; rm -f "/tmp/.stale-$arg"; fi
    done
    [ "$lv_status" = "BEHIND" ] && stale=1
    if [ "$stale" -eq 1 ]; then
        echo
        echo "At least one pin is behind. Bump the ARGs in Dockerfile and let CI verify." >&2
        exit 1
    fi
fi

rm -f /tmp/.stale-* 2>/dev/null || true
