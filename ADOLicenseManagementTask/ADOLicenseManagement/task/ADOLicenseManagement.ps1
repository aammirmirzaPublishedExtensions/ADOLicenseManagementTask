param (
  $AccessToken,
  $NumberOfMonths,
  $usersExcludedFromLicenseChange = @(),
  $Organizations = @(),
  $emailNotify,
  $SMTP_UserName,
  $SMTP_Password,
  $sentFrom,
  $adiitionalComment
)
######################################eMail notification added##############################################
function sendEmailNotification {
  param (
    $SMTP_UserName,
    $SMTP_Password,
    $sentFrom = $SMTP_UserName,
    $to,
    $aditionalComment
  )
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $SMTP_Password = $SMTP_Password | ConvertTo-SecureString -AsPlainText -Force
  $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SMTP_UserName, $SMTP_Password

  ## Define the Send-MailMessage parameters
  $mail = @{
    SmtpServer                 = 'smtp.office365.com'
    Port                       = '587'
    UseSSL                     = $true
    Credential                 = $credential
    From                       = $sentFrom
    To                         = $to
    Subject                    = "Azure DevOps license downgraded"
    Body                       = "Your license has been downgraded to STAKEHOLDER. $($adiitionalComment)"
    DeliveryNotificationOption = 'OnFailure'#, 'OnSuccess'
  }
  # write-host $mail
  try {
    Send-MailMessage @mail -EA SilentlyContinue
    Write-Host "##[section]$($to) - has been notified"
  }
  catch {
    Write-Host "##[error]$($to) - mail cannot be delivered check your SMTP configuraton / credentials"
  }
}
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
  $randomNumber = (Get-Random -Maximum 9999999)
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
      if (!$ReqAccesslevelUsers) {
        throw ( $_.Exception.Message)
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
    if ($UsersWhoNeverLogged) {
      # dedicated for Users those who have never loggedin
      foreach ($UserNl in $UsersWhoNeverLogged) {
        if ((!($usersExcludedFromLicenseChange.Contains($UserNl.User.mailAddress))) -and ($UserNl)) {
          $ResponseNl = Invoke-RestMethod -Uri (Get-UserUri -OrganizationUri $OrgUri -UserId $UserNl.Id) -Headers $Global:Header -Method 'PATCH' -Body $Body -ContentType 'application/json-patch+json'
        }
        Start-Sleep -Seconds 7
        If ($ResponseNl.isSuccess) {
          # Write-Host ("{0} Access Level is updated" -F $User.User.mailAddress)
          Write-Host "##[section] $($UserNl.User.mailAddress) Access Level is downgraded as the user 'Never logged-in from a month'"
          New-Object -TypeName PSCustomObject -Property @{
            UserEmail    = "$($UserNl.User.mailAddress)_NeverLogged"
            Organization = "$($Org)"
            Licensed     = 'Stakeholder'
            Remark     = '_NeverLoggedIn'
          } | Export-Csv -Path ActionedUsersLog_$randomNumber.csv -NoTypeInformation -Append
          # send email notofication to user
          if ($emailNotify.Contains("true")) {
            sendEmailNotification -SMTP_UserName $SMTP_UserName -SMTP_Password $SMTP_Password -sentFrom $sentFrom -to $UserNl.User.mailAddress -adiitionalComment $adiitionalComment
          }
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
              Remark     = '_Excluded'
            } | Export-Csv -Path ActionedUsersLog_$randomNumber.csv -NoTypeInformation -Append
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
            Remark     = '_OrgAdminOrPermissionIssue'
          } | Export-Csv -Path ActionedUsersLog_$randomNumber.csv -NoTypeInformation -Append
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
    }
    else { Write-Host "##[warning] Nothing found, No license to optimize in $($Org) for 'Never logged users'" }

    # dedicated for users those who have not logged in from x months
    if ($UsersWhoDidntLoggedForMonths) {
      foreach ($User in $UsersWhoDidntLoggedForMonths) {
        if (!($usersExcludedFromLicenseChange.Contains($User.User.mailAddress))) {
          if (!(Import-Csv .\ActionedUsersLog_$randomNumber.csv | Where-Object { $_.UserEmail -match $User.User.mailAddress })) {
            $Response = Invoke-RestMethod -Uri (Get-UserUri -OrganizationUri $OrgUri -UserId $User.Id) -Headers $Global:Header -Method 'PATCH' -Body $Body -ContentType 'application/json-patch+json'
          }
        }
        Start-Sleep -Seconds 7
        If ($Response.isSuccess) {
          # Write-Host ("{0} Access Level is updated" -F $User.User.mailAddress)
          Write-Host "##[section] $($User.User.mailAddress) Access Level is downgraded, as the user in-active from ,$($NumberOfMonths) months"
          New-Object -TypeName PSCustomObject -Property @{
            UserEmail    = "$($User.User.mailAddress)"
            Organization = "$($Org)"
            Licensed     = 'Stakeholder'
            Remark     = "_inActive_$($NumberOfMonths)_months"
          } | Export-Csv -Path ActionedUsersLog_$randomNumber.csv -NoTypeInformation -Append
          # send email notofication to user
          if ($emailNotify.Contains("true")) {
            sendEmailNotification -SMTP_UserName $SMTP_UserName -SMTP_Password $SMTP_Password -sentFrom $sentFrom -to $UserNl.User.mailAddress -adiitionalComment $adiitionalComment
          }
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
              Remark     = "_Skipped"
            } | Export-Csv -Path ActionedUsersLog_$randomNumber.csv -NoTypeInformation -Append
            continue
          }
          elseif (Import-Csv .\ActionedUsersLog_$randomNumber.csv | Where-Object { $_.UserEmail -match $User.User.mailAddress }) {
            Write-Host "##[section] $($User.User.mailAddress) Access Level already downgraded, as the user never logged-in."
            continue
          }
          else {
            $errorValue += "| $($Response.operationResults.errors.value)"
            $message = "| An error occured while changing Access Level for User $($User.User.mailAddress) in $($Org) organization."
            $errorValue += $message
            $countWarning += @(Write-Warning $message | Measure-Object).Count
            New-Object -TypeName PSCustomObject -Property @{
              UserEmail    = "$($User.User.mailAddress)"
              Organization = "$($Org)"
              Licensed     = 'Error_changing_license'
              Remark     = '_OrgAdminOrPermissionIssue'
            } | Export-Csv -Path ActionedUsersLog_$randomNumber.csv -NoTypeInformation -Append
            # Grouping of errors
            Write-Host "##[group]Output Variables for error handeling"
            Write-Host "##[error]Error message : $errorValue"
            Write-Host "##[error]Error counts : $countWarning"
            Write-Host "##[endgroup]"
            Write-Output("##vso[task.setvariable variable=errorValue;isOutput=true;]$errorValue")
            Write-Output("##vso[task.setvariable variable=countError;isOutput=true;]$countWarning")
            Write-Host "##vbso[task.logissue type=error;]An error occured while changing Access Level for User $($User.User.mailAddress) in $($Org) organization."
          }
        }
      }
    }
    else { Write-Host "##[warning] Nothing found - No license to optimize in $($Org) for users not logged since $($FromDate)" }
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
  Get-Content -Path ActionedUsersLog_$randomNumber.csv -ErrorAction SilentlyContinue
  Write-Host "##[command]Log file 'ActionedUsersLog_$randomNumber.csv' has been created. Use copy file task and publish artifact task to get it packaged as build artifact"
  try {
    if (($env:Agent_OS) -eq 'Windows_NT') {
      Copy-Item ActionedUsersLog_$randomNumber.csv -Destination "$($ENV:Build_ArtifactStagingDirectory)\Logs.csv" -Recurse -ErrorAction SilentlyContinue
    }
  }
  catch {
    Write-Host "##[warning] Nothing found - No content to optimize in $($Org)"
  }
}
catch {
  return ( $_.Exception.Message)
}
