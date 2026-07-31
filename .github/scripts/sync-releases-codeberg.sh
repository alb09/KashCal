#!/bin/bash
set -euo pipefail

CHECK_LAST_N="${1:-5}"
INITIAL_SYNC="${2:-false}"
SOURCE_REPO="KashCal/KashCal"
TARGET_REPO_CODEBERG="alexb936/KashCal"
CODEBERG_API="https://codeberg.org/api/v1"

if [ -z "$CODEBERG_TOKEN" ]; then
  echo "❌ CODEBERG_TOKEN ist nicht gesetzt!"
  exit 1
fi

if [ "$INITIAL_SYNC" = "true" ]; then
  CHECK_LAST_N=1000
fi

echo "🔍 Prüfe die letzten $CHECK_LAST_N Releases in $SOURCE_REPO (GitHub)..."
# GitHub Releases holen
source_releases=$(gh release list --repo "$SOURCE_REPO" --limit "$CHECK_LAST_N" --json tagName,isDraft -q '.[] | select(.isDraft==false) | .tagName')

if [ -z "$source_releases" ]; then
  echo "ℹ️  Keine Releases gefunden."
  exit 0
fi

synced_count=0
skipped_count=0
failed_count=0
ordered_tags=$(echo "$source_releases" | tac)

while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  echo ""
  # Prüfen ob Release auf Codeberg bereits existiert (und ob es Assets hat)
  existing_release=$(curl -s "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases/tags/$tag" \
    -H "Authorization: token $CODEBERG_TOKEN")
  existing_id=$(echo "$existing_release" | jq -r '.id // empty' 2>/dev/null || echo "")
  existing_asset_count=0
  
  if [ -n "$existing_id" ]; then
    existing_asset_count=$(echo "$existing_release" | jq '.assets | length' 2>/dev/null || echo 0)
  fi

  release_id=""

  if [ -n "$existing_id" ] && [ "$existing_asset_count" -gt 0 ]; then
    echo "⏭️  '$tag' bereits vorhanden mit $existing_asset_count Asset(s) — skip"
    skipped_count=$((skipped_count+1))
    continue
  elif [ -n "$existing_id" ]; then
    echo "⚠️  '$tag' existiert bereits, aber ohne Assets — lade Assets nach..."
    release_id="$existing_id"
  else
    echo "🆕 Neues Release: '$tag' — synce zu Codeberg..."
    # Release-Infos von GitHub holen
    gh release view "$tag" --repo "$SOURCE_REPO" \
      --json name,body,isPrerelease,tagName > /tmp/release_data.json
    name=$(jq -r '.name // .tagName' /tmp/release_data.json)
    body=$(jq -r '.body // ""' /tmp/release_data.json)
    is_prerelease=$(jq -r '.isPrerelease' /tmp/release_data.json)
    # JSON-Escape für Body und Name
    name_escaped=$(echo "$name" | jq -Rs .)
    body_escaped=$(echo "$body" | jq -Rs .)

    # Release zu Codeberg erstellen
    create_response=$(curl -s -w "\n%{http_code}" -X POST "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases" \
      -H "Authorization: token $CODEBERG_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "tag_name": "'"$tag"'",
        "name": '"$name_escaped"',
        "body": '"$body_escaped"',
        "prerelease": '"$is_prerelease"'
      }')
    create_http_code=$(echo "$create_response" | tail -n1)
    create_body=$(echo "$create_response" | sed '$d')

    if [ "$create_http_code" = "201" ]; then
      release_id=$(echo "$create_body" | jq -r '.id')
      echo "✅ Release '$tag' zu Codeberg erstellt (id=$release_id)"
    else
      echo "❌ Fehler bei '$tag' (HTTP $create_http_code): $create_body"
      failed_count=$((failed_count+1))
      continue
    fi
  fi

  # Assets syncen
  asset_dir="/tmp/assets_${tag//\//_}"
  mkdir -p "$asset_dir"
  if gh release download "$tag" --repo "$SOURCE_REPO" -D "$asset_dir" 2>/dev/null; then
    if [ -n "$(ls -A "$asset_dir" 2>/dev/null)" ]; then
      echo "📎 Lade Assets hoch..."
      for asset in "$asset_dir"/*; do
        fname=$(basename "$asset")
        upload_http_code=$(curl -s -o /tmp/upload_resp.json -w "%{http_code}" -X POST \
          "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases/$release_id/assets?name=$fname" \
          -H "Authorization: token $CODEBERG_TOKEN" \
          -F "attachment=@$asset")
        if [ "$upload_http_code" = "201" ]; then
          echo "  ✓ $fname"
        else
          echo "  ❌ $fname (HTTP $upload_http_code): $(cat /tmp/upload_resp.json)"
        fi
      done
    fi
  fi
  rm -rf "$asset_dir"
  synced_count=$((synced_count+1))
done <<< "$ordered_tags"
echo ""
echo "=========================================="
echo "Neu synchronisiert: $synced_count | Übersprungen: $skipped_count | Fehlgeschlagen: $failed_count"
echo "==========================================";
