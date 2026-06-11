#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: scripts/derive_release_metadata.sh <tag>" >&2
  exit 64
fi

TAG="$1"

if [[ ! "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-(beta|dev\.[0-9]+))?$ ]]; then
  echo "Release tags must match vMAJOR.MINOR.PATCH, vMAJOR.MINOR.PATCH-beta, or vMAJOR.MINOR.PATCH-dev.N, got: $TAG" >&2
  exit 1
fi

APP_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
SUFFIX="${BASH_REMATCH[4]:-}"
RELEASE_VERSION="${TAG#v}"

case "$SUFFIX" in
  "")
    RELEASE_CHANNEL="stable"
    IS_GITHUB_RELEASE="true"
    IS_PRERELEASE="false"
    ;;
  "-beta")
    RELEASE_CHANNEL="beta"
    IS_GITHUB_RELEASE="true"
    IS_PRERELEASE="true"
    ;;
  -dev.*)
    RELEASE_CHANNEL="dev"
    IS_GITHUB_RELEASE="false"
    IS_PRERELEASE="false"
    ;;
  *)
    echo "Unsupported release tag suffix: $SUFFIX" >&2
    exit 1
    ;;
esac

cat <<EOF
RELEASE_VERSION=$RELEASE_VERSION
APP_VERSION=$APP_VERSION
RELEASE_CHANNEL=$RELEASE_CHANNEL
IS_GITHUB_RELEASE=$IS_GITHUB_RELEASE
IS_PRERELEASE=$IS_PRERELEASE
EOF
