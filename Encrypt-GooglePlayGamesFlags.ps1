$ErrorActionPreference = 'Stop'

function Wait-BeforeExit {
    if ([Console]::IsInputRedirected) {
        return
    }

    Write-Host ''
    Write-Host 'Press any key to close...'
    try {
        [void] [Console]::ReadKey($true)
    } catch {
    }
}

trap {
    Write-Host ''
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Wait-BeforeExit
    exit 1
}

function Resolve-PlayGamesServiceDir {
    $candidateDirs = @(
        $PSScriptRoot,
        (Join-Path $PSScriptRoot 'current\service'),
        (Join-Path $env:ProgramFiles 'Google\Play Games\current\service'),
        (Join-Path ${env:ProgramFiles(x86)} 'Google\Play Games\current\service')
    ) | Where-Object { $_ -and $_.Trim() }

    foreach ($dir in $candidateDirs) {
        if (
            (Test-Path -LiteralPath (Join-Path $dir 'Service.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $dir 'Encryption.dll') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $dir 'ServiceUtil.dll') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $dir 'Metrics.dll') -PathType Leaf)
        ) {
            return (Resolve-Path -LiteralPath $dir).Path
        }
    }

    throw 'Could not find the Google Play Games service folder.'
}

function Quote-WindowsArgument {
    param([string] $Value)

    return '"' + $Value.Replace('"', '\"') + '"'
}

function Test-CanWriteDirectory {
    param([string] $Directory)

    $testPath = Join-Path $Directory ('.write-test-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($testPath, '')
        return $true
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
    }
}

function Restart-Elevated {
    $powershellExe = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($powershellExe)) {
        $powershellExe = Join-Path $PSHOME 'powershell.exe'
    }

    Write-Host 'Administrator permission is required to write the encrypted flags file.'
    Write-Host 'Restarting as administrator...'

    Start-Process `
        -FilePath $powershellExe `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-WindowsArgument $PSCommandPath)) `
        -WorkingDirectory $PSScriptRoot `
        -Verb RunAs

    exit 0
}

function New-PlayGamesShortcut {
    param(
        [string] $Path,
        [string] $ServiceExe,
        [string] $ServiceDir,
        [string] $EncryptedPath,
        [string] $IconPath
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $ServiceExe
    $shortcut.Arguments = '/flags {0}' -f (Quote-WindowsArgument $EncryptedPath)
    $shortcut.WorkingDirectory = $ServiceDir
    $shortcut.IconLocation = $IconPath
    $shortcut.Description = 'Google Play Games with local flag overrides'
    $shortcut.Save()
}

$jsonPath = Join-Path $PSScriptRoot 'flags.json'
if (-not (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
    throw "Missing flags file: $jsonPath"
}

$serviceDir = Resolve-PlayGamesServiceDir
$playGamesDir = Split-Path -Parent (Split-Path -Parent $serviceDir)
$serviceExe = Join-Path $serviceDir 'Service.exe'
$encryptedPath = Join-Path $playGamesDir 'flags.encrypted'
$shortcutPath = Join-Path $PSScriptRoot 'Google Play Games - Flags.lnk'

if (-not (Test-CanWriteDirectory -Directory $playGamesDir)) {
    Restart-Elevated
}

$bootstrapperExe = Join-Path $playGamesDir 'Bootstrapper.exe'
if (Test-Path -LiteralPath $bootstrapperExe -PathType Leaf) {
    $iconPath = "$bootstrapperExe,0"
} else {
    $iconPath = "$serviceExe,0"
}

$keyDir = Join-Path $env:LOCALAPPDATA 'Google\Play Games Tools'
New-Item -ItemType Directory -Force -Path $keyDir | Out-Null

$script:PlayGamesServiceDir = $serviceDir
[AppDomain]::CurrentDomain.add_AssemblyResolve({
    param($sender, $eventArgs)

    $assemblyName = ($eventArgs.Name -split ',')[0] + '.dll'
    $assemblyPath = Join-Path $script:PlayGamesServiceDir $assemblyName
    if (Test-Path -LiteralPath $assemblyPath -PathType Leaf) {
        return [Reflection.Assembly]::LoadFrom($assemblyPath)
    }

    return $null
}) | Out-Null

[Reflection.Assembly]::LoadFrom((Join-Path $serviceDir 'Encryption.dll')) | Out-Null
$serviceUtilAssembly = [Reflection.Assembly]::LoadFrom((Join-Path $serviceDir 'ServiceUtil.dll'))
$metricsAssembly = [Reflection.Assembly]::LoadFrom((Join-Path $serviceDir 'Metrics.dll'))

$logger = [Activator]::CreateInstance(
    $metricsAssembly.GetType('Google.Play.Games.Metrics.NoOpRecorder')
)

$descriptor = [Enum]::Parse(
    [Google.Play.Games.Encryption.EncryptionManager+ReadErrorDescriptor],
    'PhenotypeLoggingEncryptionKey'
)

$wrapperType = $serviceUtilAssembly.GetType('Google.Play.Games.Service.Util.EncryptionManagerWrapper')
$wrapper = New-Object -TypeName $wrapperType.FullName -ArgumentList (
    [string] $keyDir,
    [string] 'phenotype_encryption_key',
    $descriptor,
    $logger
)

$wrapper.Initialize()

$json = [IO.File]::ReadAllText($jsonPath)
$encryptedBytes = $wrapper.Encrypt([Text.Encoding]::UTF8.GetBytes($json))
[IO.File]::WriteAllBytes($encryptedPath, $encryptedBytes)

$decryptedJson = [Text.Encoding]::UTF8.GetString($wrapper.Decrypt([IO.File]::ReadAllBytes($encryptedPath)))
if ($decryptedJson -ne $json) {
    throw 'The encrypted flags file was created, but encryption verification failed.'
}

New-PlayGamesShortcut -Path $shortcutPath -ServiceExe $serviceExe -ServiceDir $serviceDir -EncryptedPath $encryptedPath -IconPath $iconPath

Write-Host "Flags JSON:     $jsonPath"
Write-Host "Encrypted file: $encryptedPath"
Write-Host "Shortcut:       $shortcutPath"
Write-Host 'Verified:       encrypted file decrypts correctly'

Wait-BeforeExit
