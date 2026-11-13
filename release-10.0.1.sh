#!/usr/bin/env bash
set -euo pipefail

VERSION="10.0.1"
TAG="v${VERSION}"
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  printf '%s\n' "Release requires a clean worktree. Commit or remove local changes first." >&2
  exit 1
fi

if [[ -n "${SONATYPE_USERNAME:-}" || -n "${SONATYPE_PASSWORD:-}" ]]; then
  : "${SONATYPE_USERNAME:?SONATYPE_USERNAME must be set with SONATYPE_PASSWORD}"
  : "${SONATYPE_PASSWORD:?SONATYPE_PASSWORD must be set with SONATYPE_USERNAME}"
elif [[ ! -f "${HOME}/.sbt/sonatype_central_credentials" ]]; then
  printf '%s\n' "Missing Sonatype credentials. Set SONATYPE_USERNAME/SONATYPE_PASSWORD or create ~/.sbt/sonatype_central_credentials." >&2
  exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
  printf '%s\n' "GPG is required for Central publishing." >&2
  exit 1
fi

if ! gpg --batch --list-secret-keys --with-colons | grep -q '^sec:'; then
  printf '%s\n' "No GPG secret key is available for signing." >&2
  exit 1
fi

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk}"
export PATH="$JAVA_HOME/bin:$PATH"

SBT=("./sbt/sbt")

"${SBT[@]}" clean test

if [[ "${RUN_INTEGRATION_TESTS:-0}" == "1" ]]; then
  if command -v start-rootless-docker >/dev/null 2>&1; then
    start-rootless-docker env \
      JAVA_HOME="$JAVA_HOME" \
      PATH="$PATH" \
      TESTCONTAINERS_HOST_OVERRIDE="${TESTCONTAINERS_HOST_OVERRIDE:-127.0.0.1}" \
      "${SBT[@]}" IntegrationTest/test
  else
    "${SBT[@]}" IntegrationTest/test
  fi
fi

if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
  if [[ "$(git rev-list -n 1 "$TAG")" != "$(git rev-parse HEAD)" ]]; then
    printf '%s\n' "Tag $TAG already exists on a different commit." >&2
    exit 1
  fi
else
  git tag "$TAG"
fi

"${SBT[@]}" "++2.12.19; publishSigned" "++2.13.13; publishSigned"

BUNDLE="$ROOT/target/arizona-${VERSION}-central-bundle.zip"
rm -f "$BUNDLE"
(
  cd target/sona-staging
  zip -qr "$BUNDLE" .
)

git push origin "$TAG"

printf 'Release bundle: %s\n' "$BUNDLE"
printf '%s\n' "Upload the bundle through Sonatype Central, or run: ./sbt/sbt sonaUpload"
