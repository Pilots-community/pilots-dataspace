#!/usr/bin/env bash
set -euo pipefail

# Creates the 4 ECR repositories that hold the connector images, with a
# minimal lifecycle policy (keep last 10 tagged, expire untagged after 7 days)
# and image-scan-on-push. Idempotent: existing repos are left as-is.
#
# These resources are managed outside Terraform so image build/push and infra
# apply can iterate independently. The repo URIs are passed into Terraform via
# the `image_registry` variable.
#
# Prerequisites:
#   - aws-vault session active (`aws-vault exec pilots --no-session`)
#
# Usage:
#   ./scripts/ecr-bootstrap.sh
#
# Prints the registry URL to paste into environments/<env>.tfvars as:
#   image_registry = "<printed value>"

REGION="${AWS_REGION:-eu-west-3}"
REPOS=(pilots/identityhub pilots/controlplane pilots/dataplane pilots/dashboard)

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

# Lifecycle policy: keep 10 most-recent tagged images, expire untagged > 7d.
LIFECYCLE=$(cat <<'JSON'
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 tagged images",
      "selection": {
        "tagStatus": "tagged",
        "tagPatternList": ["*"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Expire untagged after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": { "type": "expire" }
    }
  ]
}
JSON
)

for repo in "${REPOS[@]}"; do
  if aws ecr describe-repositories --region "${REGION}" --repository-names "${repo}" \
       --query 'repositories[0].repositoryUri' --output text >/dev/null 2>&1; then
    echo "  exists  ${repo}"
  else
    aws ecr create-repository --region "${REGION}" --repository-name "${repo}" \
      --image-scanning-configuration scanOnPush=true \
      --image-tag-mutability MUTABLE \
      --query 'repository.repositoryUri' --output text >/dev/null
    echo "  created ${repo}"
  fi

  aws ecr put-lifecycle-policy --region "${REGION}" --repository-name "${repo}" \
    --lifecycle-policy-text "${LIFECYCLE}" \
    --query 'repositoryName' --output text >/dev/null
done

echo
echo "Registry URL (paste into environments/<env>.tfvars):"
echo
echo "  image_registry = \"${REGISTRY}/pilots\""
echo
echo "Next: ./scripts/build-and-push.sh [tag]"
