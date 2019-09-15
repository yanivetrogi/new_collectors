# Monitor disk space



#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;


[bool]$user_interactive = [Environment]::UserInteractive;
[int]$threshold = $config_file.threshold_disk_free_space_percent;
[string[]]$servers = $config_file.servers;
[array]$array = @();
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];
[string]$slack_token = $config_file.slack_token;
#endregion


#region <email>
[string]$use_default_credentials = $config_file.use_default_credentials;

if($use_default_credentials -eq $true)
{
    [string]$user     = $config_file.user;
    [string]$password = $config_file.password;

    [SecureString]$secuered_password = ConvertTo-SecureString $password -AsPlainText -Force;
    [System.Management.Automation.PSCredential]$credential = New-Object System.Management.Automation.PSCredential ($user, $secuered_password);
}

[string]$to          = $config_file.to;
[string]$from        = $config_file.from;
[string]$smtp_server = $config_file.smtp_server;

[Net.Mail.SmtpClient]$smtp_client = New-Object Net.Mail.SmtpClient($smtp_server);
if($use_default_credentials -eq $true)
{
    [object]$smtp_client.Credentials  = $credential;
}
[int32]$smtp_client.Port          = $config_file.port;
[bool]$smtp_client.EnableSsl      = $config_file.ssl;
[string]$subject;
#endregion



foreach ($_server in $servers)
{   
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server};

    try
    {
        $disks = get-wmiobject Win32_LogicalDisk -computername $_server -Filter 'DriveType = 3';        
    
        foreach ($disk in $disks) 
        {
            [long]$size_mb = ($disk.size /1024 /1024);
            [int]$free_space_mb = ($disk.freespace /1024 /1024);
            [int]$percent_free = [Math]::round((($disk.freespace/$disk.size) * 100));
            [string]$drive = $disk.DeviceID;

                   
            #if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow Drive $drive 'size_mb:'$size_mb 'percent_free:'$percent_free };
        
            # if we cross the threshold send mail
            if ($percent_free -lt $threshold) 
            {           
                $message = "Drive " + $drive + " Size mb: " + $size_mb + " Free Space mb: " + $free_space_mb + " Percent Free: " + $percent_free + " crossed the predefined threshold: " + $threshold;            
                $array += [Environment]::NewLine + $message;   
            }        
            
        }

        if($array -ne $null)
        {
            $body = $array;
            $subject = $_server + ": " + $collector_name;
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow "Sending mail.." };
            $smtp_client.Send($from, $to, $subject, $body);
        }

        if ($user_interactive -eq $true) {Write-Host $array };    
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $_server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        $smtp_client.Send($from, $to, $subject, $body);   
    }

    $exception = $null;
    $subject = $null;
    $body = $null;
    $message = $null;
}
