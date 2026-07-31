#!/bin/bash
set -euo pipefail

CHECK_LAST_N=5  # wie viele der neuesten Releases geprüft werden sollen

echo "🔍 Prüfe die letzten $CHECK_LAST_N Releases in $SOURCE_REPO..."

source_releases=$(gh release list --repo "$SOURCE_REPO" --limit "$CHECK_LAST_N" --json tagName,isDraft -q '.[] | select(.isDraft==false) | .tagName')

if [ -z "$source_releases" ]; then
  echo "ℹ️  Keine (nicht-Draft) Releases gefunden. Beende."
  exit 0
fi

existing_tags=$(gh release list --repo "$TARGET_REPO" --limit 1000 --json tagName -q '.[].tagName' || echo "")

synced_count=0
skipped_count=0
failed_count=0

# Reihenfolge umkehren, damit ältere zuerst synct werden (chronologisch sinnvoller)
ordered_tags=$(echo "$source_releases" | tac)

while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  if echo "$existing_tags" | grep -qx "$tag"; then
    echo "⏭️  '$tag' bereits vorhanden — skip"
    skipped_count=$((skipped_count+1))
    continue
  fi

  echo ""
  echo "🆕 Neues Release gefunden: '$tag' — synce..."

  gh release view "$tag" --repo "$SOURCE_REPO" \
    --json name,body,isPrerelease,tagName > /tmp/release_data.json

  name=$(jq -r '.name // .tagName' /tmp/release_data.json)
  body=$(jq -r '.body // ""' /tmp/release_data.json)
  is_prerelease=$(jq -r '.isPrerelease' /tmp/release_data.json)

  flags=""
  [ "$is_prerelease" = "true" ] && flags="--prerelease"

  echo "$body" > /tmp/notes.md

  if gh release create "$tag" \
      --repo "$TARGET_REPO" \
      --title "$name" \
      --notes-file /tmp/notes.md \
      $flags; then
    echo "✅ Release '$tag' erstellt"
  else
    echo "❌ Fehler bei '$tag' (Tag evtl. noch nicht im Fork-Code vorhanden). Skip."
    failed_count=$((failed_count+1))
    continue
  fi

  # Assets syncen
  asset_dir="/tmp/assets_${tag//\//_}"
  mkdir -p "$asset_dir"

  if gh release download "$tag" --repo "$SOURCE_REPO" -D "$asset_dir" 2>/dev/null; then
    if [ -n "$(ls -A "$asset_dir" 2>/dev/null)" ]; then
      echo "📎 Lade Assets hoch..."
      gh release upload "$tag" "$asset_dir"/* --repo "$TARGET_REPO" --clobber
    fi
  fi
  rm -rf "$asset_dir"

  synced_count=$((synced_count+1))

done <<< "$ordered_tags"

echo ""
echo "=========================================="
echo "Neu synct: $synced_count | Übersprungen: $skipped_count | Fehlgeschlagen: $failed_count"
echo "=========================================="

if [ "$synced_count" -eq 0 ] && [ "$failed_count" -eq 0 ]; then
  echo "✅ Alles bereits aktuell."
fi
