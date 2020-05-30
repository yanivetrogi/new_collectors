#Set-ExecutionPolicy RemoteSigned

Stop-Service -Name 'SQLSERVERAGENT'
Stop-Service -Name 'mssqlserver'

#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string[]]$services = $config_file.services;
[string[]]$servers = $config_file.servers;
[string]$_server;
[string]$_service;
[string]$_item;
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
[bool]$smtp_client.EnableSsl      = $config_file.ssl;
[string]$subject;
$body
#endregion



foreach ($_server in $servers)
{ 
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server };      

    $ScriptBlock =
    {
        param(
           $_server = $_server,
           $_service = $_service,
           $_item = $_item,
           $services = $services,
           $collector_name = $collector_name,
           $from = $from, 
           $to = $to,
           $subject = $subject,
           $body  = $body,
           $smtp_client   = $smtp_client
       )
      
        foreach ($_service in $services)
        {
        try
            {
                $_item = Get-Service -Name $_service -ComputerName $_server;                
        
                # Not running
                # Start the service and send mail
                if($_item.Status -ne "Running")
                {                   
                   Start-Service $_item.Name          
                            
                   $subject = $_server + ": " + $collector_name + " " + $_item.Name + " service status is not Running"; 
                   $body = $subject;
                   if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $_server 'Sending mail...'}; 
                   $smtp_client.Send($from, $to, $subject, $body);
                }
                # Any other status
                else
                {
                    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $_server $_item.Name $_item.Status };    
                }     
            }
            catch {throw $_ };
        }       
    }


    $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads);
    $RunspacePool.Open();
    $Jobs = @();

    1..$NumRows | Foreach-Object {
       $PowerShell = [powershell]::Create();
       $PowerShell.RunspacePool = $RunspacePool;
       $PowerShell.AddScript($ScriptBlock).AddParameter("_server",$_server).AddParameter("_service",$_service).AddParameter("_item",$_item).AddParameter("services",$services).AddParameter("smtp_client",$smtp_client).AddParameter("from",$from).AddParameter("to",$to).AddParameter("subject",$subject).AddParameter("collector_name",$collector_name).AddParameter("body",$body)

       $Jobs += $PowerShell.BeginInvoke();
    }    
    while ($Jobs.IsCompleted -contains $false)
    {        
       Start-Sleep -Milliseconds 10;       
    };
    $RunspacePool.Close();
    $RunspacePool.Dispose();
    
}



Get-Service -Name 'SQLSERVERAGENT'#,'mssqlserver'
