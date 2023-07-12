param(
    [Parameter(Mandatory=$true)]
    [string]$File,
    [Parameter(Mandatory=$true)]
    [string]$Server,
    [Parameter(Mandatory=$true)]
    [string]$ProjectKey,
    [pscredential]$Credential
)

$apiUrl = "$Server/rest/api/2/issue/"

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
        $issue.fields["labels"] = $row.Labels -Split ","
    }

    # If the row header is not in the standard fields, create a custom field by ID and assign the value.
    foreach ($key in $row.PSObject.Properties.Name) {
        if (-Not $issue.fields.keys.contains($key) -and $row.$key) {
            $issue.fields[$key] = $row.$key
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

foreach ($issue in $issues) {
    $body = $issue | ConvertTo-Json -Depth 5
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $body
    } catch {
        Write-Host "Error creating the issue: $($_.Exception.Message)" -ForegroundColor Red
    }
}