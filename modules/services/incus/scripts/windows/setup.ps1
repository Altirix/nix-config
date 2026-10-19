# First logon, run from the unattend ISO: virtio drivers, debloat now and on every boot, RDP, then a real password.
$ErrorActionPreference = 'Stop'

# Program Files survives feature updates and only admins can write to it, the task runs from it as SYSTEM.
$dir = "$env:ProgramFiles\debloat"

try {
  New-Item -ItemType Directory -Force $dir | Out-Null
  Start-Transcript "$dir\setup.log" -Append | Out-Null

  # NIC, balloon, serial and the rest. Root disk and media are nvme and usb, those have inbox drivers.
  $msi = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$PSScriptRoot\virtio-win-gt-x64.msi`" /qn /norestart"
  if ($msi.ExitCode -notin 0, 3010) { throw "virtio-win: msiexec exited $($msi.ExitCode)" }

  # Feature updates bring apps back on Pro, so it runs again on every boot. Its own process, as at boot.
  Copy-Item "$PSScriptRoot\debloat.ps1" $dir -Force
  $debloat = "-NoProfile -ExecutionPolicy Bypass -File `"$dir\debloat.ps1`""
  Start-Process powershell.exe -Wait -ArgumentList $debloat
  $action = New-ScheduledTaskAction -Execute powershell.exe -Argument $debloat
  Register-ScheduledTask -TaskName debloat -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) -User SYSTEM -RunLevel Highest -Force | Out-Null

  # RDP with NLA. labs only reaches the router, so it's as open as the router lets it be.
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
  Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 1
  Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752' # Remote Desktop, by id so it doesn't depend on the UI language
} finally {
  # The account was created without a password, whatever failed above the next logon has to set one.
  Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' AutoAdminLogon 0
  net.exe user $env:USERNAME /logonpasswordchg:yes
  try { Stop-Transcript | Out-Null } catch { } # nothing to stop if the transcript never started
}

Restart-Computer -Force
