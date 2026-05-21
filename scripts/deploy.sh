#!/usr/bin/env bash
set -euo pipefail

STACK_NAME="philcrissman-analytics"
REGION="us-west-2"
ALLOWED_SITES="philcrissman.net,philcrissman.github.io"

if [ -z "${ANALYTICS_API_KEY:-}" ]; then
  echo "Error: ANALYTICS_API_KEY environment variable is not set"
  exit 1
fi

cd "$(dirname "$0")/../infra"

echo "==> Deploying infrastructure with SAM..."
sam deploy \
  --template-file template.yaml \
  --stack-name "$STACK_NAME" \
  --capabilities CAPABILITY_IAM \
  --region "$REGION" \
  --resolve-s3 \
  --parameter-overrides \
    ApiKeyParam="$ANALYTICS_API_KEY" \
    AllowedSitesParam="$ALLOWED_SITES"

echo "==> Deploying dashboard to S3..."
aws s3 sync ../dashboard/build/ s3://philcrissman-analytics-dashboard/ \
  --delete \
  --region "$REGION"

echo "==> Deploy complete!"
echo ""
echo "API endpoint:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text \
  --region "$REGION"

echo ""
echo "Dashboard URL:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs[?OutputKey==`DashboardUrl`].OutputValue' \
  --output text \
  --region "$REGION"
