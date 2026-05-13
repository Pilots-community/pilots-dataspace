#!/bin/bash
# validation script for pilots-dataspace deployment

DOMAIN="pilots.t-mining.ma-de.be"
SERVICES=("dashboard" "credentials" "did-api" "did-server" "dsp" "data")

echo "=== 1. DNS Resolution ==="
if host "$DOMAIN" > /dev/null 2>&1; then
    IP=$(host "$DOMAIN" | awk '/has address/ { print $4 }' | head -n1)
    echo "✅ $DOMAIN resolves to $IP"
else
    echo "❌ $DOMAIN does not resolve. Check NS delegation!"
    # Show nameservers to use
    echo "   Ensure your parent DNS has NS records for 'pilots' pointing to AWS nameservers."
fi

echo ""
echo "=== 2. SSL Certificate ==="
# Check if we can connect via HTTPS
if curl -sI "https://$DOMAIN/dashboard" --max-time 5 > /dev/null 2>&1; then
    echo "✅ SSL/HTTPS connectivity is working."
else
    echo "❌ SSL/HTTPS connectivity failed. Certificate might still be validating or NS delegation missing."
fi

echo ""
echo "=== 3. Service Endpoints ==="
for SVC in "${SERVICES[@]}"; do
    URL="https://$DOMAIN/$SVC"
    # We expect some response (200, 401, 404) but not a connection error
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" --max-time 10)
    
    if [ "$HTTP_CODE" -eq 000 ]; then
        printf "❌ %-12s: Connection Failed\n" "$SVC"
    elif [ "$HTTP_CODE" -ge 500 ]; then
        printf "⚠️  %-12s: HTTP %s (Service might be starting up...)\n" "$SVC" "$HTTP_CODE"
    else
        printf "✅ %-12s: HTTP %s\n" "$SVC" "$HTTP_CODE"
    fi
done

echo ""
echo "=== 4. Scale-to-Zero Check ==="
echo "Note: Scale-to-zero means services take 30-60s to start on first request."
echo "Triggering cold starts..."
for SVC in "${SERVICES[@]}"; do
    curl -s "https://$DOMAIN/$SVC" > /dev/null &
done
wait
echo "Cold start requests sent. Check 'aws ecs list-tasks --cluster pilots-connector-dev' to see if tasks are starting."
