param (
    [bool]$relaunched
)
Set-Location $PSScriptRoot
if(!$relaunched) {
    Write-Host "Relaunching...";
    Start-Process -Verb RunAs powershell.exe  -ArgumentList "-NoExit -Command `"$($PSCommandPath)`" -relaunched `$True";
    Exit;
}

$host.UI.RawUI.WindowTitle = "Mini Web Server Example";

Import-Module .\miniserver.psm1 -Force;

$index_Route = {
    param(
        $Request,
        $Response
    )

    $output = Get-Content -Path ".\index.html" -Encoding UTF8 -Raw;

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "text/html";
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

# Register web server routes
Set-MiniServerRoute -RoutePath "/" -ScriptBlock $index_Route;

# Start the web server
Start-MiniServer -Hostname "localhost" -Port "9797";
