# Deployment

The `backend/` codebase is deployed twice, each deployment doing one job. This
works with no code changes because `server.ts` degrades by design: without
`DATABASE_URL` the account endpoints return `503`, while authenticated route
analysis remains available when `CLERK_SECRET_KEY` is configured.

| Deployment | Host | Job | Needs |
|---|---|---|---|
| `roam-backend` | Cloud Run, `us-central1` | route difficulty only | `GOOGLE_MAPS_API_KEY`, `CLERK_SECRET_KEY` |
| `roam-data-api` | Render, `oregon` | accounts, profiles, drive history | `CLERK_SECRET_KEY`, `DATABASE_URL` |

`POST /api/route/difficulty` uses `requireVerifiedIdentity` to verify a Clerk
token without creating a database user. Cloud Run needs Clerk credentials but
does not need a database connection.

The iOS app can't talk to Postgres directly — it would have to ship database
credentials in the app binary. `roam-data-api` sits in between.

## Cloud Run

Deploy from the repository root, not from `backend/`, since the source path is
resolved relative to the working directory:

```bash
gcloud run deploy roam-backend --source backend --region us-central1
```

Continuous deployment is configured on the service in the Cloud Run console, not
in this repository, and is filtered to `backend/**` so an iOS-only commit
doesn't redeploy. It does not run the tests, so run them before pushing:

```bash
npm test --prefix backend
```

Runtime configuration lives on the service:

```bash
gcloud run services update roam-backend --region us-central1 \
  --update-env-vars ALLOWED_ORIGINS=https://example.com
```

Check what is actually live:

```bash
gcloud run services describe roam-backend --region us-central1 \
  --format='value(status.latestReadyRevisionName)'
```

Configure `CLERK_SECRET_KEY` securely on this service; without it, route requests
return `503`. Do not give the route-only service `DATABASE_URL`.

## Render

Create the service from the root `render.yaml` (Dashboard → New → Blueprint).
It provisions `roam-data-api` and the `roam-db` Postgres instance, and prompts
for the `sync: false` vars.

Migrations apply on boot — `startCommand` is `npm run migrate && npm start`.
That's safe on Render because the service runs a single instance. Don't copy it
into the Cloud Run container command: Cloud Run starts concurrent instances and
`migrations/migrate.ts` does `SELECT version` then `INSERT` inside one
transaction, so two instances starting together both see a migration as
unapplied and the loser dies on the `schema_migrations` primary key.

## Local backend

```bash
npm run dev            # backend on http://localhost:3000
PORT=3001 npm run dev  # if 3000 is taken
```

`backend/.env.local` needs `GOOGLE_MAPS_API_KEY`. For the account endpoints,
also create a local database and apply the migrations:

```bash
createdb roam
npm --prefix backend run migrate
```

Set `DATABASE_URL` and `PGSSLMODE=disable` in `backend/.env.local` first.
Without `DATABASE_URL` the backend still starts and account endpoints return
`503`. Route analysis needs `CLERK_SECRET_KEY` as well as `GOOGLE_MAPS_API_KEY`.

## Device configuration

For a physical iPhone, copy `ios/Roam/Config/Debug.local.example.xcconfig` to
`Debug.local.xcconfig` and set the API hosts. The local file is gitignored —
don't put a private network address in the shared project configuration.
