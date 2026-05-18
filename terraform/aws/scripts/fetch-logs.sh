#!/bin/bash
# fetch-logs.sh - Fetch logs from all pilots ECS services

ENVIRONMENT=${1:-dev}
DURATION=${2:-30m}
OUTPUT_FILE=${3:-services.log}
PROFILE=${AWS_PROFILE:-}

LOG_GROUP="/ecs/pilots-${ENVIRONMENT}"
SERVICES=("controlplane" "dataplane" "identityhub" "dashboard" "did-server" "vault")

AWS_CMD="aws"
if [ -n "${PROFILE}" ]; then
    AWS_CMD="aws --profile ${PROFILE}"
fi

echo "=== Fetching logs for environment: ${ENVIRONMENT} ==="
echo "Duration: ${DURATION}"
echo "Output:   ${OUTPUT_FILE}"
if [ -n "${PROFILE}" ]; then echo "Profile:  ${PROFILE}"; fi
echo ""

# Clear the output file
> "${OUTPUT_FILE}"

for service in "${SERVICES[@]}"; do
    echo "Processing ${service}..."
    echo "################################################################################" >> "${OUTPUT_FILE}"
    echo "# SERVICE: ${service}" >> "${OUTPUT_FILE}"
    echo "################################################################################" >> "${OUTPUT_FILE}"
    
    # Use aws logs tail to fetch logs. It handles multiple log streams within the prefix.
    # The flag name is --log-stream-name-prefix (not --log-stream-prefix)
    $AWS_CMD logs tail "${LOG_GROUP}" --log-stream-name-prefix "${service}" --since "${DURATION}" --format short >> "${OUTPUT_FILE}" 2>&1
    
    echo "" >> "${OUTPUT_FILE}"
done

echo ""
echo "Done! Logs saved to ${OUTPUT_FILE}"
echo "You can now analyze this file or share it with the team."
