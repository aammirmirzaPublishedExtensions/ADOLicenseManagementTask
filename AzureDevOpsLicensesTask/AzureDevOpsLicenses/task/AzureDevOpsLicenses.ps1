
param (
  $AccessToken)
################################################################
## Signature
$t = @"
    Package designed and managed
     _              _                 _
    | |__  _  _    /_\   __ _  _ __  (_) _ _
    | '_ \| || |  / _ \ / _` || '  \ | || '_|
    |_.__/ \_, | /_/ \_\\__,_||_|_|_||_||_|
           |__/
               AzDO License Report - Fetch
               all users license type accross
               AzDO Platform.
               aammir.mirza@hotmail.com
"@
Write-Host "$($t)"
################################################################
try {
# Getting list of all organization within the AzDO
$uProfile = Invoke-RestMethod -Uri 'https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=6.0' -Method get -Headers $AzureDevOpsAuthenicationHeader
$uProfile.publicAlias

$allOrganization = Invoke-RestMethod -Uri "https://app.vssps.visualstudio.com/_apis/accounts?memberId=$($uprofile.publicAlias)&api-version=6.0" -Method get -Headers $AzureDevOpsAuthenicationHeader
$EncodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$AccessToken"))
$Global:Header = @{Authorization = "Basic $encodedPat" }

}
catch {
  { write-error "Not valid PAT token. Or Token expired. Regenrate PAT accross 'All Organization', in case of multiple orgs."
    exit
}
}
$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($AccessToken)")) }

Write-Host '---------------------------------------------'
Write-Host '##[command]Summary'
Write-Host "##[command]Number_of_Organizations : $($allOrganization.count)"
Write-Host '---------------------------------------------'

$result = @()
# if (!$Organizations) {
#     $Organizations =
# }
foreach ($Org in $allOrganization.value.accountName) {
  ('=' * 75)
  $Org = $Org.replace(' ' , '').replace("'" , '').replace('"' , '')
  $Uri = "https://vsaex.dev.azure.com/$($Org)/_apis/userentitlements?api-version=6.0-preview.1"
  $AllOrgUsers = Invoke-RestMethod -Uri $Uri -Headers $Global:Header -Method 'GET' -ContentType 'application/json'
  Write-Host "Organization Name : $($Org) , User Count $($AllOrgUsers.Count)" -ForegroundColor Blue
  ('=' * 75)
  # try {
  #Access level of Basic and Basic + Test Plan
  # $ReqAccesslevelUsers = $AllOrgUsers.value | Where-Object { $_.accessLevel.licenseDisplayName -match 'Basic + Test Plans' }
  $ReqAccesslevelUsers = $AllOrgUsers.value | Where-Object { $_.accessLevel.licenseDisplayName -in ('Basic', 'Stakeholder', 'Basic + Test Plans', 'Visual Studio Subscriber', 'Visual Studio Enterprise subscription', 'Visual Studio Professional subscription') }
  foreach ($item in $ReqAccesslevelUsers) {
      # $item
      if ($item.accessLevel.licenseDisplayName -match 'Visual Studio') {
        Write-Host "##[command] |--- $($item.user.principalName.padright(50)) $($item.accessLevel.licenseDisplayName)"
      }
      elseif ($item.accessLevel.licenseDisplayName -eq 'Basic + Test Plans') {
        Write-Host "##[debug] |--- $($item.user.principalName.padright(50)) $($item.accessLevel.licenseDisplayName)"
      }
      else {
        Write-Host " |--- $($item.user.principalName.padright(50)) $($item.accessLevel.licenseDisplayName)"
      }
      $obj = [PSCustomObject]@{
          Organization     = $Org
          UPN              = $item.user.principalName
          License          = $item.accessLevel.licenseDisplayName
          lastAccessedDate = $item.lastAccessedDate
      }
      $result += $obj
  }
  # }
  # catch {
  #     write-host "Error"
  # }
}
$runnedDate = (get-date -format "yyyyMMdd")
Write-Host '##[command]Creating logs...'
$result | Export-Csv -Path "AzDOLicenses_$($runnedDate).csv" -NoTypeInformation -Append
Write-Host "##[command]Log file 'AzDOLicenses_$runnedDate.csv' has been created. Use copy file task and publish artifact task to get it packaged as build artifact"
$status = Import-csv ./"AzDOLicenses_$($runnedDate).csv"
$Stakeholder = (($status.where{$_.license -eq 'Stakeholder'}).Count)
$Basic = (($status.where{$_.license -eq 'Basic'}).Count)
$BasicTest = (($status.where{$_.license -eq 'Basic + Test'}).Count)

$pie = @"
``````mermaid
pie
    title Pie Chart
    "Stakeholder" : "$($Stakeholder)"
    "Basic" : "$($Basic)"
    "Basic + Test" : "$($BasicTest)"
```````n
"@
$pie
try {
  if (($env:Agent_OS) -eq 'Windows_NT') {
    Copy-Item AzDOLicenses_$runnedDate.csv -Destination "$($ENV:Build_ArtifactStagingDirectory)\AzDOLicenses_$runnedDate.csv" -Recurse -ErrorAction SilentlyContinue
  }
}
catch {
  Write-Host "##[warning] Cannot generate log file, check if the pipeline agent is windows based."
}