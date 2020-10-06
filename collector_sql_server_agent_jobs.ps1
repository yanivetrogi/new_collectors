
$ErrorActionPreference = 'Stop';

if ($psISE) {$path = Split-Path -Path $psISE.CurrentFile.FullPath;} else {$path = $global:PSScriptRoot;}

try
{
    $collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];
    $csv_file_full_name = Join-Path $path $collector_name #+ '.csv'
    $csv_file_full_name += '.csv';
    
    [string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
    [PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;
        
    $customername = $config_file.customername    
    $server = get-content env:computername   
    Join-Path $PSScriptRoot 'helpers.ps1'; 


    $objarr = New-Object System.Collections.ArrayList;

       
    $database = 'master'
    $command_text = 'SET NOCOUNT ON; exec DBA.dbo.MonitorFailedJobsCW @minutes = 10000;'
    $command_type = 'DataSet'
    $integrated_security = $true;
    [int]$return_value = 1


function writemetrictofile($objarr, $name, $out_file)
{
    $processing_path = $config_file.processing_path
    $ready_path = $config_file.ready_path
    $customername = $config_file.customername
    $file = $customername +"-" + $name +"-" + $(Get-date -Format yyyyMMdd-HHmmssffff) +'.csv' 
    $full_path = $processing_path + '\' + $file
    $hostn = get-content env:computername 
    
    $now = Get-Date ([datetime]::UtcNow) -Format s
    $now = $now.ToString()+"Z"
    
    foreach ($obj in $objarr)
    {    
        $obj | Add-Member -MemberType NoteProperty -Name FormatedTimestamp -Value $now
        $obj | Add-Member -MemberType NoteProperty -Name Computer -Value $hostn.trim() -Force;
    }
    $objarr | Export-Csv -Path $out_file -NoTypeInformation;
    #$target_file = $ready_path + '\' + $file
    #Move-Item $full_path $target_file    
}

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
        [string]$ApplicationName = "PowerShell"      
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



    $DataSet = Exec-Sql $server $database $command_text $command_type $integrated_security;

    foreach($row in $DataSet.Tables[0].Rows)
    {
        $status = $row.status;
        $cnt = $row.cnt;
        
        $return_value = $cnt    

    $obj = New-Object PSObject -Property @{
            Path = ("\\"+ $server +"\" + $collector_name + "_" + $status )
            CookedValue = $return_value
            }
        $objarr += $obj;
    }

    # Write to file
    writemetrictofile $objarr $collector_name $csv_file_full_name
    }
catch [Exception] {throw;}

#finally 
#    {
#        $objarr = $null; 
#        $collector_name - $null;
#        $obj = $null;
#    }

