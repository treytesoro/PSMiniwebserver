param (
    [bool]$relaunched
)

Set-Location $PSScriptRoot

# Always launch in new terminal as admin.
# We can close the new terminal window to end the server
# without closing the initial terminal window.
if(!$relaunched) {
    Write-Host "Relaunching...";
    Start-Process -Verb RunAs powershell.exe  -ArgumentList "-NoExit -Command `"C:\Users\tgtesoro\source\repos\devops\WebPSServer\testserver.ps1`" -relaunched `$True";
    Exit;
}

$host.UI.RawUI.WindowTitle = "Mini Web Server"

Import-Module .\server.psm1 -Force

function Log {
    param($message)

    Write-Host $message;
    Add-Content -Path "C:\Users\tgtesoro\source\repos\devops\WebPSServer\noclone\log.txt" -Value $message;
}

$userlockquery_Route = {
    param(
        [System.Net.HttpListenerRequest]$Request, 
        [System.Net.HttpListenerResponse]$Response
    )

    $output = "";

    if($Request.ContentType.ToUpper() -eq "APPLICATION/JSON") {

        [System.IO.StreamReader]$sw = [System.IO.StreamReader]::new($Request.InputStream);
        $readData = $sw.ReadToEnd();
        $sw.Dispose();

        $inputDataHash = ConvertFrom-Json $readData;

        if($inputDataHash.username -ne $null) {
            $username = $inputDataHash.username;
        
            Install-Module ThreadJob -Repository PSGallery | Out-Null
            Import-Module ThreadJob | Out-Null
            
            [System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices") | Out-Null
            [System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.ActiveDirectory") | Out-Null

            $DCs = [System.DirectoryServices.ActiveDirectory.DomainController]::FindAll([System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain)

            # Store in shared session variable
            $SessionData.data = [System.Collections.ArrayList]::new();
            $SessionData.Runstate = "Running";

            # Track completion state of Threadjobs with Hashtable
            $dcThreadCounter = @{
                totalDCs = $DCs.Count;
                dcthreads = 0
            };

            $DCs | Select-Object Name | ForEach-Object {
                Start-ThreadJob -ScriptBlock {
                    param(
                        [string]$servername, 
                        [string]$username,
                        [Hashtable]$SessionData,
                        [Hashtable]$dcThreadCounter
                    )
                    $dcThreadCounter.dcthreads++;
                    Import-Module ActiveDirectory | Out-Null

                    $passwordStatus = get-aduser -identity $username -server $servername `
                    -properties * | `
                    Select-Object accountexpirationdate, accountexpires, accountlockouttime, `
                    badlogoncount, padpwdcount, lastbadpasswordattempt, lastlogondate, `
                    lockedout, passwordexpired, passwordlastset, pwdlastset, DistinguishedName;

                    $returndata = @{}
                    $returndata.lastbadpassattempt = $passwordStatus.lastbadpasswordattempt;
                    $returndata.origlock = "N/A";
                    $returndata.username = $username;

                    if ($True -eq $passwordStatus.lockedout) {
                        $metadata = $dc.currentDC.GetReplicationMetadata($passwordStatus.DistinguishedName)
                        $returndata.origlock = $metadata.lockouttime.OriginatingServer.ToUpper().split('.')[0]
                    }

                    $SessionData.data.Add($returndata);

                    if($dcThreadCounter.dcthreads -eq $dcThreadCounter.totalDCs) {
                        # signal completion
                        $SessionData.Runstate = "Finished";
                    }
                } -ArgumentList $_.Name, $username, $SessionData, $dcThreadCounter
            };

            $output = '{"status": "Running"}'
        }
        else
        {
            $output = '{"error": "No username was supplied"}' # forgot to enter usename?
        }
    }
    else {
        $output = '{"error": "Unsupported Content-Type header was supplied"}' # send an  error
    }

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "application/json";
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
};

$somepath_Route = {
    param($Request, $Response)

    Log("SOMEPATH");
    $output = (Get-Content -Path "C:\Users\tgtesoro\source\repos\devops\WebPSServer\noclone\log.txt" -Raw);
    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "text/plain";
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
};

$getuserlockdata_Route = {
    param($Request, $Response)

    [System.Collections.ArrayList]$arrlist = $SessionData.data

    $output = ConvertTo-Json $SessionData;

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "application/json";
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
};

$index_Route = {
    param(
        $Request,
        $Response
    )

    $output = Get-Content -Path "C:\Users\tgtesoro\source\repos\devops\WebPSServer\index.html" -Encoding UTF8 -Raw

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "text/html";
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

RegisterLog -logname "Log" -logfunction ${function:Log};
RegisterRoute -path "/userlockquery" -sb $userlockquery_Route;
RegisterRoute -path "/somepath" -sb $somepath_Route;
RegisterRoute -path "/getuserlockdata" -sb $getuserlockdata_Route;
RegisterRoute -path "/" -sb $index_Route;

RunWebServer;
