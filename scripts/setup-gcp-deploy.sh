#!/usr/bin/env bash
#
# One-time bootstrap so GitHub Actions can deploy the Roam backend to Cloud
# Run without a service account key.
#
# It creates a Workload Identity Federation pool that trusts GitHub's OIDC
# issuer, a deploy service account, and the IAM bindings between them. The
# trust is scoped to one repository, so a workflow in any other repository
# cannot assume this identity even though the issuer is shared by all of
# GitHub.
#
# Safe to re-run: every create is guarded by an existence check.
#
#   ./scripts/setup-gcp-deploy.sh
#
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-project-22e1ead8-00a3-4990-ba3}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-roam-backend}"
GITHUB_REPO="${GITHUB_REPO:-mastercoder26/roam}"

POOL="github-actions"
PROVIDER="github"
SA_NAME="roam-deployer"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "Project:    ${PROJECT_ID}"
echo "Repository: ${GITHUB_REPO}"
echo

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
echo "Project number: ${PROJECT_NUMBER}"

echo
echo "==> Enabling the APIs the deploy path needs"
gcloud services enable \
  iamcredentials.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  --project "${PROJECT_ID}"

echo
echo "==> Workload identity pool"
if ! gcloud iam workload-identity-pools describe "${POOL}" \
  --project "${PROJECT_ID}" --location=global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "${POOL}" \
    --project "${PROJECT_ID}" \
    --location=global \
    --display-name="GitHub Actions"
else
  echo "    already exists"
fi

echo
echo "==> Workload identity provider"
if ! gcloud iam workload-identity-pools providers describe "${PROVIDER}" \
  --project "${PROJECT_ID}" --location=global --workload-identity-pool="${POOL}" >/dev/null 2>&1; then
  # The attribute condition is the security boundary. Without it, any GitHub
  # repository anywhere could mint a token this pool would accept.
  gcloud iam workload-identity-pools providers create-oidc "${PROVIDER}" \
    --project "${PROJECT_ID}" \
    --location=global \
    --workload-identity-pool="${POOL}" \
    --display-name="GitHub" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository == '${GITHUB_REPO}'"
else
  echo "    already exists"
fi

echo
echo "==> Deploy service account"
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam service-accounts create "${SA_NAME}" \
    --project "${PROJECT_ID}" \
    --display-name="Roam GitHub Actions deployer"
else
  echo "    already exists"
fi

echo
echo "==> Granting the deploy roles"
# Deliberately not Editor or Owner. These are the roles a source deploy
# actually needs: build the image, store it, and update the service.
for role in \
  roles/run.developer \
  roles/cloudbuild.builds.editor \
  roles/artifactregistry.writer \
  roles/storage.admin \
  roles/logging.viewer; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" \
    --condition=None \
    --quiet >/dev/null
  echo "    ${role}"
done

echo
echo "==> Letting Cloud Run deploy as the service's runtime account"
# `gcloud run deploy` sets the revision's runtime identity, which requires
# permission to act as that account.
RUNTIME_SA="$(gcloud run services describe "${SERVICE}" \
  --project "${PROJECT_ID}" --region "${REGION}" \
  --format='value(spec.template.spec.serviceAccountName)' 2>/dev/null || true)"
if [ -z "${RUNTIME_SA}" ]; then
  RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
fi
echo "    runtime account: ${RUNTIME_SA}"
gcloud iam service-accounts add-iam-policy-binding "${RUNTIME_SA}" \
  --project "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountUser" \
  --quiet >/dev/null

echo
echo "==> Letting the GitHub repository impersonate the deploy account"
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --project "${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository/${GITHUB_REPO}" \
  --quiet >/dev/null

PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/providers/${PROVIDER}"

cat <<EOF

Done.

Set these as GitHub Actions repository variables. None of them is
confidential, so they are variables rather than secrets, which also keeps
them readable in run logs:

  gh variable set GCP_PROJECT_ID --body "${PROJECT_ID}"
  gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "${PROVIDER_RESOURCE}"
  gh variable set GCP_DEPLOY_SERVICE_ACCOUNT --body "${SA_EMAIL}"

EOF
