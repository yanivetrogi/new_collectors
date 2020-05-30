<#
verbose	        5
Informational	4
Warning	        3
Critical	    2
Log Always	    1
#>

if ($psISE) {$path = Split-Path -Path $psISE.CurrentFile.FullPath;} else {$path = $global:PSScriptRoot;}

#region <variables>
[string]$config_file_full_name = Join-Path $path 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[string]$source = $config_file.eventlog_application_source;
[int16]$minutes = $config_file.eventlog_minutes;
[array]$eventlog_system_ids_exclude = $config_file.eventlog_system_ids_exclude;

[datetime]$date = (Get-Date).Addminutes(-$minutes);
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

    [SecureString]$secuered_password = ConvertTo-SecureString $password -AsPlainText -Force;
    [System.Management.Automation.PSCredential]$credential = New-Object System.Management.Automation.PSCredential ($user, $secuered_password);
}

[string]$to          = $config_file.to;
[string]$from        = $config_file.from;
[string]$smtpserver = $config_file.smtpserver;

[Net.Mail.SmtpClient]$smtp_client = New-Object Net.Mail.SmtpClient($smtpserver);
if($use_default_credentials -eq $true)
{
    [object]$smtp_client.Credentials  = $credential;
}
[int32]$smtp_client.Port          = $config_file.port;
[bool]$smtp_client.EnableSsl      = $config_file.ssl;
[string]$subject;
#endregion




foreach ($server in $servers)
{     
    try
    {        
        # Application
        $log_name = 'Application';
        $events = Get-WinEvent –FilterHashtable @{logname= $log_name; level=1,2} -ComputerName $server -MaxEvents 20 | Where-Object {$_.TimeCreated -gt $date -and $_.source -match $source } 
        if ($events -ne $null)
        {
            $body = $events | format-list -property * | out-string;
            $subject = $server + ': ' + $collector_name + $log_name;   
        }


        # System
        $log_name = 'System';
        $events = Get-WinEvent –FilterHashtable @{logname= $log_name; level=1,2} -ComputerName $server -MaxEvents 20 | Where-Object {$_.TimeCreated -gt $date } 
        if ($events -ne $null)
        {
            $body += $events | format-list -property * | out-string;
            $subject = $server + ': ' + $collector_name + $log_name;                    
        }


        if ($body -ne $null)
        {
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $server 'sending mail...'};     
                $smtp_client.Send($from, $to, $subject, $body);   
        }

    }
    catch [Exception] 
    {        
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $_.Exception};      
            
        $subject = $server + ': Exception at ' + $collector_name;
        $body = $_.Exception;                      
        $smtp_client.Send($from, $to, $subject, $body);   
    }    

    $subject = $null;
    $body = $null;
}
