param(
    [Parameter(Mandatory=$true)]
    [string]$File,
    [Parameter(Mandatory=$true)]
    [string]$Server,
    [Parameter(Mandatory=$true)]
    [string]$ProjectKey,
    [pscredential]$Credential
)

$File = "ISO 27002 - Annex A - JIRA Import -v2023-06-09.csv"
$Server = "https://jira.ovt.com"
$ProjectKey = "ISO27002"
$apiUrl = "$Server/rest/api/2/issue/"

if (-not $Server -match "http*") {
    Write-Host "-Server parameter value must be in the format http(s)://<hostname|IP>." -ForegroundColor Yellow
}

# Check import file exists and is in the correct format.
if (-Not (Test-Path $File)) {
    Write-Host "Cannot find $File. Check that the file exists and the path is correct." -ForegroundColor Yellow
    Exit
}

if (-Not ([System.IO.Path]::GetExtension($file) -eq ".csv")) {
   Write-Host "Import data must be in .csv format." -ForegroundColor Yellow
   Exit
}

if (-Not $Credential) {
    $Credential = Get-Credential -Message "Please enter credentials with permission to create issues for the Jira project."
}

# Split the PSCredential object into username/password and strip out full UPNs or other prefixes.
$password = $Credential.GetNetworkCredential().Password
if ($Credential.GetNetworkCredential().Username.Contains("@")) {
    $username = $Credential.GetNetworkCredential().Username.Split("@")[0]
} elseif ($Credential.GetNetworkCredential().Username.Contains("\")) {
    $username = $Credential.GetNetworkCredential().Username.Split("\")[1]
} else {
    $username = $Credential.Username
}

$csvData = Import-Csv $File
# Initialize an empty array to store the issues
$issues = @()

# Iterate over each row in the CSV
foreach ($row in $csvData) {
    # Build response body from CSV row.
    $issue = @{
        fields = @{
            project = @{
                key = $ProjectKey
            }
            summary = $row.Summary
            description = $row.Description
            issuetype = @{
                name = $row.IssueType
            }
        }
    }

    if ($row.Reporter) {
        $issue.fields["reporter"] = @{"name" = $row.Reporter}
    }

    if ($row.DueDate)  {
        $issue.fields["duedate"] = $row.DueDate
    }

    if ($row.Labels) {
        $issue.fields["labels"] = @($row.Labels)
    }

    #If the row header is not in the standard fields, create a custom field by ID and assign the value.
    foreach ($key in $row.PSObject.Properties.Name) {
        if (!($issue.fields.keys -contains $key.toLower())) {
            # String custom fields (comma separated list of alphanumeric characters)
            if ($row.key -match "^[a-zA-Z0-9]+(?:,[a-zA-Z0-9]+)*$") {
                $issue.fields[$key] = $row.$key
            }
            # TODO: add other custom field types
            
        }
    }

    $issues += $issue
}

# Create a base64-encoded credential string
$base64Creds = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($username):$($password)"))

$headers = @{
    'Content-Type' = 'application/json'
    'Authorization' = "Basic $base64Creds"
}

foreach ($issue in $issues[4..5]) {
    $body = $issue | ConvertTo-Json -Depth 5
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body
    } catch {
        Write-Host "Error creating the issue: $($_.Exception.Message)" -ForegroundColor Red
        Break
    }
}