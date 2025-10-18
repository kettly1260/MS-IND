# Get-AuditLogs.ps1

param (
    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ClientSecret,

    [Parameter(Mandatory=$true)]
    [string]$OneDriveUserId,

    [Parameter(Mandatory=$true)]
    [string]$TargetFolderPath
)

# 安装必要的 Microsoft Graph PowerShell 模块
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Reports -Scope CurrentUser -Force
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Reports

# 使用服务主体凭据进行身份验证
$secureClientSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($ClientId, $secureClientSecret)
Connect-MgGraph -TenantId $TenantId -Credential $credential

Write-Host "Successfully connected to Microsoft Graph."

# 设置日期范围，获取过去24小时的日志
$endDate = Get-Date
$startDate = $endDate.AddDays(-1)
$filterString = "activityDateTime ge $($startDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) and activityDateTime le $($endDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))"

Write-Host "Fetching audit logs from $startDate to $endDate..."

# 获取审计日志
try {
    $auditLogs = Get-MgAuditLogDirectoryAudit -Filter $filterString -ErrorAction Stop
    if ($null -eq $auditLogs) {
        Write-Host "No audit logs found for the specified period."
        exit 0
    }
    Write-Host "Retrieved $($auditLogs.Count) log entries."

    # 准备 CSV 文件
    $fileName = "AuditLog_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
    $localPath = Join-Path $env:TEMP $fileName
    $auditLogs | Export-Csv -Path $localPath -NoTypeInformation -Encoding UTF8

    Write-Host "CSV file created at $localPath"

    # 将文件上传到 OneDrive
    $uploadUrl = "https://graph.microsoft.com/v1.0/users/$OneDriveUserId/drive/root:$($TargetFolderPath)/$($fileName):/content"
    $accessToken = (Get-MgContext).Token
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "text/csv"
    }

    Write-Host "Uploading file to OneDrive folder: $TargetFolderPath"
    Invoke-RestMethod -Uri $uploadUrl -Method Put -InFile $localPath -Headers $headers
    Write-Host "File upload completed successfully."

} catch {
    Write-Error "An error occurred: $_"
    exit 1
} finally {
    # 断开连接
    Disconnect-MgGraph
    Write-Host "Disconnected from Microsoft Graph."
}
