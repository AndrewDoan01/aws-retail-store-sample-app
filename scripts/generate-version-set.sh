#!/usr/bin/env bash

set -euo pipefail

# Generate version-set.json from Helm charts + ECR digests
# This script converts app repo release metadata into infra repo deployment contract
# Digests are passed via arguments (extracted separately in CI/CD workflow)

VERSION_FILE="${1:-}"
RELEASE_ID="${2:-}"
APP_COMMIT_SHA="${3:-}"
TARGET_ENVIRONMENT="${4:-}"
IMAGE_REPOSITORY_PREFIX="${5:-}"  # e.g., "ACCOUNT.dkr.ecr.ap-southeast-1.amazonaws.com/retail-store-sample"
PRIMARY_REGION="${6:-ap-southeast-1}"
ECR_REGISTRIES_JSON="${7:-}"      # JSON mapping regions to registries, e.g., {"ap-southeast-1":"ACCOUNT.dkr.ecr.ap-southeast-1.amazonaws.com"}

if [ -z "${VERSION_FILE}" ] || [ -z "${RELEASE_ID}" ] || [ -z "${APP_COMMIT_SHA}" ] || [ -z "${TARGET_ENVIRONMENT}" ] || [ -z "${IMAGE_REPOSITORY_PREFIX}" ] || [ -z "${ECR_REGISTRIES_JSON}" ]; then
  echo "Usage: generate-version-set.sh <output_version_file> <release_id> <app_commit_sha> <target_environment> <image_repository_prefix> <primary_region> <ecr_registries_json>"
  echo "Example: generate-version-set.sh infra/deploy/versions/test.json v1.0.0 abc1234 test '123456789.dkr.ecr.ap-southeast-1.amazonaws.com/retail-store-sample' ap-southeast-1 '{\"ap-southeast-1\":\"123456789.dkr.ecr.ap-southeast-1.amazonaws.com\"}'"
  exit 1
fi

# Validate environment
if [[ ! "${TARGET_ENVIRONMENT}" =~ ^(test|staging|prod)$ ]]; then
  echo "Invalid target environment: ${TARGET_ENVIRONMENT} (must be test, staging, or prod)"
  exit 1
fi

# Services to deploy
services=(catalog cart orders checkout ui)
declare -A NAMESPACE_MAP
NAMESPACE_MAP[catalog]=retail
NAMESPACE_MAP[cart]=retail
NAMESPACE_MAP[orders]=retail
NAMESPACE_MAP[checkout]=retail
NAMESPACE_MAP[ui]=retail

# Start building version-set JSON
output_dir="$(dirname "${VERSION_FILE}")"
mkdir -p "${output_dir}"

# Build services array
services_json="[]"

for service in "${services[@]}"; do
  # Get Helm chart version from Chart.yaml
  chart_yaml="src/${service}/chart/Chart.yaml"
  if [[ ! -f "${chart_yaml}" ]]; then
    echo "Chart.yaml not found for service '${service}': ${chart_yaml}"
    exit 1
  fi

  chart_version="$(grep '^version:' "${chart_yaml}" | awk '{print $2}' | tr -d ' ')"
  if [ -z "${chart_version}" ]; then
    echo "Failed to extract chart version from ${chart_yaml}"
    exit 1
  fi

  # Extract image digest for this service from ECR (primary region)
  registry_for_region="$(echo "${ECR_REGISTRIES_JSON}" | jq -r --arg r "${PRIMARY_REGION}" '.[$r] // empty')"
  if [ -z "${registry_for_region}" ]; then
    echo "No registry found for region '${PRIMARY_REGION}' in ECR_REGISTRIES_JSON"
    exit 1
  fi

  repository_name="retail-store-sample-${service}"
  # Query ECR for the digest of this image
  digest="$(aws ecr describe-images \
    --region "${PRIMARY_REGION}" \
    --repository-name "${repository_name}" \
    --image-ids imageTag="${RELEASE_ID}" \
    --query 'imageDetails[0].imageDigest' \
    --output text 2>/dev/null || echo '')"

  if [ -z "${digest}" ] || [ "${digest}" = "None" ]; then
    echo "ERROR: Failed to get digest for ${repository_name}:${RELEASE_ID} in region ${PRIMARY_REGION}"
    echo "Make sure the image has been pushed to ECR before running this script"
    exit 1
  fi

  # Build image repository URI for this service
  image_repo="${registry_for_region}/retail-store-sample-${service}"

  # Build service entry matching version-set schema
  namespace="${NAMESPACE_MAP[${service}]}"
  release="${service}"
  chart="oci://public.ecr.aws/docker/retail-store-sample-${service}"

  echo "  ✓ ${service}: chart_version=${chart_version}, digest=${digest:0:20}..."

  service_entry=$(cat <<EOF
{
  "name": "${service}",
  "release": "${release}",
  "namespace": "${namespace}",
  "chart": "${chart}",
  "chart_version": "${chart_version}",
  "image": {
    "repository": "${image_repo}",
    "digest": "${digest}"
  },
  "release_id": "${RELEASE_ID}",
  "app_commit_sha": "${APP_COMMIT_SHA}",
  "values_files": ["values.yaml"],
  "smoke": {
    "deployment": "${service}"
  }
}
EOF
)

  # Append to services array
  services_json="$(echo "${services_json}" | jq ". += [$(echo "${service_entry}" | jq -c .)]")"
done

# Build final version-set JSON
version_set=$(cat <<EOF
{
  "environment": "${TARGET_ENVIRONMENT}",
  "services": $(echo "${services_json}" | jq .)
}
EOF
)

# Write to file
mkdir -p "$(dirname "${VERSION_FILE}")"
echo "${version_set}" | jq . > "${VERSION_FILE}"

echo ""
echo "✓ Generated version-set: ${VERSION_FILE}"
echo "  Environment: ${TARGET_ENVIRONMENT}"
echo "  Services: ${#services[@]}"
echo "  Release ID: ${RELEASE_ID}"
echo "  Commit SHA: ${APP_COMMIT_SHA}"
