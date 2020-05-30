$ErrorActionPreference = 'Stop'
#$path = Get-Location;

if ($psISE) {$path = Split-Path -Path $psISE.CurrentFile.FullPath;} else {$path = $global:PSScriptRoot;}


    $collector_name = $MyInvocation.MyCommand.Name.Split(".")[0];
    
    [string]$config_file_full_name = Join-Path $path 'config.json';
    [PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;


    $processing_path = $config_file.processing_path
    $ready_path = $config_file.ready_path
    $customername = $config_file.customername
    $metricspath = $config_file.metricspath

    $server = get-content env:computername   
     #"C:\GoogleDrive\Team\PowerShell\CloudMonitoring\new_collectors\helpers.ps1" 
     Join-Path $path 'helpers.ps1';
   
   <#
    function writemetrictofile($objarr, $name)
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
            $obj | Add-Member -MemberType NoteProperty -Name FormatedTimestamp -Value $now -Force
            $obj | Add-Member -MemberType NoteProperty -Name Computer -Value $hostn.trim() -Force;
        }
        $objarr | Export-Csv -Path $full_path -NoTypeInformation;
        $target_file = $ready_path + '\' + $file
        Move-Item $full_path $target_file        
    }
    #>
    
    $server = get-content env:computername 
    $delay=1
    $count=1


    try
    {
        $metrics = Get-Counter -Counter $metricspath -SampleInterval $delay -MaxSamples $count            
        foreach($metric in $metrics)            
        {            
            $obj = $metric.CounterSamples | Select-Object -Property Path, CookedValue;   
            $objarr += $obj          
        }     

    writemetrictofile ($objarr) ($collector_name)    
}
catch {Throw; }

#finally 
#    {
#        $objarr = $null; 
#        $collector_name - $null;
#        $obj = $null;
#    }

