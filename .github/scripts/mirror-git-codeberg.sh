#!/bin/bash
# Mirrors main and all tags 1:1 from the official GitHub repo to Codeberg.
# Reads upstream directly (not the fork), so Codeberg never depends on the fork's tags.
set -euo pipefail
: "${SSH_KEY:?SSH_KEY is not set}"
UPSTREAM_URL="https://github.com/KashCal/KashCal.git"
CODEBERG_SSH="git@codeberg.org:alexb936/KashCal.git"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q

git fetch -q --no-tags "$UPSTREAM_URL" '+refs/heads/main:refs/upstream/main' '+refs/tags/*:refs/tags/*'
tag_count=$(git tag | wc -l)
# --prune below deletes every Codeberg tag without a local twin: never run it on an empty fetch
if [ "$tag_count" -eq 0 ]; then
  echo "❌ Upstream returned no tags — abort (would prune all Codeberg tags)"
  exit 1
fi
echo "📥 Upstream: main + $tag_count tag(s)"

install -m 600 /dev/null "$work/key"
echo "$SSH_KEY" > "$work/key"
ssh-keyscan codeberg.org > "$work/known_hosts" 2>/dev/null
export GIT_SSH_COMMAND="ssh -i $work/key -o IdentitiesOnly=yes -o UserKnownHostsFile=$work/known_hosts -o StrictHostKeyChecking=yes"

git remote add codeberg "$CODEBERG_SSH"
git push --force --prune codeberg refs/upstream/main:refs/heads/main 'refs/tags/*:refs/tags/*'
