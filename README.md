# philcrissman-analytics

Self-hosted, privacy-respecting analytics for personal websites. No cookies, no user tracking, no fingerprinting — just page view counts and referrer data.

## Stack

- **Backend**: Haskell on AWS Lambda (custom runtime via [hal](https://github.com/Nike-Inc/hal))
- **Frontend**: [Elm](https://elm-lang.org/) SPA with [elm-charts](https://github.com/terezka/elm-charts)
- **Database**: DynamoDB (single-table design, pay-per-request)
- **Tracker**: ~20 lines of vanilla JS using `navigator.sendBeacon`
- **Infra**: AWS SAM (API Gateway + Lambda + DynamoDB + S3)

## Architecture

```
Browser ──POST /track──> API Gateway ──> Lambda ──> DynamoDB
                                                        │
Dashboard ──GET /stats──> API Gateway ──> Lambda ────────┘
            GET /sites
            DELETE /sites
```

The tracker fires a single POST on each page load with the URL path, referrer, and site ID. No cookies or identifiers are stored. The dashboard is a static Elm SPA served from S3, authenticated via a Bearer token.

### DynamoDB Key Design (multi-site)

| Item type | pk | sk |
|---|---|---|
| Page view | `SITE#<siteId>#PAGE#<path>` | `TS#<timestamp>#<uuid>` |
| Site registry | `SITES` | `SITE#<siteId>` |

**GSI (ByDate)**: `gsi1pk = SITE#<siteId>#MONTH#<yyyy-mm>`, `gsi1sk = DATE#<timestamp>#<uuid>`

### API Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| `POST` | `/track` | None | Record a page view |
| `GET` | `/stats?site=&start=&end=` | Bearer | Get aggregated stats |
| `GET` | `/sites` | Bearer | List all tracked sites |
| `DELETE` | `/sites?site=` | Bearer | Delete all data for a site |

## Prerequisites

- [Docker](https://www.docker.com/) (for building the Lambda binary and running DynamoDB Local)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- [AWS CLI](https://aws.amazon.com/cli/) with configured credentials
- [Elm](https://elm-lang.org/) 0.19.1 (`brew install elm`)

## Local Development

### 1. Start DynamoDB Local

```bash
make local-setup    # starts DynamoDB Local via Docker and creates the table
make local-seed     # seeds ~70 sample page views over 14 days
```

Or manually:

```bash
docker compose up -d
./scripts/create-local-table.sh
./scripts/seed-data.sh
```

### 2. Build and run the backend

```bash
make local-api
```

This builds the Haskell Lambda in Docker (first build takes a while — subsequent builds use cached layers) and starts SAM local on port 3000.

The Docker build uses `utdemir/ghc-musl:v25-ghc944` to produce a statically linked x86_64 Linux binary, even on ARM Macs. The build uses **Cabal** (not Stack).

### 3. Run the dashboard

```bash
cd dashboard
elm make src/Main.elm --output=build/elm.js
python3 -m http.server 8080
```

Open `http://localhost:8080?api=http://localhost:3000` in your browser. The local API key is `localdevkey` (set in `local-env.json`).

### Local environment configuration

`local-env.json` provides environment variables to the Lambda container:

| Variable | Value | Purpose |
|---|---|---|
| `TABLE_NAME` | `PageViews` | DynamoDB table name |
| `DYNAMODB_ENDPOINT` | `http://dynamodb-local:8000` | Local DynamoDB endpoint |
| `API_KEY` | `localdevkey` | Bearer token for protected endpoints |
| `AWS_ACCESS_KEY_ID` | `local` | Dummy credentials for DynamoDB Local |
| `AWS_SECRET_ACCESS_KEY` | `local` | Dummy credentials for DynamoDB Local |
| `AWS_DEFAULT_REGION` | `us-west-2` | AWS region |

### SAM gotchas

- SAM only passes env vars declared in the template's `Environment.Variables` to the Lambda container
- Must use `AWS::Serverless::Api` (REST API v1), **not** `HttpApi` (v2) — hal expects the v1 event format
- Use `--docker-network philcrissman-analytics_default` so the Lambda container can reach DynamoDB Local

## Building

### Backend

```bash
./scripts/build-backend.sh
```

Outputs `backend/build/function.zip` — the Lambda deployment package containing a statically linked `bootstrap` binary.

**Build notes:**
- Docker image: `utdemir/ghc-musl:v25-ghc944` (not v27)
- Must use `--platform linux/amd64` (ARM Mac -> x86_64 Lambda)
- `cabal.project` has `allow-newer: all` for dependency resolution with amazonka 2.0

### Dashboard

```bash
cd dashboard
elm make src/Main.elm --optimize --output=build/elm.js
```

The production API URL is set as a default in `index.html`. For local dev, override with the `?api=` query parameter.

## Deploying

### First deploy

```bash
sam deploy \
  --stack-name philcrissman-analytics \
  --resolve-s3 \
  --capabilities CAPABILITY_IAM \
  --region us-west-2 \
  --parameter-overrides "ApiKeyParam=YOUR_SECRET_KEY_HERE" \
  --no-confirm-changeset
```

This creates the full stack: API Gateway, Lambda, DynamoDB table, and S3 bucket for the dashboard.

### Update the dashboard

After deploying the stack, update `index.html` with the API Gateway URL from the stack outputs, then:

```bash
aws s3 sync dashboard/ s3://philcrissman-analytics-dashboard \
  --exclude "src/*" --exclude "elm.json" --exclude "elm-stuff/*" \
  --exclude ".gitignore" --exclude "*.elm" \
  --region us-west-2
```

### Changing the API key

Update the stack with a new key:

```bash
sam deploy \
  --stack-name philcrissman-analytics \
  --resolve-s3 \
  --capabilities CAPABILITY_IAM \
  --region us-west-2 \
  --parameter-overrides "ApiKeyParam=NEW_KEY_HERE" \
  --no-confirm-changeset
```

## Adding the tracker to a site

The dashboard has a "Get Tracker Code" button that generates a ready-to-paste `<script>` tag with the correct API URL and site ID.

For Hugo sites, add the snippet to a partial (e.g., `footer.html`) and wrap it to avoid tracking local dev:

```html
{{ if not hugo.IsServer }}
<script>
(function() {
  "use strict";
  var endpoint = "https://YOUR-API-URL.execute-api.us-west-2.amazonaws.com/prod/track";
  var siteId = "your-site.com";
  if (document.visibilityState === "prerender") return;
  var data = JSON.stringify({
    url: window.location.pathname,
    referrer: document.referrer || null,
    siteId: siteId
  });
  if (navigator.sendBeacon) {
    navigator.sendBeacon(endpoint, data);
  } else {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", endpoint, true);
    xhr.setRequestHeader("Content-Type", "text/plain");
    xhr.send(data);
  }
})();
</script>
{{ end }}
```

## Project Structure

```
philcrissman-analytics/
├── Makefile                    # Build and dev automation
├── docker-compose.yml          # DynamoDB Local
├── local-env.json              # Local dev env vars
├── backend/
│   ├── Dockerfile              # ghc-musl static build
│   ├── philcrissman-analytics.cabal
│   ├── cabal.project
│   └── src/
│       ├── Main.hs             # Lambda handler, routing, auth
│       └── Analytics/
│           ├── Types.hs        # TrackRequest, PageView, StatsResponse
│           ├── DynamoDB.hs     # Table operations, key design
│           ├── TrackHandler.hs # POST /track
│           └── StatsHandler.hs # GET /stats
├── dashboard/
│   ├── elm.json
│   ├── index.html
│   ├── style.css
│   └── src/
│       ├── Main.elm            # Auth, multi-site, date controls
│       ├── Api.elm             # HTTP client, decoders
│       └── Chart/
│           └── Visits.elm      # Daily views line chart
├── tracker/
│   └── tracker.js              # Template tracker script
├── infra/
│   └── template.yaml           # SAM/CloudFormation template
└── scripts/
    ├── build-backend.sh
    ├── build-dashboard.sh
    ├── deploy.sh
    ├── create-local-table.sh
    └── seed-data.sh
```
