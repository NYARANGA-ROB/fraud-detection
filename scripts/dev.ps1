param(
    [ValidateSet('start', 'stop', 'status', 'test')]
    [string]$Command = 'start'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$LogsDir = Join-Path $RepoRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null

function Ensure-Java {
    if (-not $env:JAVA_HOME) {
        $jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'jdk' } |
            Sort-Object Name -Descending |
            Select-Object -First 1

        if (-not $jdk) {
            throw 'JAVA_HOME is not set and no JDK was found under C:\Program Files\Microsoft. Install a JDK 17+ and rerun this command.'
        }

        $env:JAVA_HOME = $jdk.FullName
    }

    $env:Path = "$env:JAVA_HOME\bin;$env:Path"
}

function Ensure-PythonEnv {
    $venvPath = Join-Path $RepoRoot 'ai-reasoning-service\.venv'
    $venvPython = if (Test-Path (Join-Path $venvPath 'Scripts\python.exe')) {
        Join-Path $venvPath 'Scripts\python.exe'
    } elseif (Test-Path (Join-Path $venvPath 'bin/python')) {
        Join-Path $venvPath 'bin/python'
    } else {
        $null
    }

    if (-not $venvPython) {
        Write-Host 'Creating Python virtual environment for the AI reasoning service...'
        py -3 -m venv $venvPath
        $venvPython = if (Test-Path (Join-Path $venvPath 'Scripts\python.exe')) {
            Join-Path $venvPath 'Scripts\python.exe'
        } else {
            Join-Path $venvPath 'bin/python'
        }
    }

    & $venvPython -m pip install --quiet -r (Join-Path $RepoRoot 'ai-reasoning-service\requirements.txt')
    return $venvPython
}

function Start-TrackedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $process = Start-Process -FilePath 'powershell' -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command',
        "Set-Location '$WorkingDirectory'; $Command"
    ) -WorkingDirectory $RepoRoot -RedirectStandardOutput $LogPath -RedirectStandardError $LogPath -PassThru

    Write-Host "Started $Name (PID $($process.Id))"
    return $process
}

function Get-ServiceProcesses {
    $candidates = @(
        'payment-service',
        'fraud-detection-service',
        'notification-service',
        'api-gateway',
        'ai-reasoning-service'
    )

    $paths = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match 'fraud-detection|payment-service|notification-service|api-gateway|ai-reasoning-service' -or
        $_.CommandLine -match 'spring-boot:run|main.py|mvnw'
    }

    foreach ($process in $paths) {
        $cmd = $process.CommandLine
        foreach ($candidate in $candidates) {
            if ($cmd -match $candidate) {
                [PSCustomObject]@{
                    Name = $candidate
                    PID = $process.ProcessId
                    Command = $cmd
                }
                break
            }
        }
    }
}

switch ($Command) {
    'start' {
        Ensure-Java
        $venvPython = Ensure-PythonEnv

        Write-Host 'Starting infrastructure...'
        docker compose -f (Join-Path $RepoRoot 'docker-compose.yml') up -d

        Write-Host 'Starting Java microservices...'
        Start-TrackedProcess -Name 'payment-service' -WorkingDirectory (Join-Path $RepoRoot 'payment-service') -Command './mvnw spring-boot:run' -LogPath (Join-Path $LogsDir 'payment-service.log')
        Start-TrackedProcess -Name 'fraud-detection-service' -WorkingDirectory (Join-Path $RepoRoot 'fraud-detection-service') -Command './mvnw spring-boot:run' -LogPath (Join-Path $LogsDir 'fraud-detection-service.log')
        Start-TrackedProcess -Name 'notification-service' -WorkingDirectory (Join-Path $RepoRoot 'notification-service') -Command './mvnw spring-boot:run' -LogPath (Join-Path $LogsDir 'notification-service.log')
        Start-TrackedProcess -Name 'api-gateway' -WorkingDirectory (Join-Path $RepoRoot 'api-gateway') -Command './mvnw spring-boot:run' -LogPath (Join-Path $LogsDir 'api-gateway.log')

        Write-Host 'Starting AI reasoning service...'
        $aiCommand = "& '$venvPython' main.py"
        Start-TrackedProcess -Name 'ai-reasoning-service' -WorkingDirectory (Join-Path $RepoRoot 'ai-reasoning-service') -Command $aiCommand -LogPath (Join-Path $LogsDir 'ai-reasoning-service.log')

        Write-Host ''
        Write-Host 'Services are starting.'
        Write-Host 'Check logs in:'
        Write-Host "  $LogsDir"
        Write-Host 'When ready, open:'
        Write-Host '  http://localhost:8080'
        Write-Host '  http://localhost:8081/swagger-ui.html'
        Write-Host '  http://localhost:8082/swagger-ui.html'
        Write-Host '  http://localhost:8083/swagger-ui.html'
        Write-Host '  http://localhost:8084/docs'
    }

    'stop' {
        $processes = Get-ServiceProcesses | Sort-Object -Unique PID
        if (-not $processes) {
            Write-Host 'No project service processes were found to stop.'
            return
        }

        foreach ($p in $processes) {
            try {
                Stop-Process -Id $p.PID -Force
                Write-Host "Stopped $($p.Name) (PID $($p.PID))"
            } catch {
                Write-Warning "Could not stop process $($p.PID): $($_.Exception.Message)"
            }
        }
    }

    'status' {
        $processes = Get-ServiceProcesses
        if (-not $processes) {
            Write-Host 'No project services are currently running.'
            return
        }

        $processes | Format-Table Name, PID, Command -AutoSize
    }

    'test' {
        Ensure-Java
        $serviceDirs = @(
            'payment-service',
            'fraud-detection-service',
            'notification-service',
            'api-gateway'
        )

        foreach ($dir in $serviceDirs) {
            $servicePath = Join-Path $RepoRoot $dir
            Write-Host "Running tests for $dir..."
            Push-Location $servicePath
            try {
                & (Join-Path $servicePath 'mvnw.cmd') test -q
                if ($LASTEXITCODE -ne 0) {
                    throw "Tests failed for $dir"
                }
            } finally {
                Pop-Location
            }
        }

        Write-Host 'All service tests passed.'
    }
}
