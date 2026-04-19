param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FlutterArgs
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$backendEnv = Join-Path $repoRoot "backend/.env"

$backendPort = "8000"

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
    }
}

$apiUrl = "http://localhost:$backendPort/api/v1"

& flutter run "--dart-define=API_URL=$apiUrl" @FlutterArgs
exit $LASTEXITCODE
