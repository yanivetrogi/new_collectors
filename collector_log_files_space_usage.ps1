﻿
#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[int]$threshold = $config_file.threshold_tlog_percent_used;
[string[]]$servers = $config_file.servers;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];
[string]$message;

[string]$server;
[string]$query = "SET NOCOUNT ON; EXEC DBA.dbo.MonitorLogFileSpaceUsed @threshold = 0;";
[string]$command_type = "DataSet";
[string]$database = "DBA";

[array]$array = @();
[long]$file_size_mb = 0;
[long]$used_size_mb = 0;
[long]$percent = 0;

[string]$graylog_server = $config_file.graylog_server;
[string]$graylog_port = $config_file.graylog_port;

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


# Exceute database commands
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
    {   
        $ds = Exec-Sql $server $database $query $command_type $true;

        # Loop over the table
        foreach ($Row in $ds.Tables[0].Rows)
        {
    
            $db           = $Row.Item('database').trim();
            $file_size_mb = $Row.Item('file_size_mb');
            $used_size_mb = $Row.Item('used_size_mb');
            $percent      = $Row.Item('percent');
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $server "Database:" $db "file Size mb:" $file_size_mb "used size mb:" $used_size_mb "Percent:" $percent;};   
        

            # Graylog        
            if($send_graylog -eq $true) {Send-PSGelfUDP -GelfServer $graylog_server -Port $graylog_port -ShortMessage $collector_name -Facility $server -AdditionalField @{database=$db; file_size_mb=$file_size_mb; used_size_mb=$used_size_mb; percent=$percent} }

            # If the percent used has crossed the threshold
            if ($percent -gt $threshold)
            {
                $message = "Database: " + $db + "  file Size mb: " + $file_size_mb + "  used size mb: " + $used_size_mb + "  Percent: " + $percent + "  has crossed the predefined threshold: " + $threshold;                
                $array += [Environment]::NewLine + $message;           
            }    
        }

        if($array -ne $null)
        {
            $body = $array;
            $subject = $server + ": " + $collector_name;
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Yellow $server $array };
            #if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $server "Sending mail.." };
            if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)}; 
        }
        
        $array   = $null;        
        $body    = $null;
        $message = $null;    
        $db = $null;
        $file_size_mb = $null;
        $used_size_mb = $null;
        $percent = $null;

    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        if ($send_mail -eq $true ) {$smtp_client.Send($from, $to, $subject, $body)};   
    }

    $exception = $null;
    $subject = $null;
    $body = $null;
    $message = $null;

    $array   = $null;            
    $db = $null;
    $file_size_mb = $null;
    $used_size_mb = $null;
    $percent = $null;

}