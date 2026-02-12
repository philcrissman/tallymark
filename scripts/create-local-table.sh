#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="http://localhost:8000"

echo "==> Creating PageViews table on DynamoDB Local..."
aws dynamodb create-table \
  --table-name PageViews \
  --attribute-definitions \
    AttributeName=pk,AttributeType=S \
    AttributeName=sk,AttributeType=S \
    AttributeName=gsi1pk,AttributeType=S \
    AttributeName=gsi1sk,AttributeType=S \
  --key-schema \
    AttributeName=pk,KeyType=HASH \
    AttributeName=sk,KeyType=RANGE \
  --global-secondary-indexes \
    'IndexName=ByDate,KeySchema=[{AttributeName=gsi1pk,KeyType=HASH},{AttributeName=gsi1sk,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
  --billing-mode PAY_PER_REQUEST \
  --endpoint-url "$ENDPOINT" \
  --region us-west-2 \
  2>/dev/null && echo "    Table created." || echo "    Table already exists."

echo "==> Done."
