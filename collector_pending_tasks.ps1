# Monitor sql server pending tasks

#region <variables>

[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];

[int]$threshold = $config_file.threshold_work_queue_count;
[string[]]$servers = $config_file.servers;
[string]$message;

[string]$_server;
[string]$_query = "SET NOCOUNT ON; EXEC DBA.dbo.MonitorPendingTasks;"
[string]$_command_type = "DataSet";
[string]$_database = "DBA";

[array]$array = @();
#$ArrayList = [System.Collections.ArrayList]@();

[System.Data.DataSet]$DataSet = New-Object System.Data.DataSet;

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
[bool]$smtp_client.EnableSsl      = $config_file.ssl;
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
                    
        foreach ($Row in $DataSet.Tables[0].Rows)
        {
            [int]$current_tasks_count = $Row.Item('current_tasks_count');
            [int]$current_workers_count = $Row.Item('current_workers_count');
            [int]$active_workers_count = $Row.Item('active_workers_count');
            [int]$work_queue_count = $Row.Item('work_queue_count');
            [int]$pending_disk_io_count = $Row.Item('pending_disk_io_count');
        }
        # Graylog        
       if($send_graylog -eq $true) {Send-PSGelfUDP -GelfServer $graylog_server -Port $graylog_port -ShortMessage $collector_name -Facility $_server -AdditionalField @{current_tasks_count=$current_tasks_count; current_workers_count=$current_workers_count; active_workers_count=$active_workers_count; work_queue_count=$work_queue_count; pending_disk_io_count=$pending_disk_io_count} }

            
        if($work_queue_count -gt $threshold)
        {
            $message = "work_queue_count: " + $work_queue_count + " has crossed the predefined threshold: " + $threshold;            
            $array += [Environment]::NewLine + $message;
            
            if ($send_sms -eq $true) {Invoke-WebRequest $sms_url -Method POST -Body $sms_post_params;};
        }
        
        if($array -ne $null)
        {
            $body = $array;
            $subject = $_server + ': ' + $collector_name;            
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server "Sending mail.." };
            if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};      
            #sms      
        }
        if ($user_interactive -eq $true ) {Write-Host -ForegroundColor Yellow $array};      
        $array   = $null;        
        $body    = $null;
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $_server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};   
        if ($send_sms -eq $true) {Invoke-WebRequest $sms_url -Method POST -Body $sms_post_params;};
        Throw;
    }

    $exception = $null;
    $subject = $null;
    $body = $null;
    $message = $null;

}