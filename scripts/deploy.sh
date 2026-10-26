#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Settings come from the environment, or from tallymark.env in the repo root
# (copy tallymark.env.example to get started). Values in tallymark.env win.
if [ -f "$ROOT/tallymark.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/tallymark.env"
  set +a
fi

STACK_NAME="${TALLYMARK_STACK_NAME:-tallymark}"
REGION="${TALLYMARK_REGION:-us-east-1}"
ALLOWED_SITES="${TALLYMARK_ALLOWED_SITES:-}"
TABLE_NAME="${TALLYMARK_TABLE_NAME:-}"
DASHBOARD_BUCKET="${TALLYMARK_DASHBOARD_BUCKET:-}"

if [ -z "${TALLYMARK_API_KEY:-}" ]; then
  echo "Error: TALLYMARK_API_KEY is not set (export it or put it in tallymark.env)"
  exit 1
fi

if [ ! -f "$ROOT/backend/build/function.zip" ]; then
  echo "Error: backend/build/function.zip not found."
  echo "Run 'make build-backend', or download function.zip from a GitHub release into backend/build/."
  exit 1
fi

if [ ! -f "$ROOT/dashboard/build/index.html" ]; then
  echo "Error: dashboard/build/ not found. Run 'make build-dashboard' or use a release bundle."
  exit 1
fi

stack_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey==\`$1\`].OutputValue" \
    --output text \
    --region "$REGION"
}

cd "$ROOT/infra"

echo "==> Deploying stack '$STACK_NAME' to $REGION with SAM..."
sam deploy \
  --template-file template.yaml \
  --stack-name "$STACK_NAME" \
  --capabilities CAPABILITY_IAM \
  --region "$REGION" \
  --resolve-s3 \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "ApiKeyParam=\"$TALLYMARK_API_KEY\"" \
    "AllowedSitesParam=\"$ALLOWED_SITES\"" \
    "TableNameParam=\"$TABLE_NAME\"" \
    "DashboardBucketNameParam=\"$DASHBOARD_BUCKET\""

API_URL="$(stack_output ApiEndpoint)"
BUCKET="$(stack_output DashboardBucketName)"
DASHBOARD_URL="$(stack_output DashboardUrl)"

echo "==> Writing dashboard config..."
printf 'window.TALLYMARK_API_URL = "%s";\n' "$API_URL" > "$ROOT/dashboard/build/config.js"

echo "==> Uploading dashboard to s3://$BUCKET/..."
aws s3 sync "$ROOT/dashboard/build/" "s3://$BUCKET/" \
  --delete \
  --region "$REGION"

echo ""
echo "==> Deploy complete!"
echo ""
echo "  API endpoint:  $API_URL"
echo "  Dashboard:     $DASHBOARD_URL"
echo ""
echo "Open the dashboard, sign in with your API key, and click \"Get Tracker Code\"."
