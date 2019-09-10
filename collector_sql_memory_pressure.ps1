﻿# Monitor disk space



#region <variables>
$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;

[int]$threshold = $config_file.threshold_memory_pressure_count;
[int]$minutes = $config_file.threshold_memory_pressure_duration_minutes;

[string[]]$servers = $config_file.servers;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];
[string]$message;

[string]$_server;
[string]$_query = "SET NOCOUNT ON; EXEC DBA.dbo.MonitorMemoryPressure @minutes = $minutes;";
[string]$_command_type = "DataSet";
[string]$_database = "DBA";

[array]$array = @();
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

[Net.Mail.SmtpClient]$smtp = New-Object Net.Mail.SmtpClient($smtp_server);
if($use_default_credentials -eq $true)
{
    [object]$smtp.Credentials  = $credential;
}
[int32]$smtp.Port          = $config_file.port;
[bool]$smtp.EnableSsl      = $config_file.ssl;
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

        # Loop over the table
        foreach ($Row in $DataSet.Tables[0].Rows)
        {    
            $alert_count = $Row.Item('alert_count');
            
        
            # If the percent used has crossed the threshold
            if ($alert_count -gt $threshold)
            {'['
                $message = 'The Number of Memory Pressure events: ''' + $alert_count + ''' has crossed the predefined threshold: ''' + $threshold + ''' in the last ' + $minutes + ' minutes';            
                $array += [Environment]::NewLine + $message;           
            }    
        }

        if($array -ne $null)
        {
            $body = $array;
            $subject = $_server + ": " + $collector_name;
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server "Sending mail.." };
            $smtp.Send($from, $to, $subject, $body);
        }
        if ($user_interactive -eq $true ) {Write-Host -ForegroundColor Yellow $array};      
        $array   = $null;        
        $body    = $null;
        $message = $null;        

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