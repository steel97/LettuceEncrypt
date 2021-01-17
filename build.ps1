#!/usr/bin/env pwsh
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Debug', 'Release')]
    $Configuration = $null,
    [switch]
    $ci,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MSBuildArgs
)

Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

Import-Module -Force -Scope Local "$PSScriptRoot/src/common.psm1"

#
# Main
#

if ($env:CI -eq 'true') {
    $ci = $true
}

if (!$Configuration) {
    $Configuration = if ($ci) { 'Release' } else { 'Debug' }
}

if ($ci) {
    $MSBuildArgs += '-p:CI=true'

    & dotnet --info
}

$isPr = $env:APPVEYOR_PULL_REQUEST_HEAD_COMMIT -or ($env:BUILD_REASON -eq 'PullRequest')
if (-not (Test-Path variable:\IsCoreCLR)) {
    $IsWindows = $true
}

$artifacts = "$PSScriptRoot/artifacts/"

Remove-Item -Recurse $artifacts -ErrorAction Ignore

exec dotnet tool restore
exec dotnet build --configuration $Configuration '-warnaserror:CS1591' @MSBuildArgs
exec dotnet pack --no-restore --no-build --configuration $Configuration -o $artifacts @MSBuildArgs

[string[]] $testArgs=@()
if ($env:TF_BUILD) {
    $testArgs += '--logger', 'trx'
}

exec dotnet test --no-restore --no-build --configuration $Configuration '-clp:Summary' `
    --collect:"XPlat Code Coverage" `
    @testArgs `
    @MSBuildArgs

if ($ci) {
    exec dotnet tool run reportgenerator `
        "-reports:$PSScriptRoot/**/coverage.cobertura.xml" `
        "-targetdir:$PSScriptRoot/coverlet/reports" `
        "-reporttypes:Cobertura"
}

write-host -f green 'BUILD SUCCEEDED'
