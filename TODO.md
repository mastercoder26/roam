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

### The trigger fires on any file change

It has no `includedFiles` filter, so an iOS-only commit rebuilds and redeploys
the backend as well. Not dangerous, since it ships identical code, but it
wastes build minutes and fills the revision history with rollouts that changed
nothing.

Fix by setting the trigger's included files filter to `backend/**`.

## Google Cloud cleanup

The abandoned Workload Identity bootstrap left real resources behind. It
failed partway through on a propagation race, after creating the pool, the
provider, the service account, and one IAM binding. `roam-deployer` currently
holds deploy permission on the project and nothing uses it, which is exactly
the kind of unused standing credential worth removing.

```bash
gcloud projects remove-iam-policy-binding project-22e1ead8-00a3-4990-ba3 \
  --member="serviceAccount:roam-deployer@project-22e1ead8-00a3-4990-ba3.iam.gserviceaccount.com" \
  --role="roles/run.developer" --condition=None --quiet

gcloud iam service-accounts delete \
  roam-deployer@project-22e1ead8-00a3-4990-ba3.iam.gserviceaccount.com --quiet

gcloud iam workload-identity-pools providers delete github \
  --location=global --workload-identity-pool=github-actions --quiet

gcloud iam workload-identity-pools delete github-actions --location=global --quiet
```

Leave the APIs the script enabled (Cloud Build, Artifact Registry, IAM
Credentials) switched on. They are harmless, and Cloud Build's continuous
deployment needs them.

## iOS

### Replace the deprecated geocoding calls

`ios/Roam/Models/RoutePlanningLocationCoordinator.swift` uses `CLGeocoder` and
`reverseGeocodeLocation`, both deprecated in favour of MapKit's
`MKReverseGeocodingRequest`. They still compile and work, so this is not
urgent, but the warnings surface on every command-line check run.
