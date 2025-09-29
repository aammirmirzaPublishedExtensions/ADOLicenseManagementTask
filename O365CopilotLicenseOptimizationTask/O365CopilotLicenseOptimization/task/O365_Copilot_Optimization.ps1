[CmdletBinding()]
param (
    $inactiveDaysThreshold = 45,
    $Revoke = "False")  # Number of days of inactivity after which a user is considered inactive
################################################################
## Signature
$t = @"
    Package designed and managed
     _              _                 _
    | |__  _  _    /_\   __ _  _ __  (_) _ _
    | '_ \| || |  / _ \ / _` || '  \ | || '_|
    |_.__/ \_, | /_/ \_\\__,_||_|_|_||_||_|
           |__/
               O365 Copilot License Report - Fetch
               all users license type across
               O365 CoPilot Assignments.
               aammir.mirza@hotmail.com
"@
Write-Host "$($t)"
################################################################
# # Import required modules
# Import-Module Microsoft.Graph.Authentication
# Import-Module Microsoft.Graph.Reports
# # Connect to Microsoft Graph (interactive login; uses delegated permissions)
# Connect-MgGraph -Scopes "Reports.Read.All"
try {
    # Retrieve current Az context (requires prior Connect-AzAccount)
    $context = Get-AzContext -ErrorAction Stop
    if (-not $context) {
        throw "No active Az context found. Run Connect-AzAccount before executing this script."
    }

    # Acquire Microsoft Graph access token using existing Az session
    $graphToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
        $context.Account,
        $context.Environment,
        $context.Tenant.Id.ToString(),
        $null,
        [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never,
        $null,
        'https://graph.microsoft.com'
    ).AccessToken

    if (-not $graphToken) {
        throw "Failed to acquire Microsoft Graph access token."
    }

    # Connect to Microsoft Graph with the acquired token
    Connect-MgGraph -AccessToken ($graphToken | ConvertTo-SecureString -AsPlainText -Force) -ErrorAction Stop
    Write-Host "✅ Connected to Microsoft Graph using existing Az context."
}
catch {
    Write-Error "❌ Microsoft Graph connection failed: $($_.Exception.Message)"
    return
}

# Define parameters
$period = "D180"  # Options: D7, D30, D90, D180
$outputPath = ".\CopilotUsageReport.csv"  # Adjust path as needed
# Fetch the Copilot usage user detail report

# Build initial request
$uri = "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUsageUserDetail(period='$period')"

try {
    $response = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject

    if ($response.value) {
        # Collect first page + any additional pages
        $allRaw = @()
        $allRaw += $response.value
        $nextLink = $response.'@odata.nextLink'
        while ($nextLink) {
            $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET -OutputType PSObject
            if ($response.value) { $allRaw += $response.value }
            $nextLink = $response.'@odata.nextLink'
        }

        # Threshold (in days) after which a user is considered inactive
        # $inactiveDaysThreshold = 45  # Adjust as needed

        # Transform each record into a PSCustomObject with readable column names
        $records = $allRaw | ForEach-Object {
            $lastActivityRaw = $_.LastActivityDate
            $inactive = $true
            if (-not [string]::IsNullOrWhiteSpace($lastActivityRaw)) {
                try {
                    $lastActivityDate = [datetime]$lastActivityRaw
                    $inactive = ((Get-Date) - $lastActivityDate).TotalDays -gt $inactiveDaysThreshold
                }
                catch {
                    $inactive = $true
                }
            }

            [PSCustomObject]@{
                'Report Refresh Date'              = $_.reportRefreshDate
                'User Principal Name'              = $_.UserPrincipalName
                'Last Activity Date'               = $_.LastActivityDate
                'Display Name'                     = $_.displayName
                'Copilot Chat Last Activity'       = $_.copilotChatLastActivityDate
                'Teams Copilot Last Activity'      = $_.microsoftTeamsCopilotLastActivityDate
                'Word Copilot Last Activity'       = $_.wordCopilotLastActivityDate
                'Excel Copilot Last Activity'      = $_.excelCopilotLastActivityDate
                'PowerPoint Copilot Last Activity' = $_.powerPointCopilotLastActivityDate
                'Outlook Copilot Last Activity'    = $_.outlookCopilotLastActivityDate
                'OneNote Copilot Last Activity'    = $_.oneNoteCopilotLastActivityDate
                'Loop Copilot Last Activity'       = $_.loopCopilotLastActivityDate
                'Activity Period Detail'           = $_.copilotActivityUserDetailsByPeriod.reportPeriod
                'RevokeLicense'                    = if ($inactive) { 'Yes' } else { 'No' }
            }
        }

        write-Host "✅ Fetched $(($records | Measure-Object).Count) records from Copilot usage report."
        if ($Revoke.Contains('true')) {
            $usersToRevoke = $records | Where-Object { $_.RevokeLicense -eq 'Yes' }
            foreach ($user in $usersToRevoke) {
                $upn = $user.'User Principal Name'
                try {
                    # Fetch user
                    $mgUser = Get-MgUser -UserId $upn -ErrorAction Stop
                    if ($mgUser) {
                        # Check if user has a Copilot license
                        $hasCopilotLicense = $false
                        foreach ($license in $mgUser.AssignedLicenses) {
                            if ($license.SkuId -eq "c42b9cae-ea4f-4ab7-9717-81576235ccac") {
                                # Copilot SKU ID
                                $hasCopilotLicense = $true
                                break
                            }
                        }

                        if ($hasCopilotLicense) {
                            # Remove Copilot license
                            # Set-MgUserLicense -UserId $upn -RemoveLicenses @("c42b9cae-ea4f-4ab7-9717-81576235ccac") -ErrorAction Stop
                            Write-Host "🔴 Revoked Copilot license for inactive user: $upn"
                        }
                        else {
                            Write-Host "⚪ User $upn does not have a Copilot license assigned. Skipping."
                        }
                    }
                    else {
                        Write-Warning "⚠️ User not found: $upn"
                    }
                }
                catch {
                    Write-Error "❌ Failed to process user ${upn}: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "ℹ️ Revoke switch not set. No licenses were revoked."
            {
                Write-Host "ℹ️ Revoke switch not set. No licenses were revoked."
                $records | Where-Object { $_.RevokeLicense -eq 'Yes' } | Format-Table -AutoSize
            }
        }
        # Export
        $records | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "✅ Copilot usage report saved to $outputPath"
    }
    else {
        Write-Warning "No data returned for period $period."
    }
}
catch {
    Write-Error "Failed to fetch report: $($_.Exception.Message)"
}
