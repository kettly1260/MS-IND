# Get-AuditLogs.ps1 (Revised and Corrected Version)

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

try {
    # --------------------------------------------------------------------------
    # 步骤 1: 直接获取访问令牌
    # --------------------------------------------------------------------------
    Write-Host "Requesting Access Token..."
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $tokenBody = @{
        client_id     = $ClientId
        scope         = "https://graph.microsoft.com/.default"
        client_secret = $ClientSecret
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -ContentType "application/x-www-form-urlencoded" -Body $tokenBody -ErrorAction Stop
    $accessToken = $tokenResponse.access_token

    if ([string]::IsNullOrEmpty($accessToken)) {
        Write-Error "Failed to acquire access token."
        exit 1
    }
    Write-Host "Successfully acquired access token."

    # 准备用于 Graph API 调用的通用标头
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "application/json"
    }

    # --------------------------------------------------------------------------
    # 步骤 2: 使用令牌获取审计日志
    # --------------------------------------------------------------------------
    $endDate = Get-Date
    $startDate = $endDate.AddDays(-1)
    $filterString = "activityDateTime ge $($startDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) and activityDateTime le $($endDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"))"
    
    # 对筛选器字符串进行 URL 编码以确保安全
    $encodedFilter =::UrlEncode($filterString)
    $auditLogUrl = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$encodedFilter"

    Write-Host "Fetching audit logs from $startDate to $endDate..."
    $auditLogResponse = Invoke-RestMethod -Method Get -Uri $auditLogUrl -Headers $headers -ErrorAction Stop
    $auditLogs = $auditLogResponse.value

    if ($null -eq $auditLogs -or $auditLogs.Count -eq 0) {
        Write-Host "No audit logs found for the specified period."
        exit 0
    }
    Write-Host "Retrieved $($auditLogs.Count) log entries."

    # --------------------------------------------------------------------------
    # 步骤 3: 准备 CSV 文件并上传到 OneDrive
    # --------------------------------------------------------------------------
    $fileName = "AuditLog_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
    $localPath = Join-Path $env:TEMP $fileName

    # 从复杂的日志对象中选择有用的属性以创建更清晰的 CSV
    $auditLogs | Select-Object activityDisplayName, activityDateTime, category, correlationId, result, resultReason, @{N='InitiatedByUser'; E={$_.initiatedBy.user.userPrincipalName}}, @{N='TargetResource'; E={$_.targetResources.displayName}} | Export-Csv -Path $localPath -NoTypeInformation -Encoding UTF8

    Write-Host "CSV file created at $localPath"

    $uploadUrl = "https://graph.microsoft.com/v1.0/users/$OneDriveUserId/drive/root:$($TargetFolderPath)/$($fileName):/content"
    
    # 为文件上传准备特定的标头
    $uploadHeaders = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type"  = "text/csv"
    }

    Write-Host "Uploading file to OneDrive folder: $TargetFolderPath"
    Invoke-RestMethod -Uri $uploadUrl -Method Put -InFile $localPath -Headers $uploadHeaders -ErrorAction Stop
    Write-Host "File upload completed successfully."

} catch {
    # 统一的错误处理
    Write-Error "An error occurred: $_"
    # 如果有更详细的响应信息，也一并输出
    if ($_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $streamReader = New-Object System.IO.StreamReader($errorResponse)
        $errorBody = $streamReader.ReadToEnd()
        Write-Error "Error Response Body: $errorBody"
    }
    exit 1
}
