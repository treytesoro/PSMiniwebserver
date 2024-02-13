param (
    [bool]$relaunched
)
Set-Location $PSScriptRoot
if(!$relaunched) {
    Write-Host "Relaunching...";
    Start-Process -Verb RunAs powershell.exe  -ArgumentList "-NoExit -Command `"$($PSCommandPath)`" -relaunched `$True";
    Exit;
}

# Let's test some Azure cmdlet stuff
# Connect-AzAccount # only need this once
Connect-MgGraph

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

    # You can do something like:
    # New-MiniServerHtmlSingleQuery -Headers "DisplayName", "UPN", "Id" -Url "http://localhost:9797/az" -Queryparameter "username" | Out-File .\test.html
    # Then use that file for output
    # $output = Get-Content -Path ".\test.html" -Encoding UTF8 -Raw;

    # Or you can just generate the html on the fly and output that.
    $output = New-MiniServerHtmlSingleQuery -Headers "DisplayName", "UPN", "Id" -Url "http://localhost:9797/az" -Queryparameter "username";

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

$az_Route = {
    param(
        $Request,
        $Response
    )
    
    $input = @{};
    $output = "";

    # grab the request body and convert to json
    # we expect: { "username": "someusername" }
    [System.IO.StreamReader]$sr = [System.IO.StreamReader]::new($Request.InputStream);
    $input = $sr.ReadToEnd() | ConvertFrom-Json;
    $sr.Close();

    $username = $input.username;

    $mguser =  Get-MgUser -Filter "startsWith(DisplayName, '$($username)')" | Select-Object -Property DisplayName, UserPrincipalName, Id
    if($mguser.length -gt 1) {
        $output = ConvertTo-Json -InputObject $mguser
    }
    else {
        $output = "[ " + (ConvertTo-Json -InputObject $mguser) + " ]";
    }

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
Set-MiniServerRoute -RoutePath "/az" -ScriptBlock $az_Route;

# Start the web server
Start-MiniServer -Hostname "localhost" -Port "9797";

# Open url in default browser
Start-Process "http://localhost:9797"
