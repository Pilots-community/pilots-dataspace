#!/bin/bash
# wakeup.sh - Trigger all scale-to-zero services to start

DOMAIN="pilots.t-mining.ma-de.be"
# These are the paths mapped in ssl-routing.tf
PATHS=("dashboard" "credentials" "identity" "did-api" "did-server" "mgmt" "dsp" "data")

echo "=== Triggering Service Wake-up ==="
echo "Sending requests to all services to trigger scale-up alarms..."

for path in "${PATHS[@]}"; do
    URL="https://${DOMAIN}/${path}"
    echo "  -> Pinging $URL"
    # Send request in background, don't wait for response
    curl -s -k -o /dev/null "$URL" &
done

wait
echo ""
echo "Requests sent! Application Auto Scaling should now be increasing desired counts."
echo "Note: It typically takes 1-3 minutes for tasks to start and become healthy."
echo ""
echo "=== Monitoring Status (Ctrl+C to stop) ==="
while true; do
    aws ecs describe-services \
        --cluster pilots-connector-dev \
        --services pilots-dashboard-dev pilots-identityhub-dev pilots-controlplane-dev pilots-dataplane-dev pilots-did-server-dev \
        --query "services[].{Service:serviceName, Desired:desired_count, Running:running_count}" \
        --output table
    sleep 10
done
