# Seed IdentityHub participants for Kubernetes deployment

param(
    [string]$SuperuserKey = $env:PILOTS_SUPERUSER_KEY,
    [string]$ApiKey = $env:PILOTS_API_AUTH_KEY,
    [string]$ProviderIdentityUrl = "http://localhost:7092/api/identity",
    [string]$ProviderMgmtUrl = "http://localhost:19193/management",
    [string]$ProviderDid = "did:web:pilots-dataspace.westeurope.cloudapp.azure.com"
)

if ([string]::IsNullOrWhiteSpace($SuperuserKey)) {
    throw "SuperuserKey is required. Pass -SuperuserKey or set PILOTS_SUPERUSER_KEY"
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "ApiKey is required. Pass -ApiKey or set PILOTS_API_AUTH_KEY"
}

$PROVIDER_IH_IDENTITY = $ProviderIdentityUrl  # Provider IdentityHub Identity API
$PROVIDER_DID = $ProviderDid
$PROVIDER_MGMT = $ProviderMgmtUrl

Write-Host "=== Seeding Provider IdentityHub ===" -ForegroundColor Cyan

# Create provider participant context
Write-Host "Creating provider participant context..."
try {
    $response = Invoke-RestMethod -Uri "$PROVIDER_IH_IDENTITY/v1alpha/participants" -Method Post `
        -Headers @{"Content-Type"="application/json"; "x-api-key"=$SuperuserKey} `
        -Body (@{
            participantContextId = $PROVIDER_DID
            did = $PROVIDER_DID
            active = $true
            key = @{
                keyId = "$PROVIDER_DID#key-1"
                privateKeyAlias = "$PROVIDER_DID-alias"
                keyGeneratorParams = @{
                    algorithm = "EdDSA"
                    curve = "Ed25519"
                }
            }
            apiKeys = @()
            roles = @()
        } | ConvertTo-Json -Depth 10)
    
    Write-Host "  Success!" -ForegroundColor Green
    $providerClientSecret = $response.clientSecret
    Write-Host "  Client Secret: (generated)" -ForegroundColor Yellow
    
    # Store the client secret
    Write-Host "  Storing STS client secret in provider connector..."
    try {
        Invoke-RestMethod -Uri "$PROVIDER_MGMT/v3/secrets" -Method Put `
            -Headers @{"Content-Type"="application/json"; "x-api-key"=$ApiKey} `
            -Body (@{
                "@context" = @{ "@vocab" = "https://w3id.org/edc/v0.0.1/ns/" }
                "@type" = "Secret"
                "@id" = "$PROVIDER_DID-sts-client-secret"
                value = $providerClientSecret
            } | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "  Stored!" -ForegroundColor Green
    } catch {
        Write-Host "  Error storing secret: $($_.Exception.Message)" -ForegroundColor Red
    }
    
} catch {
    if ($_.Exception.Message -match "409") {
        Write-Host "  Provider participant already exists" -ForegroundColor Yellow
    } else {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        }
    }
}

Write-Host "`n=== Storing Membership Credentials ===" -ForegroundColor Cyan

# First, activate participants and publish DIDs
Write-Host "`n=== Activating Participant Contexts ===" -ForegroundColor Cyan

# Base64URL encode function
function Get-Base64UrlEncoded {
    param($Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $b64 = [Convert]::ToBase64String($bytes) -replace '\+','-' -replace '/','_' -replace '='
    return $b64
}

$providerDidB64 = Get-Base64UrlEncoded $PROVIDER_DID

Write-Host "Activating provider participant context..."
try {
    Invoke-RestMethod -Uri "$PROVIDER_IH_IDENTITY/v1alpha/participants/$providerDidB64/state?isActive=true" -Method Post `
        -Headers @{"Content-Type"="application/json"; "x-api-key"=$SuperuserKey} `
        -Body "{}" | Out-Null
    Write-Host "  Activated" -ForegroundColor Green
} catch {
    if ($_.Exception.Message -notmatch "400") {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Yellow
    } else {
        Write-Host "  Already active" -ForegroundColor Yellow
    }
}


Write-Host "`n=== Publishing DID Documents ===" -ForegroundColor Cyan

Write-Host "Publishing provider DID..."
try {
    Invoke-RestMethod -Uri "$PROVIDER_IH_IDENTITY/v1alpha/participants/$providerDidB64/dids/publish" -Method Post `
        -Headers @{"Content-Type"="application/json"; "x-api-key"=$SuperuserKey} `
        -Body (@{ did = $PROVIDER_DID } | ConvertTo-Json) | Out-Null
    Write-Host "  Published" -ForegroundColor Green
} catch {
    Write-Host "  Error or already published: $($_.Exception.Message)" -ForegroundColor Yellow
}


Write-Host "`n=== Storing Membership Credentials ===" -ForegroundColor Cyan

# Helper function to store credential
function Store-Credential {
    param($IdentityUrl, $ParticipantDID, $ParticipantDidB64, $VcJwt)
    
    # Decode JWT to extract VC details
    $jwtParts = $VcJwt.Split('.')
    $payload = $jwtParts[1]
    # Add padding if needed
    $padding = 4 - ($payload.Length % 4)
    if ($padding -ne 4) { $payload += "=" * $padding }
    $payloadJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.Replace('-','+').Replace('_','/')))
    $decoded = $payloadJson | ConvertFrom-Json
    
    # Build credential manifest
    $credential = @{
        id = $decoded.vc.id
        type = $decoded.vc.type
        issuer = @{ id = if ($decoded.vc.issuer -is [string]) { $decoded.vc.issuer } else { $decoded.vc.issuer.id } }
        issuanceDate = $decoded.vc.issuanceDate
        expirationDate = $decoded.vc.expirationDate
        credentialSubject = if ($decoded.vc.credentialSubject -is [array]) { $decoded.vc.credentialSubject } else { @($decoded.vc.credentialSubject) }
    }
    
    $manifest = @{
        id = "membership-credential"
        participantContextId = $ParticipantDID
        verifiableCredentialContainer = @{
            rawVc = $VcJwt
            format = "VC1_0_JWT"
            credential = $credential
        }
    }
    
    try {
        Invoke-RestMethod -Uri "$IdentityUrl/v1alpha/participants/$participantDidB64/credentials" -Method Post `
            -Headers @{"Content-Type"="application/json"; "x-api-key"=$SuperuserKey} `
            -Body ($manifest | ConvertTo-Json -Depth 10) | Out-Null
        return $true
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
        }
        return $false
    }
}

# Load the pre-signed membership credentials
$providerVcPath = "..\..\deployment\assets\credentials\provider\membership-credential.json"
$consumerVcPath = "..\..\deployment\assets\credentials\consumer\membership-credential.json"

Write-Host "Storing provider MembershipCredential..."
$providerVcJwt = (Get-Content $providerVcPath | ConvertFrom-Json).credential
if (Store-Credential $PROVIDER_IH_IDENTITY $PROVIDER_DID $providerDidB64 $providerVcJwt) {
    Write-Host "  OK" -ForegroundColor Green
} else {
    Write-Host "  FAILED" -ForegroundColor Red
}

Write-Host "Storing consumer MembershipCredential..."
$consumerVcJwt = (Get-Content $consumerVcPath | ConvertFrom-Json).credential
if (Store-Credential $CONSUMER_IH_IDENTITY $CONSUMER_DID $consumerDidB64 $consumerVcJwt) {
    Write-Host "  OK" -ForegroundColor Green
} else {
    Write-Host "  FAILED" -ForegroundColor Red
}

Write-Host "`nDone!" -ForegroundColor Green
