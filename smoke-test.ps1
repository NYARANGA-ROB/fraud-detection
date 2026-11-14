$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path $PSScriptRoot).Path

function Ensure-Java {
    if (-not $env:JAVA_HOME) {
        $jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'jdk' } |
            Sort-Object Name -Descending |
            Select-Object -First 1

        if (-not $jdk) {
            throw 'JAVA_HOME is not set and no JDK 17+ was found under C:\Program Files\Microsoft. Install Java 17 or set JAVA_HOME.'
        }

        $env:JAVA_HOME = $jdk.FullName
    }

    $env:Path = "$env:JAVA_HOME\bin;$env:Path"
}

function Ensure-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is required but was not found in PATH.'
    }

    docker compose -f (Join-Path $RepoRoot 'docker-compose.yml') up -d
}

function Assert-CurlOk {
    param([string]$Url)

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15 -Method Get -SkipHttpErrorCheck
    if ($response.StatusCode -ge 400) {
        throw "Health check failed for $Url (status $($response.StatusCode))"
    }
}

Ensure-Java
Ensure-Docker
Write-Host 'Running project smoke tests...'

$services = @(
    'payment-service',
    'fraud-detection-service',
    'notification-service',
    'api-gateway'
)

foreach ($service in $services) {
    $dir = Join-Path $RepoRoot $service
    Write-Host "Compiling $service..."
    Push-Location $dir
    try {
        & (Join-Path $dir 'mvnw.cmd') test -q
        if ($LASTEXITCODE -ne 0) {
            throw "Smoke test failed for $service"
        }
    } finally {
        Pop-Location
    }
}

Assert-CurlOk 'http://localhost:8080/actuator/health'
Write-Host 'Smoke tests passed.'
