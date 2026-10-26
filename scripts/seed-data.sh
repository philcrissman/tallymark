#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="http://localhost:8000"
TABLE="PageViews"
REGION="us-west-2"
SITE_ID="example.com"

# Sample blog post paths
PAGES=(
  "/"
  "/blog/hello-world/"
  "/blog/fun-with-combinators/"
  "/blog/fun-with-combinators/"
  "/blog/a-tiny-analytics-tool/"
  "/about/"
  "/blog/fun-with-combinators/"
)

# Sample referrers
REFERRERS=(
  "https://news.ycombinator.com/"
  "https://twitter.com/"
  "https://google.com/"
  ""
  "https://reddit.com/r/haskell"
  ""
  "https://google.com/"
)

USER_AGENTS=(
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0"
  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15"
)

echo "==> Seeding DynamoDB Local with sample page views for site: ${SITE_ID}..."

# Write site registry entry
aws dynamodb put-item \
  --table-name "$TABLE" \
  --item "{\"pk\":{\"S\":\"SITES\"},\"sk\":{\"S\":\"SITE#${SITE_ID}\"},\"siteId\":{\"S\":\"${SITE_ID}\"}}" \
  --endpoint-url "$ENDPOINT" \
  --region "$REGION" \
  --no-cli-pager

# Generate views spread across the last 14 days
for day_offset in $(seq 0 13); do
  # 3-8 views per day
  num_views=$((RANDOM % 6 + 3))
  date=$(date -v-"${day_offset}d" +%Y-%m-%d 2>/dev/null || date -d "-${day_offset} days" +%Y-%m-%d)
  month=$(echo "$date" | cut -c1-7)

  for i in $(seq 1 "$num_views"); do
    hour=$((RANDOM % 24))
    minute=$((RANDOM % 60))
    second=$((RANDOM % 60))
    ts=$(printf "%sT%02d:%02d:%02dZ" "$date" "$hour" "$minute" "$second")
    uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$RANDOM-$i")

    page_idx=$((RANDOM % ${#PAGES[@]}))
    page="${PAGES[$page_idx]}"

    ref_idx=$((RANDOM % ${#REFERRERS[@]}))
    referrer="${REFERRERS[$ref_idx]}"

    ua_idx=$((RANDOM % ${#USER_AGENTS[@]}))
    ua="${USER_AGENTS[$ua_idx]}"

    # Build the item JSON with site-scoped keys
    item="{\"pk\":{\"S\":\"SITE#${SITE_ID}#PAGE#${page}\"},\"sk\":{\"S\":\"TS#${ts}#${uuid}\"},\"url\":{\"S\":\"${page}\"},\"siteId\":{\"S\":\"${SITE_ID}\"},\"timestamp\":{\"S\":\"${ts}\"},\"date\":{\"S\":\"${date}\"},\"gsi1pk\":{\"S\":\"SITE#${SITE_ID}#MONTH#${month}\"},\"gsi1sk\":{\"S\":\"DATE#${ts}#${uuid}\"}"

    if [ -n "$referrer" ]; then
      item="${item},\"referrer\":{\"S\":\"${referrer}\"}"
    fi
    item="${item},\"ua\":{\"S\":\"${ua}\"}}"

    aws dynamodb put-item \
      --table-name "$TABLE" \
      --item "$item" \
      --endpoint-url "$ENDPOINT" \
      --region "$REGION" \
      --no-cli-pager

    echo "    $date $ts $page"
  done
done

# Show count
count=$(aws dynamodb scan \
  --table-name "$TABLE" \
  --select COUNT \
  --endpoint-url "$ENDPOINT" \
  --region "$REGION" \
  --no-cli-pager \
  --query 'Count' \
  --output text)

echo "==> Seeded $count total items (including site registry)."
