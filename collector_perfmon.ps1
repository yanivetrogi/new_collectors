Import-Module psgelf;
#$ErrorActionPreference = 'Stop'
#$path = Get-Location;

#if ($psISE) {$path = Split-Path -Path $psISE.CurrentFile.FullPath;} else {$path = $global:PSScriptRoot;}

   
#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

Join-Path $PSScriptRoot 'helpers.ps1';

[bool]$user_interactive = [Environment]::UserInteractive;
[string]$collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];

$processing_path = $config_file.processing_path
$ready_path = $config_file.ready_path
$customername = $config_file.customername
$metricspath = $config_file.metricspath

[string[]]$servers = $config_file.servers; 

[string]$graylog_server = $config_file.graylog_server;
[string]$graylog_port = $config_file.graylog_port;


#endregion


    
    
$delay=1;
$count=1;

foreach($server in $servers)
{
    if ($user_interactive -eq $true) {Write-Host -ForegroundColor Green $server }; 
    try
    {
        $metrics = Get-Counter -Counter $metricspath -SampleInterval $delay -MaxSamples $count            
        foreach($metric in $metrics)            
        {            
            $obj = $metric.CounterSamples | Select-Object -Property Path, CookedValue;   
            $objarr += $obj          
        }     
        # Export to csv
        #writemetrictofile ($objarr) ($collector_name)    


        $obj = $null;
        
        # Graylog
        foreach($obj in $objarr)
        {    
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $server $obj.Path $obj.CookedValue}; 
            #Send-PSGelfUDP -GelfServer $graylog_server -Port $graylog_port -ShortMessage $obj.path -FullMessage $obj.CookedValue;
        }
    }
    catch {Throw; }
}

$metrics = $null;
$objarr =  $null; 
$collector_name = $null;
$obj = $null;


