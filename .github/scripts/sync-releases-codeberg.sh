#!/bin/bash
set -euo pipefail

CHECK_LAST_N="${1:-5}"
INITIAL_SYNC="${2:-false}"

SOURCE_REPO="KashCal/KashCal"
TARGET_REPO_CODEBERG="alexb936/KashCal"
CODEBERG_API="https://codeberg.org/api/v1"

if [ "$INITIAL_SYNC" = "true" ]; then
  CHECK_LAST_N=1000
fi

echo "🔍 Prüfe die letzten $CHECK_LAST_N Releases in $SOURCE_REPO (GitHub)..."

source_releases=$(gh release list --repo "$SOURCE_REPO" --limit "$CHECK_LAST_N" --json tagName,isDraft -q '.[] | select(.isDraft==false) | .tagName')

if [ -z "$source_releases" ]; then
  echo "ℹ️  Keine Releases gefunden."
  exit 0
fi

existing_tags=$(curl -s "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases" \
  -H "Authorization: token $CODEBERG_API_TOKEN" \
  | jq -r '.[].tag_name' 2>/dev/null || echo "")

synced_count=0
skipped_count=0
failed_count=0

ordered_tags=$(echo "$source_releases" | tac)

while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  if echo "$existing_tags" | grep -qx "$tag"; then
    echo "⏭️  '$tag' bereits vorhanden — skip"
    skipped_count=$((skipped_count+1))
    continue
  fi

  echo ""
  echo "🆕 Neues Release: '$tag' — synce zu Codeberg..."

  # Release-Infos von GitHub holen
  gh release view "$tag" --repo "$SOURCE_REPO" \
    --json name,body,isPrerelease,tagName > /tmp/release_data.json

  name=$(jq -r '.name // .tagName' /tmp/release_data.json)
  body=$(jq -r '.body // ""' /tmp/release_data.json)
  is_prerelease=$(jq -r '.isPrerelease' /tmp/release_data.json)

  # Escapen für JSON
  name_escaped=$(echo "$name" | jq -Rs .)
  body_escaped=$(echo "$body" | jq -Rs .)

  # Release zu Codeberg erstellen
  release_response=$(curl -s -X POST "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases" \
    -H "Authorization: token $CODEBERG_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "tag_name": "'"$tag"'",
      "name": '"$name_escaped"',
      "body": '"$body_escaped"',
      "prerelease": '"$is_prerelease"'
    }')

  release_id=$(echo "$release_response" | jq -r '.id // empty')

  if [ -z "$release_id" ]; then
    echo "❌ Fehler beim Erstellen von '$tag'"
    failed_count=$((failed_count+1))
    continue
  fi

  echo "✅ Release '$tag' erstellt (ID: $release_id)"

  # Assets syncen
  asset_dir="/tmp/assets_${tag//\//_}"
  mkdir -p "$asset_dir"

  if gh release download "$tag" --repo "$SOURCE_REPO" -D "$asset_dir" 2>/dev/null; then
    if [ -n "$(ls -A "$asset_dir" 2>/dev/null)" ]; then
      echo "📎 Lade Assets hoch..."
      
      for asset in "$asset_dir"/*; do
        [ -f "$asset" ] || continue
        filename=$(basename "$asset")
        
        if curl -s -X POST "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases/$release_id/assets" \
          -H "Authorization: token $CODEBERG_API_TOKEN" \
          -F "attachment=@$asset" > /dev/null; then
          echo "  ✅ $filename"
        else
          echo "  ❌ $filename fehlgeschlagen"
        fi
      done
    fi
  fi
  rm -rf "$asset_dir"

  synced_count=$((synced_count+1))

done <<< "$ordered_tags"

echo ""
echo "=========================================="
echo "Synchronisiert: $synced_count | Übersprungen: $skipped_count | Fehlgeschlagen: $failed_count"
echo "=========================================="
