# Create ConfigMap from frontend files
kubectl create configmap frontend-files `
  --from-file=index.html=frontend/index.html `
  --from-file=app.js=frontend/app.js `
  -n pilots-dataspace `
  --dry-run=client -o yaml | kubectl apply -f -

# Apply the frontend deployment
kubectl apply -f deployment/kubernetes/10-frontend-deployment.yaml

Write-Host ""
Write-Host "✅ Frontend deployed to AKS!" -ForegroundColor Green
Write-Host "🌐 Access via your ingress external IP / hostname (see: kubectl get ingress -n pilots-dataspace)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: The frontend is now at the root path (/)" -ForegroundColor Yellow
Write-Host "Your API endpoints are still available at:" -ForegroundColor Yellow
Write-Host "  - /provider/management/*" -ForegroundColor Gray
Write-Host "  - /consumer/management/*" -ForegroundColor Gray
