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

# First we must import the miniserver module
Import-Module ..\..\miniserver.psm1 -Force;

########################################################################################
# Define scriptblocks for our routes.
# Route scriptblocks will receive the current request and response objects when called.
########################################################################################

$index_Route = {
    param(
        $Request,
        $Response
    )

    $output = Get-Content -Path ".\index.html" -Encoding UTF8 -Raw;

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "text/html";

    # Write index content to outputstream
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

$examplejson_Route = {
    param(
        $Request,
        $Response
    )

    $exampledatahash = @{
        "firstname"="John";
        "lastname"="Doe";
    };

    $output = ConvertTo-Json -InputObject $exampledatahash;

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "application/Json";

    # Write JSON data to outputstream
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

# Register web server routes
Set-MiniServerRoute -RoutePath "/" -ScriptBlock $index_Route;
Set-MiniServerRoute -RoutePath "/examplejson" -ScriptBlock $examplejson_Route;

# Start the web server
Start-MiniServer -Hostname "localhost" -Port "9797";

# Open url in default browser
Start-Process "http://localhost:9797"
