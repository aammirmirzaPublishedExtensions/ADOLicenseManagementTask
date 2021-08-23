param (
  [string] [Parameter(Mandatory = $true)] $AccessToken,
  [string] [Parameter(Mandatory = $true)] $NumberOfMonths,
  $usersExcludedFromLicenseChange = @(),
  $Organizations = @()
)
function Get-UserUri {
  param (
    [string] [Parameter(Mandatory = $true)] $OrganizationUri,
    [string] [Parameter(Mandatory = $true)] $UserId
  )

  $UserUri = "$($OrganizationUri)/$($UserId)?api-version=5.1-preview.2"
  return $UserUri
}

$EncodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$AccessToken"))
$Global:Header = @{Authorization = "Basic $encodedPat" }

#Getting Date from $NumberOfMonths
$FromDate = Get-date (Get-Date).AddMonths(-$NumberOfMonths) -Format 'yyyy-MM-dd'

#Getting Date from 3 Months ago to check the added date of the user
$FromDateThreeMonthsAgo = Get-date (Get-Date).AddMonths(-2) -Format 'yyyy-MM-dd'

# Condition for user to whom access granted but they never logged in to AzDO
$NeverDate = Get-date (Get-Date).AddMonths(-500) -Format 'yyyy-MM-dd'

$Body = '[
  {
    "from": "",
    "op": "replace",
    "path": "/accessLevel",
    "value": {
      "accountLicenseType":"stakeholder",
      "licensingSource": "account"
    }
  }]'

try {
  $aEV = 0
  $Orges = [string[]]($Organizations -split ',').replace(' ' , '')
  Write-Host "##[section] Checking license for total $($Orges.count) Organizations"
  foreach ($Org in $Orges) {
    ('=' * 75)
    $Org = $Org.replace("'" , "")
    $OrgUri = "https://vsaex.dev.azure.com/$($Org)/_apis/userentitlements"
    $Uri = "$($OrgUri)?top=10000&skip=0&api-version=5.1-preview.1"
    Write-Host "##[command]Organization Name : $($Org)"
    ('=' * 75)
    try {
      $AllOrgUsers = Invoke-RestMethod -Uri $Uri -Headers $Global:Header -Method 'GET' -ContentType "application/json"
      #Access level of Basic and Basic + Test Plan
      $ReqAccesslevelUsers = $AllOrgUsers.value | Where-Object { $_.accessLevel.licenseDisplayName -match 'Basic' }
      if(!$ReqAccesslevelUsers){ throw ( $_.Exception.Message)
      }
      #Users with Basic and Basic + Test Plan access level who have not logged in for at least $NumberOfMonths and started date is atleast 3 months
      $UsersWhoDidntLoggedForMonths = $ReqAccesslevelUsers | Where-Object { ($_.lastAccessedDate -le $FromDate) -and ($_.dateCreated -le $FromDateThreeMonthsAgo) }
      # Condition for user to whom access granted but they never logged in to AzDO
      $UsersWhoNeverLogged = $ReqAccesslevelUsers | Where-Object { ($_.lastAccessedDate -lt $NeverDate) -and ($_.dateCreated -le $FromDate) }
      Write-Host "##[section] $(($UsersWhoDidntLoggedForMonths).count) user(s) need licenses update in Organization $($Org) - Not looged in from $($FromDate)"
      Write-Host "##[section] $(($UsersWhoNeverLogged).count) user(s) need licenses update in Organization $($Org) - Never logged-in yet"
      ('-' * 75)
    }
    catch {
      # Grouping of errors
      Write-Host "##[group] ERROR : Invalid invocation for $($Org), Check access, or Org name"
      Write-Host "##[error]Invocation fail for: " $Org
      Write-Host "##[error]StatusCode: 401 " $_.Exception.Response.StatusCode.value__
      Write-Host "##[error]StatusDescription: Invalid Authentication, Check token used for $($Org) "$_.Exception.Response.Content.value__
      Write-Host "##[endgroup]"

      Write-Host "##vso[task.complete result=Failed;]Invocation fail for: $Org (Authentication issue or incorrect org name)"
      $authExceptionValue += $aEV
    }
if($UsersWhoNeverLogged){
  # dedicated for Users those who have never loggedin
      foreach ($UserNl in $UsersWhoNeverLogged) {
      if ((!($usersExcludedFromLicenseChange.Contains($UserNl.User.mailAddress))) -and ($UserNl)) {
        $ResponseNl = Invoke-RestMethod -Uri (Get-UserUri -OrganizationUri $OrgUri -UserId $UserNl.Id) -Headers $Global:Header -Method 'PATCH' -Body $Body -ContentType 'application/json-patch+json'
      }
      Start-Sleep -Seconds 7
      If ($ResponseNl.isSuccess) {
        # Write-Host ("{0} Access Level is updated" -F $User.User.mailAddress)
        Write-Host "##[section] $($UserNl.User.mailAddress) Access Level is updated"
        New-Object -TypeName PSCustomObject -Property @{
          UserEmail    = "$($UserNl.User.mailAddress)"
          Organization = "$($Org)"
          Licensed     = 'Stakeholder'
        } | Export-Csv -Path ActionedUsersLog.csv -NoTypeInformation -Append
      }
      elseif (!$ResponseNl.isSuccess) {
        # Need to skip this because of the owner of the ADO Org.
        # if ($User.User.mailAddress -in $usersExcludedFromLicenseChange) {
        if (($usersExcludedFromLicenseChange.Contains($UserNl.User.mailAddress)) -and $UserNl) {
          Write-Host "##[warning]Skipping license check for $($UserNl.User.mailAddress)"
          New-Object -TypeName PSCustomObject -Property @{
            UserEmail    = "$($UserNl.User.mailAddress)"
            Organization = "$($Org)"
            Licensed     = 'Skipped'
          } | Export-Csv -Path ActionedUsersLog.csv -NoTypeInformation -Append
          continue
        }
        # if($User){
        $errorValue += "| $($ResponseNl.operationResults.errors.value)"
        $message = "| An error occured while changing Access Level for User $($UserNl.User.mailAddress) in $($Org) organization."
        $errorValue += $message
        $countWarning += @(Write-Warning $message | Measure-Object).Count
        New-Object -TypeName PSCustomObject -Property @{
          UserEmail    = "$($UserNl.User.mailAddress)"
          Organization = "$($Org)"
          Licensed     = 'Error_changing_license'
        } | Export-Csv -Path ActionedUsersLog.csv -NoTypeInformation -Append
        # Grouping of errors
        Write-Host "##[group]Output Variables for error handeling"
        Write-Host "##[error]Error message : $errorValue"
        Write-Host "##[error]Error counts : $countWarning"
        Write-Host "##[endgroup]"
        Write-Output("##vso[task.setvariable variable=errorValue;isOutput=true;]$errorValue")
        Write-Output("##vso[task.setvariable variable=countError;isOutput=true;]$countWarning")
        Write-Host "##vbso[task.logissue type=error;]An error occured while changing Access Level for User $($User.User.mailAddress) in $($Org) organization."
        # }
      }
    }
  } else { Write-Host "##[warning] Nothing found, No license to optimize in $($Org) for 'Never logged users'" }
    # dedicated for users those who have not logged in from x months
    if ($UsersWhoDidntLoggedForMonths){
    foreach ($User in $UsersWhoDidntLoggedForMonths) {
      if (!($usersExcludedFromLicenseChange.Contains($User.User.mailAddress))) {
        $Response = Invoke-RestMethod -Uri (Get-UserUri -OrganizationUri $OrgUri -UserId $User.Id) -Headers $Global:Header -Method 'PATCH' -Body $Body -ContentType 'application/json-patch+json'
      }
      Start-Sleep -Seconds 7
      If ($Response.isSuccess) {
        # Write-Host ("{0} Access Level is updated" -F $User.User.mailAddress)
        Write-Host "##[section] $($User.User.mailAddress) Access Level is updated"
        New-Object -TypeName PSCustomObject -Property @{
          UserEmail    = "$($User.User.mailAddress)"
          Organization = "$($Org)"
          Licensed     = 'Stakeholder'
        } | Export-Csv -Path ActionedUsersLog.csv -NoTypeInformation -Append
      }
      elseif (!$Response.isSuccess) {
        # Need to skip this because of the owner of the ADO Org.
        # if ($User.User.mailAddress -in $usersExcludedFromLicenseChange) {
        if ($usersExcludedFromLicenseChange.Contains($User.User.mailAddress)) {
          Write-Host "##[warning]Skipping license check for $($User.User.mailAddress)"
          New-Object -TypeName PSCustomObject -Property @{
            UserEmail    = "$($User.User.mailAddress)"
            Organization = "$($Org)"
            Licensed     = 'Skipped'
          } | Export-Csv -Path ActionedUsersLog.csv -NoTypeInformation -Append
          continue
        }
        # if($User){
        $errorValue += "| $($Response.operationResults.errors.value)"
        $message = "| An error occured while changing Access Level for User $($User.User.mailAddress) in $($Org) organization."
        $errorValue += $message
        $countWarning += @(Write-Warning $message | Measure-Object).Count
        New-Object -TypeName PSCustomObject -Property @{
          UserEmail    = "$($User.User.mailAddress)"
          Organization = "$($Org)"
          Licensed     = 'Error_changing_license'
        } | Export-Csv -Path ActionedUsersLog.csv -NoTypeInformation -Append
        # Grouping of errors
        Write-Host "##[group]Output Variables for error handeling"
        Write-Host "##[error]Error message : $errorValue"
        Write-Host "##[error]Error counts : $countWarning"
        Write-Host "##[endgroup]"
        Write-Output("##vso[task.setvariable variable=errorValue;isOutput=true;]$errorValue")
        Write-Output("##vso[task.setvariable variable=countError;isOutput=true;]$countWarning")
        Write-Host "##vbso[task.logissue type=error;]An error occured while changing Access Level for User $($User.User.mailAddress) in $($Org) organization."
        # }
      }
    }
  } else { Write-Host "##[warning] Nothing found - No license to optimize in $($Org) for users not logged since $($FromDate)" }
    Write-Host "##[command]Creating logs..."
  }
  # Pipeline break in case of exception
  if ($countWarning -gt 0) {
    # Write-Error $errorValue.split(" | ")
    Write-Host "##vso[task.complete result=Failed;]$errorValue"
    exit 1
  }
  if ($aEV -gt 0) {
    # Write-Error $errorValue.split(" | ")
    Write-Host "##vso[task.complete result=Failed;]Invocation fail due to authentication issue or incorrect org name"
    exit 1
  }
    Get-Content -Path ActionedUsersLog.csv -ErrorAction SilentlyContinue
    Write-Host "##[command]Log file 'ActionedUsersLog.csv' has been created. Use copy file task and publish artifact task to get it packaged as build artifact"
  try {
    if (($env:Agent_OS) -eq 'Windows_NT') {
      Copy-Item ActionedUsersLog.csv -Destination "$($ENV:Build_ArtifactStagingDirectory)\Logs.csv" -Recurse -ErrorAction SilentlyContinue
    }
  }
  catch {
    Write-Host "##[warning] Nothing found - No content to optimize in $($Org)"
  }
}
catch {
  return ( $_.Exception.Message)
}