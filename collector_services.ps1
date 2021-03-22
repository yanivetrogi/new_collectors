Import-Module psgelf;

#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string[]]$services = $config_file.services;
[string[]]$servers = $config_file.servers;
[string]$server;
[string]$service;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];

$graylog_server = $config_file.graylog_server;
$graylog_port = $config_file.graylog_port;

$send_mail = $false;
$send_graylog = $true;
$send_sms = $false;

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
[bool]$smtp_client.EnableSsl      = $false #$config_file.ssl;
[string]$subject;
#endregion


#region <sms>
if ($send_sms -eq $true)
{
    #"sms_url":"http://10.32.190.12:4214/publicServices\json\smssender\sms\send",
    #[string]$sms_url = 'http://10.32.190.12:4214/publicServices\json\smssender\sms\send';
    [string]$sms_recipients = $config_file.sms_recipients;

    $sms_post_params = @{
     "pMessage"=$collector_name
     "pRecipients"=$sms_recipients
    } | ConvertTo-Json;
}
#endregion


try
{
    $script_block = {
        param($service)
        Get-Service -Name "$service";
    }


    foreach ($server in $servers)
    { 
        foreach($service in $services)
        {
            try
            {
                #if ($user_interactive -eq $true) {Write-Host -ForegroundColor Green $server };                            
                $check = Invoke-Command -ScriptBlock $script_block -ArgumentList $service -ComputerName $server;
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $server $service $check.Status}; 

                if ($check.Status -ne 'running') 
                {
                    $subject = $server + ': ' + $service + ' ' +  'Status:' + ' ' +  $check.Status;                    
                    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $subject};                  
                    
                    $body = $subject;                      
                    if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};    
                    if ($send_sms -eq $true) {Invoke-WebRequest $sms_url -Method POST -Body $sms_post_params;};                         
                };

                if($send_graylog -eq $true) {Send-PSGelfUDP -GelfServer $graylog_server -Port $graylog_port -ShortMessage $collector_name -Facility $server -AdditionalField @{service_name=$check.Name; service_status=$check.Status;} } 
            }
            catch [Exception] 
            {
               $exception = $_.Exception;
               if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
               $subject = $server + ': Exception at ' + $collector_name;
               $body = $exception;                      
               if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};    
               if ($send_sms -eq $true) {Invoke-WebRequest $sms_url -Method POST -Body $sms_post_params;};  
            }
        }   
    }
}
 catch [Exception] 
{
    $exception = $_.Exception;
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
    $subject = $server + ': Exception at ' + $collector_name;
    $body = $exception;                      
    if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};    
    if ($send_sms -eq $true) {Invoke-WebRequest $sms_url -Method POST -Body $sms_post_params;};  
    Throw; 
}