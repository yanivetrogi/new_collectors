# Monitor AlwaysOn state

#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[string]$helpers_file_full_name = Join-Path $PSScriptRoot 'helpers.ps1';

[bool]$user_interactive = [Environment]::UserInteractive;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];

[int]$seconds = $config_file.threshold_alwayson_duration_seconds;
[string[]]$servers = $config_file.servers;
[string]$message;

[string]$server;
[string]$query = 'EXEC DBA.dbo.MonitorReplicationDistributionAgentsSynschronizationStatus @send_mail = 0, @seconds = 0, @debug = 1;'
[string]$command_type = 'DataSet';
[string]$database = 'DBA';

[array]$array = @();
[System.Data.DataSet]$DataSet = New-Object System.Data.DataSet;

$graylog_server = $config_file.graylog_server;
$graylog_port = $config_file.graylog_port;

$send_mail = $false;
$send_graylog = $true;
$send_sms = $true;

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


function Exec-Sql
{
    [CmdletBinding()]
    [Alias()]
    #[OutputType([int])]
    Param
    (    
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=0)]
        [string]$Server,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=1)]
        [string]$Database,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=2)]
        [string]$CommandText,

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=3)]
        [string]$CommandType,       

        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$false, Position=4)]
        [bool]$IntegratedSecurity,  
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=5)]
        [string]$User,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=6)]
        [string]$Password,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=7)]
        [int32]$CommandTimeOut = 30,

        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$false, Position=8)]
        [string]$ApplicationName = "CloudMonitoringCollector"      
    )

    Begin
    {
        if($IntegratedSecurity -eq $true)
        {
            $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; Application Name=$ApplicationName;";
        }
        else
        {
            # Validate the credentials were supplied
            if( [string]::IsNullOrEmpty($User)) {Throw 'The ''$User'' variable does not contain a valid value'}
            if( [string]::IsNullOrEmpty($Password)) {Throw 'The ''$Password'' variable does not contain a valid value'}

            $ConnectionString = "Server=$Server; Database=$Database; Integrated Security=$IntegratedSecurity; User=$User; Password=$Password; Application Name=$ApplicationName;";
        }
        #Write-Host $ConnectionString -ForegroundColor Yellow

        if($CommandType -notin ('NonQuery' ,'Scalar' ,'DataSet') )
        {
            throw 'The ''$CommandType'' parameter contains an invalid value Valid values are: ''NonQuery'' ,''Scalar'' ,''DataSet''';
        }

        try
        {
            $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString);
            $SqlCommand = $sqlConnection.CreateCommand();
            $SqlConnection.Open(); 
            $SqlCommand.CommandText = $CommandText;                      
                  
            # NonQuery
            if($CommandType -eq 'NonQuery')
            {      
                $sqlCommand.ExecuteNonQuery();
                return;
            }

            # Scalar
            if($CommandType -eq 'Scalar')
            {                
                 Write-Host $CommandText -ForegroundColor Yellow   
                                   
                $Val = $sqlCommand.ExecuteScalar();
                return $Val;
            }
            
            # DataSet
            if($CommandType -eq "DataSet")
            {
                $DataSet = New-Object System.Data.DataSet;
                $SqlDataAdapter = New-Object System.Data.SqlClient.SqlDataAdapter;
                $SqlDataAdapter.SelectCommand = $SqlCommand;    
                $SqlDataAdapter.Fill($DataSet);  
                return $DataSet;   
            }
        }
        catch
        {       
            throw;
        }
    }
}


foreach ($server in $servers)
{
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Green $server };
    try
    {   # Execute the stored procedure 
        $ds = Exec-Sql $server $database $query $command_type $true;        
                    
        foreach ($Row in $ds.Tables[0].Rows)
        {            
            [string]$subscriber = $Row.Item('subscriber');
            [string]$publication = $Row.Item('publication');            
            [string]$status = $Row.Item('status');
            [string]$warning = $Row.Item('warning');
            [int]$pending_commands = $Row.Item('pending_commands');
            [string]$estimated_process_time_ss = $Row.Item('estimated_process_time_ss');            
            [int]$latency_ss = $Row.Item('latency (ss)');
            [string]$last_dist_sync = $Row.Item('last_dist_sync');
            [int]$last_dist_sync_diff_ss = $Row.Item('last_dist_sync_diff_ss');

            # Graylog        
            if($send_graylog -eq $true) {Send-PSGelfUDP -GelfServer $graylog_server -Port $graylog_port -ShortMessage $collector_name -Facility $server `
            -AdditionalField @{subscriber=$subscriber; publication=$publication; status=$status; warning=$warning; pending_commands=$pending_commands; estimated_process_time_ss=$estimated_process_time_ss; latency_ss=$latency_ss; last_dist_sync=$last_dist_sync; last_dist_sync_diff_ss=$last_dist_sync_diff_ss} }
        }            
         

        if($array -ne $null)
        {
            if ($user_interactive -eq $true ) {Write-Host -ForegroundColor Yellow $array};     

            $body = $array;
            $subject = $server + ': ' + $collector_name;            
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $server "Sending mail.." };
            if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};   
        }        
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $server + ': Exception at ' + $collector_name;
        $body = $exception;                      
       if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)}; 
       #if ($send_sms -eq $true) {Invoke-WebRequest $sms_url -Method POST -Body $sms_post_params;};  
    }

    #$exception = $null;
    #$subject = $null;
    #$body = $null;
    #$ds = $null;
    #$array = $null;
    #$message = $null;

}