# Idempotent, runs at first logon and then on every boot as SYSTEM.
# Pro ignores "Turn off Microsoft consumer experiences" and telemetry level 0, so the apps are removed and the
# per user content delivery switches turned off instead.

Start-Transcript "$PSScriptRoot\debloat.log" | Out-Null

$apps = @(
  'Clipchamp.Clipchamp'
  'Microsoft.549981C3F5F10' # Cortana
  'Microsoft.BingNews'
  'Microsoft.BingSearch'
  'Microsoft.BingWeather'
  'Microsoft.Copilot'
  'Microsoft.Edge.GameAssist'
  'Microsoft.GamingApp'
  'Microsoft.GetHelp'
  'Microsoft.Getstarted'
  'Microsoft.MicrosoftOfficeHub'
  'Microsoft.MicrosoftSolitaireCollection'
  'Microsoft.Office.OneNote'
  'Microsoft.OutlookForWindows'
  'Microsoft.People'
  'Microsoft.PowerAutomateDesktop'
  'Microsoft.StartExperiencesApp'
  'Microsoft.Todos'
  'Microsoft.Windows.Ai.Copilot.Provider'
  'Microsoft.Windows.DevHome'
  'Microsoft.WindowsFeedbackHub'
  'Microsoft.WindowsMaps'
  'Microsoft.Xbox.TCUI'
  'Microsoft.XboxGamingOverlay'
  'Microsoft.XboxIdentityProvider'
  'Microsoft.XboxSpeechToTextOverlay'
  'Microsoft.YourPhone'
  'Microsoft.ZuneMusic'
  'Microsoft.ZuneVideo'
  'MicrosoftCorporationII.MicrosoftFamily'
  'MicrosoftCorporationII.QuickAssist'
  'MicrosoftTeams'
  'MicrosoftWindows.Client.WebExperience' # Widgets
  'MSTeams'
)

function Set-Dword($path, $name, $value) {
  if (-not (Test-Path $path)) { New-Item $path -Force | Out-Null }
  New-ItemProperty $path -Name $name -Value $value -PropertyType DWord -Force | Out-Null
}

# Provisioned ones would be installed again for every new account.
$provisioned = Get-AppxProvisionedPackage -Online
foreach ($app in $apps) {
  $provisioned | Where-Object DisplayName -eq $app | Remove-AppxProvisionedPackage -Online -AllUsers -ErrorAction SilentlyContinue | Out-Null
  Get-AppxPackage -AllUsers -Name $app | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
}

$policies = 'HKLM:\SOFTWARE\Policies\Microsoft'
Set-Dword "$policies\Windows\WindowsAI" DisableAIDataAnalysis 1 # Recall
Set-Dword "$policies\Windows\WindowsCopilot" TurnOffWindowsCopilot 1
Set-Dword "$policies\Dsh" AllowNewsAndInterests 0 # Widgets
Set-Dword "$policies\Windows\Windows Search" AllowCortana 0
Set-Dword "$policies\Windows\Windows Search" DisableWebSearch 1
Set-Dword "$policies\Windows\Windows Search" ConnectedSearchUseWeb 0
Set-Dword "$policies\Windows\Explorer" DisableSearchBoxSuggestions 1 # Bing in Start
Set-Dword "$policies\Windows\DataCollection" AllowTelemetry 1 # Required, the lowest Pro honours
Set-Dword "$policies\Windows\DataCollection" DoNotShowFeedbackNotifications 1
Set-Dword "$policies\Windows\AdvertisingInfo" DisabledByGroupPolicy 1
Set-Dword "$policies\Windows\OneDrive" DisableFileSyncNGSC 1

foreach ($service in 'DiagTrack', 'dmwappushservice') {
  Stop-Service $service -Force -ErrorAction SilentlyContinue
  Set-Service $service -StartupType Disabled -ErrorAction SilentlyContinue
}

# Suggested and silently installed apps are per user: the default profile for new accounts, and every existing one.
function Set-UserContent($root) {
  $cdm = "$root\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
  foreach ($name in @(
      'ContentDeliveryAllowed'
      'OemPreInstalledAppsEnabled'
      'PreInstalledAppsEnabled'
      'SilentInstalledAppsEnabled'
      'SoftLandingEnabled'
      'SubscribedContentEnabled'
      'SubscribedContent-338388Enabled'
      'SubscribedContent-338389Enabled'
      'SubscribedContent-353694Enabled'
      'SubscribedContent-353696Enabled'
      'SystemPaneSuggestionsEnabled'
    )) {
    Set-Dword $cdm $name 0
  }
  Remove-ItemProperty "$root\Software\Microsoft\Windows\CurrentVersion\Run" OneDriveSetup -ErrorAction SilentlyContinue
}

$profiles = @(@{ Sid = 'debloat-default'; Path = "$env:SystemDrive\Users\Default\NTUSER.DAT" }) +
  @(Get-CimInstance Win32_UserProfile | Where-Object { -not $_.Special } | ForEach-Object { @{ Sid = $_.SID; Path = "$($_.LocalPath)\NTUSER.DAT" } })
foreach ($user in $profiles) {
  $root = "Registry::HKEY_USERS\$($user.Sid)"
  $loaded = Test-Path $root
  if (-not $loaded) {
    reg.exe load "HKU\$($user.Sid)" $user.Path | Out-Null
    if ($LASTEXITCODE -ne 0) { continue }
  }
  Set-UserContent $root
  if (-not $loaded) {
    # Left loaded, the default hive can't be copied and new accounts get a temporary profile.
    foreach ($try in 1..5) {
      [gc]::Collect()
      [gc]::WaitForPendingFinalizers()
      reg.exe unload "HKU\$($user.Sid)" 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) { break }
      Start-Sleep -Seconds 1
    }
  }
}

Stop-Transcript | Out-Null
