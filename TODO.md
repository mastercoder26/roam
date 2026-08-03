# TODO

Open items from setting up continuous deployment on 3 August 2026. Each one
records why it matters, so a future reader does not have to reconstruct the
reasoning before deciding whether it is still worth doing.

## Deploy pipeline

### Prove the trigger actually works

The Cloud Build trigger `rmgpgab-roam-backend-us-central1-mastercoder26-roam--macdq`
is enabled and correctly wired, but it has never run. No build in the project
carries a commit SHA: revision `roam-backend-00003-7sd` was created when the
continuous deployment config was saved, which re-rolled the existing image
rather than building a new one. `backend/Dockerfile` has therefore never been
built by anything, locally or in CI.

Until a real push goes through, the pipeline is unproven.

```bash
git commit --allow-empty -m "chore: verify the Cloud Build trigger" && git push
```

Then confirm the new revision came from that commit:

```bash
gcloud builds list --region us-central1 --limit 3 \
  --format="table(id,status,substitutions.COMMIT_SHA)"
gcloud run services describe roam-backend --region us-central1 \
  --format="value(status.latestReadyRevisionName)"
```

### Nothing runs the tests before deploying

The trigger builds and deploys on every push to `main` whether the backend's
103 tests pass or not, so a broken commit ships itself. This is the one real
capability lost when the GitHub Actions workflow was dropped in favour of
Cloud Build.

Two ways to close it:

- Run `npm test --prefix backend` before every push, by habit.
- Add a `cloudbuild.yaml` whose first step runs the tests, so a failure aborts
  the build before it reaches Cloud Run. This is the durable fix, since it
  does not depend on anyone remembering.

### ~~The trigger fires on any file change~~ — done, 3 August 2026

It had no `includedFiles` filter, so an iOS-only commit rebuilt and redeployed
the backend as well. Fixed by exporting the trigger, adding
`includedFiles: [backend/**]`, and importing it back with
`gcloud alpha builds triggers import` (`update-github` and `export` are not in
the stable track). Confirmed with:

```bash
gcloud builds triggers describe rmgpgab-roam-backend-us-central1-mastercoder26-roam--macdq \
  --format="value(includedFiles)"
# backend/**
```

## Google Cloud cleanup — done, 3 August 2026

The abandoned Workload Identity bootstrap was believed to have left the
`roam-deployer` service account holding deploy permission on the project.
Checked directly instead of re-running the deletes blind:

- `roam-deployer@...iam.gserviceaccount.com` — does not exist. Not in
  `gcloud iam service-accounts list`, and no project IAM binding references it.
- `roles/run.developer` binding for that account — not found; already gone.
- Workload identity pool `github-actions` — state `DELETED` (soft-deleted).
- Its `github` provider — `NOT_FOUND`.

Nothing to remove. Google's IAM propagation appears to have caught up after
the original bootstrap failure. The APIs the script enabled (Cloud Build,
Artifact Registry, IAM Credentials) are left switched on, since Cloud Build's
continuous deployment needs them and they carry no standing credential risk.

## iOS

### Replace the deprecated geocoding calls

`ios/Roam/Models/RoutePlanningLocationCoordinator.swift` uses `CLGeocoder` and
`reverseGeocodeLocation`, both deprecated in favour of MapKit's
`MKReverseGeocodingRequest`. They still compile and work, so this is not
urgent, but the warnings surface on every command-line check run.
