#!/bin/bash
set -euo pipefail
CHECK_LAST_N="${1:-5}"
INITIAL_SYNC="${2:-false}"
APK_COUNT="${3:-0}"
APK_DIRECTION="${4:-newest}"
MAX_APK_RETAIN="${5:-27}"
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
# GitHub Releases holen (explizit nach Veröffentlichungsdatum sortiert, neueste zuerst)
source_releases=$(gh release list --repo "$SOURCE_REPO" --limit "$CHECK_LAST_N" --json tagName,isDraft,publishedAt \
  -q 'sort_by(.publishedAt) | reverse | .[] | select(.isDraft==false) | .tagName')
if [ -z "$source_releases" ]; then
  echo "ℹ️  Keine Releases gefunden."
  exit 0
fi
synced_count=0
skipped_count=0
failed_count=0
apk_uploaded_this_run=0

# Chronologisch alt -> neu für die Erstellreihenfolge auf Codeberg
mapfile -t ordered_tags_arr < <(echo "$source_releases" | tac)
total_tags=${#ordered_tags_arr[@]}

echo "📊 $total_tags Release(s) im aktuellen Sync-Fenster."
echo "🎯 APK-Upload: $APK_COUNT Release(s), Richtung: $APK_DIRECTION"

# Set der Tags bestimmen, für die APKs hochgeladen werden sollen
declare -A apk_eligible
if [ "$APK_COUNT" -gt 0 ] 2>/dev/null; then
  if [ "$APK_DIRECTION" = "oldest" ]; then
    # die ersten (ältesten) N Tags in der Liste
    for ((i=0; i<total_tags && i<APK_COUNT; i++)); do
      apk_eligible["${ordered_tags_arr[$i]}"]=1
    done
  else
    # die letzten (neuesten) N Tags in der Liste
    start=$((total_tags - APK_COUNT))
    [ "$start" -lt 0 ] && start=0
    for ((i=start; i<total_tags; i++)); do
      apk_eligible["${ordered_tags_arr[$i]}"]=1
    done
  fi
fi

for tag in "${ordered_tags_arr[@]}"; do
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

  # Soll für diesen Tag ein APK hochgeladen werden?
  should_sync_apk=false
  [ -n "${apk_eligible[$tag]:-}" ] && should_sync_apk=true

  release_id=""

  if [ -n "$existing_id" ] && [ "$existing_asset_count" -gt 0 ]; then
    echo "⏭️  '$tag' bereits vorhanden mit $existing_asset_count Asset(s) — skip"
    skipped_count=$((skipped_count+1))
    continue
  elif [ -n "$existing_id" ] && [ "$should_sync_apk" != "true" ]; then
    echo "⏭️  '$tag' bereits vorhanden (ohne Assets, außerhalb des APK-Fensters) — skip"
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

  # Assets syncen (nur wenn dieser Tag im APK-Fenster liegt)
  if [ "$should_sync_apk" = "true" ]; then
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
            apk_uploaded_this_run=$((apk_uploaded_this_run+1))
          else
            echo "  ❌ $fname (HTTP $upload_http_code): $(cat /tmp/upload_resp.json)"
          fi
        done
      fi
    fi
    rm -rf "$asset_dir"
  else
    echo "⏭️  Außerhalb des APK-Fensters ($APK_COUNT/$APK_DIRECTION) — überspringe Asset-Upload"
  fi
  synced_count=$((synced_count+1))
done
echo ""
echo "=========================================="
echo "Neu synchronisiert: $synced_count | Übersprungen: $skipped_count | Fehlgeschlagen: $failed_count"
echo "==========================================";

# ── APK-Retention: nur die neuesten $MAX_APK_RETAIN Releases behalten Assets ──
if [ "$apk_uploaded_this_run" -gt 0 ]; then
  echo ""
  echo "🧹 Neue APK(s) hochgeladen — prüfe Retention (max. $MAX_APK_RETAIN)..."

  page=1
  releases_with_assets=""
  while true; do
    batch=$(curl -s "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases?page=$page&limit=50" \
      -H "Authorization: token $CODEBERG_TOKEN" \
      | jq -r '.[] | select(.assets | length > 0) | "\(.published_at // .created_at)|\(.id)|\(.tag_name)"')
    [ -z "$batch" ] && break
    releases_with_assets="$releases_with_assets
$batch"
    page=$((page+1))
  done
  releases_with_assets=$(echo "$releases_with_assets" | sed '/^$/d')

  total_with_assets=$(echo "$releases_with_assets" | grep -c . || true)
  echo "📦 $total_with_assets Release(s) mit Assets gefunden."

  if [ "$total_with_assets" -gt "$MAX_APK_RETAIN" ]; then
    excess=$((total_with_assets - MAX_APK_RETAIN))
    echo "🗑️  $excess Release(s) über dem Limit — entferne APKs der ältesten..."

    # aufsteigend nach Datum sortieren, die ältesten $excess herausgreifen
    to_prune=$(echo "$releases_with_assets" | sort -t'|' -k1,1 | head -n "$excess")

    while IFS='|' read -r pub_date rel_id tag_name; do
      [ -z "$rel_id" ] && continue
      echo ""
      echo "🗑️  Entferne APK(s) von '$tag_name' (Release id=$rel_id, published=$pub_date)..."

      release_detail=$(curl -s "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases/$rel_id" \
        -H "Authorization: token $CODEBERG_TOKEN")
      asset_ids=$(echo "$release_detail" | jq -r '.assets[].id')

      for asset_id in $asset_ids; do
        del_http_code=$(curl -s -o /tmp/del_asset_resp.json -w "%{http_code}" -X DELETE \
          "$CODEBERG_API/repos/$TARGET_REPO_CODEBERG/releases/$rel_id/assets/$asset_id" \
          -H "Authorization: token $CODEBERG_TOKEN")
        if [ "$del_http_code" = "204" ]; then
          echo "  ✓ Asset $asset_id gelöscht"
        else
          echo "  ❌ Asset $asset_id nicht gelöscht (HTTP $del_http_code): $(cat /tmp/del_asset_resp.json)"
        fi
      done
    done <<< "$to_prune"
  else
    echo "✅ Innerhalb des Limits — keine Bereinigung nötig."
  fi
fi
