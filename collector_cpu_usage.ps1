<#
.SYNOPSIS
    Monitors CPU Usage 
.DESCRIPTION
    Removes user defined variables from the PowerShell ISE or console. $StartupVars must be defined prior to running
    this function, preferably in a profile script. Populate $StartUpVars with 'Get-Variable | Select-Object -ExpandProperty
    Name'. All variables added after populating $StartupVars will be removed when this function is run.
.EXAMPLE
     Remove-MrUserVariable
.INPUTS
    None
.OUTPUTS
    None
.NOTES
    Author:  Yaniv Etrogi
    Website: http://sqlserverutilities.com
    Twitter: @mikefrobbins
#>


#region <variables>
[string]$config_file_full_name = Join-Path $PSScriptRoot 'config.json';
[PSCustomObject]$config_file = Get-Content  $config_file_full_name | Out-String| ConvertFrom-Json;

[int]$threshold = $config_file.threshold_cpu_usage_pecent;
[string[]]$servers = $config_file.servers;
[string]$file_full_name;
[int16]$counter;
[int16]$num_times_crossed_threshold;
[int16]$num_samples = 4;
[bool]$send_mail = $false;
[bool]$user_interactive = [Environment]::UserInteractive;
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
#endregion


foreach($_server in $servers)
{
    try
    {
        # Get the Total CPU time
        #$current_value = Get-Counter '\Processor(_Total)\% Processor Time' -ComputerName $_server | select -expand CounterSamples | select CookedValue;
        $current_value = Get-Counter '\Processor(_Total)\% Processor Time' | select -expand CounterSamples | select CookedValue;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Green $_server ' CPU Usage:' $current_value.CookedValue }#([math]::Round($current_value.CookedValue)) };

        $file_name = $_server + '_ProcessorTime.csv';
        $file_full_name = Join-Path $PSScriptRoot $file_name

        # If the file does not exists create it
        if (!(Test-Path $file_full_name)) {$current_value | Export-Csv $file_full_name -NoTypeInformation -Append;}
    
        # Read the file
        $file_values = Import-Csv $file_full_name;
    

        $counter = 1;
        $num_times_crossed_threshold = 0;

        [System.Collections.ArrayList]$array_list = New-Object System.Collections.ArrayList;
        
        
        # Loop over the file and find how many times the threshold has been crossed
        foreach($file_value in $file_values)
        {   
            # Loop over the file values while excluding the last value         
            [int]$file_value_rounded = $file_value.CookedValue;
            if ($file_value_rounded -gt $threshold) 
            {                    
                $num_times_crossed_threshold += 1;                         
            }                         
            

            # First iteration
            # Add current value as the first element
            # Add the first line of the file that we have read as the second element in the psobject
            if($counter -eq 1)
            {
                $psobject = New-Object PSObject -Property @{CookedValue = $current_value.CookedValue;}
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $counter $current_value.CookedValue;}   
                $array_list += $psobject;    

                $psobject = New-Object PSObject -Property @{CookedValue = $file_value.CookedValue;}
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $counter $file_value.CookedValue;}  
                $array_list += $psobject;                       
            }
            else
            # Add file value
            {
                $psobject = New-Object PSObject -Property @{CookedValue = $file_value.CookedValue;}
                if ($user_interactive -eq $true) {Write-Host -ForegroundColor DarkYellow $counter   $file_value.CookedValue;}  
                $array_list += $psobject;   
            }
                            
            $counter++          
            # Exit the loop before the last element which is dropped out as a result of the new value being the first element
            # This way we maintain a fixed number of lines in the file
            if($counter -eq $file_values.Count ) {break};           
        }
        


        # Following the initial deployment the file does not yet contain the desired number of values
        if ($file_values.Count -lt $num_samples)
        {
            $psobject = New-Object PSObject -Property @{CookedValue = $current_value.CookedValue;}
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Magenta $counter   $file_value.CookedValue;}  
            $array_list += $psobject;
        }
                  
     

        # Write to file
        $array_list | Export-Csv $file_full_name -Force;


        
        if ($num_times_crossed_threshold -ge $num_samples-1)
        {
            $body = '''Processor(_Total)\% Processor Time'' has crossed the predefined threshold ''' + $threshold + ''' for ''' + $num_samples + ''' consecutive checks';                
            if ($user_interactive -eq $true) {Write-Host -ForegroundColor Cyan $_server':' $body }; 

            # Send mail if the threshold has been crossed in the last xx checks
            if ($send_mail -eq $true)
            {
                $subject = $_server + ': ' + $collector_name;                
                $smtp_client.Send($from, $to, $subject, $body);
            }
        }
    }
    catch [Exception] 
    {
        $exception = $_.Exception;
        if ($user_interactive -eq $true) {Write-Host -ForegroundColor Red $exception};      
            
        $subject = $_server + ': Exception at ' + $collector_name;
        $body = $exception;                      
        $smtp_client.Send($from, $to, $subject, $body);   
    }

    $exception = $null;
    $subject = $null;
    $body = $null;
    $message = $null;

    
}

