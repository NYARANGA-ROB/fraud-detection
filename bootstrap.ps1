param(
    [switch]$SkipDocker,
    [switch]$SkipTests
)

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

function Ensure-PythonEnv {
    $venvPath = Join-Path $RepoRoot 'ai-reasoning-service\.venv'
    $venvPython = if (Test-Path (Join-Path $venvPath 'Scripts\python.exe')) {
        Join-Path $venvPath 'Scripts\python.exe'
    } else {
        $null
    }

    if (-not $venvPython) {
        Write-Host 'Creating AI reasoning service virtual environment...'
        py -3 -m venv $venvPath
        $venvPython = Join-Path $venvPath 'Scripts\python.exe'
    }

    & $venvPython -m pip install --quiet -r (Join-Path $RepoRoot 'ai-reasoning-service\requirements.txt')
}

function Ensure-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is required but was not found in PATH.'
    }

    docker compose -f (Join-Path $RepoRoot 'docker-compose.yml') up -d
}

function Run-JavaTests {
    $serviceDirs = @(
        'payment-service',
        'fraud-detection-service',
        'notification-service',
        'api-gateway'
    )

    foreach ($dir in $serviceDirs) {
        $path = Join-Path $RepoRoot $dir
        Write-Host "Running tests for $dir..."
        Push-Location $path
        try {
            & (Join-Path $path 'mvnw.cmd') test -q
            if ($LASTEXITCODE -ne 0) {
                throw "Tests failed for $dir"
            }
        } finally {
            Pop-Location
        }
    }
}

Ensure-Java
Ensure-PythonEnv
if (-not $SkipDocker) { Ensure-Docker }
if (-not $SkipTests) { Run-JavaTests }

Write-Host ''
Write-Host 'Bootstrap complete.'
Write-Host 'Next: use scripts/dev.ps1 start to launch the stack.'
