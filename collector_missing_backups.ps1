﻿# Monitor AlwaysOn state

#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[bool]$user_interactive = [Environment]::UserInteractive;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];

[int]$threshold_full_backup_hours = $config_file.threshold_full_backup_hours;
[int]$threshold_log_backup_hours = $config_file.threshold_log_backup_hours;

[string[]]$servers = $config_file.servers;
[string]$message;

[string]$server;
[string]$query = 'SET NOCOUNT ON; EXEC DBA.dbo.MonitorMissingBackups @full_backup_threshold_hours = ' + $threshold_full_backup_hours +', @log_backup_threshold_hours = ' + $threshold_log_backup_hours + ';';
[string]$command_type = 'DataSet';
[string]$database = 'DBA';

[array]$array = @();
[System.Data.DataSet]$DataSet = New-Object System.Data.DataSet;
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


[string]$helpers_file_full_name = Join-Path $PSScriptRoot 'helpers.ps1';
$helpers_file_full_name;

<#
.Synopsis
   Executes sql command
.DESCRIPTION
   A generic code to execute sql commands
.EXAMPLE
   ExecuteScalar
        $val = Exec-Sql $server $database $command_text $command_type $integrated_security;
   DataSet        
        $val = Exec-Sql $server $database $command_text $command_type $integrated_security;

.EXAMPLE
   Another example of how to use this cmdlet
#>
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
            [string]$id = $Row.Item('id');
            [string]$database_name = $Row.Item('database_name');
            [string]$type = $Row.Item('type');


            $message = 'id: ' + $id + ' database_name: ' + $database_name + ' backup_type: ' + $type;                     
            $array += [Environment]::NewLine + $message;               
        }            
         

        if($array -ne $null)
        {
            if ($user_interactive -eq $true ) {Write-Host -ForegroundColor Yellow $array};     

            $body = $array;
            $subject = $server + ': ' + $collector_name;            
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $server "Sending mail.." };
            $smtp_client.Send($from, $to, $subject, $body);
        }        
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        $smtp_client.Send($from, $to, $subject, $body);   
    }

    #$exception = $null;
    #$subject = $null;
    #$body = $null;
    #$ds = $null;
    #$array = $null;
    #$message = $null;

}