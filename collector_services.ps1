#Set-ExecutionPolicy RemoteSigned


#region <variables>
$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string[]]$services = $config_file.services;
[string[]]$servers = $config_file.servers;
[string]$_server;
[string]$_service;
[string]$_item;
#endregion

<#

    test for git

#>

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

[Net.Mail.SmtpClient]$smtp = New-Object Net.Mail.SmtpClient($smtp_server);
if($use_default_credentials -eq $true)
{
    [object]$smtp.Credentials  = $credential;
}
[int32]$smtp.Port          = $config_file.port;
[bool]$smtp.EnableSsl      = $config_file.ssl;
[string]$subject;
#endregion



foreach ($_server in $servers)
{ 
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server };   
    
    foreach ($_service in $services)
    {
        try
        {
            $_item = Get-Service -Name $_service -ComputerName $_server;
            #if ($user_interactive -eq $true) {Write-Host $_server $_item.Name $_item.Status -ForegroundColor Cyan};   
        
            # Not running
            # Start the service and send mail
            if($_item.Status -ne "Running")
            {
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $_server $_item.Name $_item.Status };       
                #Start-Service $_item.Name  
        
                $subject = $_server + ": " + $collector_name + " " + $_item.Name + " service status is not Running"; 
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $_server 'Sending mail...'}; 
                $smtp.Send($from, $to, $subject, $body);
            }
            # Any other status
            else
            {
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $_server $_item.Name $_item.Status };    
            }     
        }
        catch [Exception] 
        {
            $exception = $_.Exception;
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
            $subject = $_server + ': Exception at ' + $collector_name;
            $body = $exception;                      
            $smtp.Send($from, $to, $subject, $body);   
        }
    }
}
exit

