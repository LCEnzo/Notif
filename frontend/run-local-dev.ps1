param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$backendEnv = Join-Path $repoRoot "backend/.env"

$backendPort = "8000"
# Django's CSRF origin check is port-exact and DEBUG settings trust exactly
# this loopback origin, so a web run has to land on it. Keep in sync with
# DEV_WEB_PORT in backend/.env(.example).
$webPort = "5353"

$env:ANDROID_ADB_SERVER_PORT = "5067"

if (Test-Path $backendEnv) {
    foreach ($line in Get-Content $backendEnv) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim("'`"")

        if ($key -eq "BACKEND_PORT" -and $value) {
            $backendPort = $value
        }
        if ($key -eq "DEV_WEB_PORT" -and $value) {
            $webPort = $value
        }
    }
}

$apiUrl = "http://localhost:$backendPort/api/v1"

# --web-port only matters for web targets, where an unpinned random port would
# fail Django's CSRF origin check. It is harmless on other devices.
& flutter run "--dart-define=API_URL=$apiUrl" "--web-port=$webPort" @FlutterArgs
exit $LASTEXITCODE
