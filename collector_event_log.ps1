<# 
    Query event log
#>


#region <variables>
$config_file_full_name = "C:\Program Files\CloudMonitoring\PowerShell\config.json";
$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;


[string]$source = $config_file.eventlog_application_source;
[int16]$minutes = $config_file.eventlog_minutes;
$eventlog_system_ids_exclude = $config_file.eventlog_system_ids_exclude;

[datetime]$date = (Get-Date).Addminutes(- $minutes);
[string[]]$servers = $config_file.servers;
[string[]]$events;

[bool]$user_interactive = [Environment]::UserInteractive;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];
#endregion



#region <email>
[string]$use_default_credentials = $config_file.use_default_credentials;

if($use_default_credentials -eq $true)
{
    [string]$user     = $config_file.user;
    [string]$password = $config_file.password;

    $secuered_password = ConvertTo-SecureString $password -AsPlainText -Force;
    [System.Management.Automation.PSCredential]$credential = New-Object System.Management.Automation.PSCredential ($user, $secuered_password);
}

[string]$to                = $config_file.to;
[string]$from              = $config_file.from;
[string]$smtp_server       = $config_file.smtp_server;

[Net.Mail.SmtpClient]$smtp_client = New-Object Net.Mail.SmtpClient($smtp_server);
if($use_default_credentials -eq $true)
{
    [object]$smtp_client.Credentials  = $credential;
}
[int32]$smtp_client.Port          = $config_file.port;
[bool]$smtp_client.EnableSsl      = $config_file.ssl;
[string]$subject;
#endregion






[string]$log_name = 'Application';

foreach ($_server in $servers)
{ 
    try
    {
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $_server $log_name};
        
        $events = Get-EventLog -LogName $log_name -ComputerName $_server -After $date | where {($_.EntryType -in 'Critical', 'Error', 'Warning' -and $_.Source -match $source )  } | Format-Table TimeWritten, EventID, Message -auto;
        if ($events -ne $null)
        {
            $body = $events | format-list -property * | out-string;
            $subject = $_server + ': ' + $collector_name + $log_name;   
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $_server 'sending mail...'};     
            $smtp_client.Send($from, $to, $subject, $body);
        
        }
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $_server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        $smtp_client.Send($from, $to, $subject, $body);   
    }
}
#return

<# ************************************************************************************************** #>
$log_name = 'System';

foreach ($_server in $servers)
{ 
    try
    {
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $_server $log_name };

        $events = Get-EventLog -LogName $log_name -ComputerName $_server -After $date | where {($_.EntryType -in 'Critical', 'Error' -and $_.EventID -notin ($eventlog_system_ids_exclude) ) } | Format-Table TimeWritten, EventID, EntryType, Message -auto;
        if ($events -ne $null)
        {
            $body = $events | format-list -property * | out-string;
            $subject = $_server + ': ' + $collector_name + $log_name;   
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $_server 'sending mail...'};     
            $smtp_client.Send($from, $to, $subject, $body);
        }
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $_server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        $smtp_client.Send($from, $to, $subject, $body);   
    }
}
