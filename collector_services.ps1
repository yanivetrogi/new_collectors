
#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string[]]$services = $config_file.services;
[string[]]$servers = $config_file.servers;
[string]$_server;
[string]$_service;
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
[string]$smtp_server = $config_file.smtp_server;

[Net.Mail.SmtpClient]$smtp_client = New-Object Net.Mail.SmtpClient($smtp_server);
if($use_default_credentials -eq $true)
{
    [object]$smtp_client.Credentials  = $credential;
}
[int32]$smtp_client.Port          = $config_file.port;
[bool]$smtp_client.EnableSsl      = $false #$config_file.ssl;
[string]$subject;
$body
#endregion



try
{
    $script_block = {
        param($_Service)
        Get-Service -Name "$_Service";
    }


    foreach ($_server in $servers)
    { 
        foreach($_service in $services)
        {
            try
            {
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Green $_server };                            
                $check = Invoke-Command -ScriptBlock $script_block -ArgumentList $_service -ComputerName $_server;
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server $_service $check.Status}; 

                if ($check.Status -ne 'running') 
                {
                    $subject = $_server + ': ' + $_service + ' ' +  'Status:' + ' ' +  $check.Status;                    
                    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $subject};                  
                    
                    $body = $subject;                      
                    $smtp_client.Send($from, $to, $subject, $body);                 
                };
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