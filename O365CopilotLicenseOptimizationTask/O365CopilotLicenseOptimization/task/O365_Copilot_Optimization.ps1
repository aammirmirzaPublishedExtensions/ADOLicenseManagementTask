param(
    [string] $TenantId,
    [string] $ClientId,
    [string] $ClientSecret,
    [int]    $inactiveDaysThreshold = 30,
    [string] $Revoke
)

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

# Add simple validation + debug
Write-Host "TenantId supplied: $TenantId"
Write-Host "ClientId supplied: $ClientId"
Write-Host "ClientSecret present: $([bool]$ClientSecret)"
Write-Host "Checking for federated token (AZURE_FEDERATED_TOKEN / file)..."

function Get-GraphTokenSecret {
    param($TenantId,$ClientId,$ClientSecret)
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }
    Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body -ContentType application/x-www-form-urlencoded
}

function Get-GraphTokenFederated {
    param($TenantId,$ClientId)
    $oidc = $env:AZURE_FEDERATED_TOKEN
    if (-not $oidc -and (Test-Path $env:AZURE_FEDERATED_TOKEN_FILE)) {
        $oidc = Get-Content -Raw -Path $env:AZURE_FEDERATED_TOKEN_FILE
    }
    if (-not $oidc) {
        throw "Federated service connection detected but AZURE_FEDERATED_TOKEN not found. Enable 'Allow scripts to access OIDC token' or use secret-based SP."
    }
    $body = @{
        client_id              = $ClientId
        scope                  = "https://graph.microsoft.com/.default"
        grant_type             = "client_credentials"
        client_assertion_type  = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        client_assertion       = $oidc
    }
    Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body -ContentType application/x-www-form-urlencoded
}

$graphToken = $null
try {
    if ($ClientSecret) {
        Write-Host "🔐 Acquiring token via client secret."
        $resp = Get-GraphTokenSecret -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
        $graphToken = $resp.access_token
    } else {
        Write-Host "🔐 Acquiring token via workload identity federation."
        $resp = Get-GraphTokenFederated -TenantId $TenantId -ClientId $ClientId
        $graphToken = $resp.access_token
    }
} catch {
    Write-Error "Token acquisition failed: $($_.Exception.Message)"
    exit 1
}

if (-not $graphToken) {
    Write-Error "No Graph token obtained."
    exit 1
}

try {
    Connect-MgGraph -AccessToken ($graphToken | ConvertTo-SecureString -AsPlainText -Force) -ErrorAction Stop
    Write-Host "✅ Connected to Microsoft Graph."
} catch {
    Write-Error "Graph connect failed: $($_.Exception.Message)"
    exit 1
}

# Define parameters
$period = "D180"  # Options: D7, D30, D90, D180
$outputPath = ".\CopilotUsageReport.csv"  # Adjust path as needed

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
            if ($response.value) { 
                $allRaw += $response.value 
            }
            $nextLink = $response.'@odata.nextLink'
        }

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

        Write-Host "✅ Fetched $(($records | Measure-Object).Count) records from Copilot usage report."

        if ($Revoke -and $Revoke.Contains('true')) {
            $usersToRevoke = $records | Where-Object { $_.RevokeLicense -eq 'Yes' }
            Write-Host "🔍 Found $($usersToRevoke.Count) users flagged for license revocation."
            
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
                            # Remove Copilot license (uncomment to enable actual revocation)
                            # Set-MgUserLicense -UserId $upn -RemoveLicenses @("c42b9cae-ea4f-4ab7-9717-81576235ccac") -ErrorAction Stop
                            Write-Host "🔴 Would revoke Copilot license for inactive user: $upn"
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
            $candidatesCount = ($records | Where-Object { $_.RevokeLicense -eq 'Yes' } | Measure-Object).Count
            Write-Host "📊 $candidatesCount users would be flagged for revocation."
            $records | Where-Object { $_.RevokeLicense -eq 'Yes' } | Select-Object 'User Principal Name','Last Activity Date','RevokeLicense' | Format-Table -AutoSize
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
    exit 1
}
