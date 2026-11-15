param([ValidateSet('windows','android')][string]$Target='windows')
$ErrorActionPreference='Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Install Flutter 3.38.0 and run python scripts/bootstrap.py first.' }
if ($Target -eq 'windows' -and $env:OS -ne 'Windows_NT') { throw 'Windows builds require Windows and Visual Studio C++ desktop tools.' }
if (-not (Test-Path "apps/nearloop/.metadata")) { throw 'Run python scripts/bootstrap.py to generate native runners.' }
Set-Location apps/nearloop
function Invoke-Flutter { & flutter @args; if ($LASTEXITCODE -ne 0) { throw "Flutter failed: $args" } }
Invoke-Flutter analyze
Invoke-Flutter test
if ($Target -eq 'windows') {
  Invoke-Flutter build windows --release
  if (-not (Test-Path 'build/windows/x64/runner/Release/nearloop.exe')) { throw 'Expected executable bundle missing.' }
  Write-Output 'Distribute the entire Release directory including DLLs and data, never only the EXE. Unsigned build.'
} else {
  Invoke-Flutter build apk --debug
  if (-not (Test-Path 'build/app/outputs/flutter-apk/app-debug.apk')) { throw 'Debug APK missing.' }
  Write-Output 'Development APK only; production signing has not been configured.'
}
