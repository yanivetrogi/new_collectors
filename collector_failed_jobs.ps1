﻿# Monitor disk space


#region <variables>
$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];

[int]$threshold = $config_file.threshold_faild_jobs_duration_minutes;
[string[]]$servers = $config_file.servers;
[string]$message;

[string]$_server;
[string]$_query = "SET NOCOUNT ON; EXEC DBA.dbo.MonitorFailedJobs @minutes = ' $threshold ' ;"
[string]$_command_type = "DataSet";
[string]$_database = "DBA";

[array]$array = @();
[string]$database;
[long]$file_size_mb = 0;
[long]$used_size_mb = 0;
[long]$percent = 0;
[System.Data.DataSet]$DataSet = New-Object System.Data.DataSet;
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



# Exceute database commands
function execute_sql_command ($_server, $_database, $_query, $_command_type )
{ 
  try
  {
      $SqlConnection = New-Object System.Data.SqlClient.SqlConnection;
      $SqlConnection.ConnectionString = "Server = $_server; Database = $_database; Integrated Security=True; Application Name=CloudMonitoringCollector;";

      $SqlCommand = New-Object System.Data.SqlClient.SqlCommand;
      $SqlCommand.CommandText = $_query;
      $SqlCommand.Connection = $SqlConnection;  

 
      if($_command_type -eq "Text")
      {      
        $SqlConnection.Open();      
        $SqlCommand.ExecuteNonQuery();        
      }

      if($_command_type -eq "DataSet")
      {
        $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
        $SqlAdapter.SelectCommand = $SqlCommand;    
        $SqlAdapter.Fill($DataSet);     
      }
  }
 catch [System.Data.SqlClient.SqlException] 
 {    
    $execption = $_.Exception;    
   if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $execption};    
    #throw;  
 }

 if ($SqlConnection.State -eq "Open") {$SqlConnection.Close()};  
}


foreach ($_server in $servers)
{
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Green $_server };
    try
    {   # Execute the stored procedure and get the t-log space used
        execute_sql_command ($_server)($_database)($_query)($_command_type);

        if ($DataSet.Tables[0].Rows.Count -lt 1 ) {return};

        # Loop over the table
        foreach ($Row in $DataSet.Tables[0].Rows)
        {
    
            $name         = $Row.Item('name');
            $step_name    = $Row.Item('step_name');
            $step_message = $Row.Item('message');            
            #if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $database};   
        
            $message = "Job: " + $name + "  step : " + $step_name + "  failed: " + $step_message;            
            $array += [Environment]::NewLine + $message;                           
        }

        if($array -ne $null)
        {
            $body = $array;
            $subject = $_server + ": " + $collector_name;
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server "Sending mail.." };
            $smtp_client.Send($from, $to, $subject, $body);
        }
        if ($user_interactive -eq $true ) {Write-Host -ForegroundColor Yellow $array};      
        $array   = $null;        
        $body    = $null;
        #$message = $null;        

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