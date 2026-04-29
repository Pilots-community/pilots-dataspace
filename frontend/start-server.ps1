# Simple HTTP server to serve the frontend
$port = 8080
$path = "$PSScriptRoot"

Write-Host "🚀 Starting EDC Management UI..." -ForegroundColor Cyan
Write-Host "📂 Serving from: $path" -ForegroundColor Gray
Write-Host "🌐 Open your browser to: http://localhost:$port" -ForegroundColor Green
Write-Host ""
Write-Host "Press Ctrl+C to stop the server" -ForegroundColor Yellow
Write-Host ""

# Use Python's built-in HTTP server
Set-Location $path

try {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        python -m http.server $port
    } elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
        python3 -m http.server $port
    } else {
        Write-Host "❌ Python not found. Please install Python to run the server." -ForegroundColor Red
        Write-Host "Alternative: Open index.html directly in your browser" -ForegroundColor Yellow
        Write-Host "Note: CORS restrictions may apply when opening files directly" -ForegroundColor Gray
        exit 1
    }
} catch {
    Write-Host "❌ Error starting server: $_" -ForegroundColor Red
    exit 1
}
