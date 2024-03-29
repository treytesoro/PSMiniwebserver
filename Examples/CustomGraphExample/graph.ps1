param (
    [bool]$relaunched
)
[console]::WindowWidth=100; 
[console]::WindowHeight=20; 
[console]::BufferWidth=[console]::WindowWidth

Set-Location $PSScriptRoot
if(!$relaunched) {
    Write-Host "Relaunching...";
    Start-Process -Verb RunAs powershell.exe  -ArgumentList "-NoExit -Command `"$($PSCommandPath)`" -relaunched `$True";
    Exit;
}

# Let's test some Azure cmdlet stuff
# Connect-AzAccount # only need this once
# Connect-MgGraph

$host.UI.RawUI.WindowTitle = "Mini Web Server Example";

# First we must import the miniserver module
Import-Module ..\..\miniserver.psm1 -Force;

########################################################################################
# Define scriptblocks for our routes.
# Route scriptblocks will receive the current request and response objects when called.
########################################################################################

# This will respond to the "/" (index) path
# The ContentType will be set to "text/html" and
# the html content will be generated by the New-MiniServerHtmlSingleQuery cmdlet;
$index_Route = {
    param(
        $Request,
        $Response
    )

    # You can do something like:
    # New-MiniServerHtmlSingleQuery -Headers "DisplayName", "UPN", "Id" -Url "http://localhost:9797/az" -Queryparameter "username" | Out-File .\test.html
    
    # Then use that file for output
    $output = Get-Content -Path ".\graph.html" -Encoding UTF8 -Raw;

    # Or you can just generate the html on the fly and output that.
     # http://localhost:9797/az URL, represented by $az_Route scripblock, expects "username" for its query.
    # $output = New-MiniServerHtmlSingleQuery -Headers "DisplayName", "UPN", "Id" -Url "http://localhost:9797/az" -Queryparameter "username";

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "text/html";

    # Write index content to outputstream
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

# This will respond to the "/az" path
# The ContentType will be set to "application/Json" and
# the json content will be generated by the Get-MgUser | ConvertTo-Json cmdlets
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

$connectGraph_Route = {
    param(
        $Request,
        $Response
    )

    $input = @{};
    # grab the request body and convert to json
    [System.IO.StreamReader]$sr = [System.IO.StreamReader]::new($Request.InputStream);
    $input = $sr.ReadToEnd() | ConvertFrom-Json;
    $sr.Close();

    $clientid = $input.clientid;
    $tenantid = $input.tenantid;

    if($clientid.length -eq 0 -or $tenantid.length -eq 0) {
        Connect-MgGraph;
    }
    else{
        Connect-MgGraph -ClientId $clientid -TenantId $tenantid;
    }

    $output = '{"status": "Connected"}';
    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "application/Json";

    # Write JSON data to outputstream
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

$invokegraph_Route = {
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

    $graphurl = $input.graphurl;

    $graphurl = [URI]::EscapeUriString($graphurl);
    $output = (Invoke-MgGraphRequest -Method GET -Uri $graphurl | ConvertTo-Json -Depth 10);
    
    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "application/Json";

    # Write JSON data to outputstream
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}

$getmgcontext_Route = {
    param(
        $Request,
        $Response
    )

    $output = ""

    $mgctx = Get-MgContext;

    $output = $mgctx | ConvertTo-Json;

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
Set-MiniServerRoute -RoutePath "/az" -ScriptBlock $az_Route;
Set-MiniServerRoute -RoutePath "/connectgraph" -ScriptBlock $connectGraph_Route;
Set-MiniServerRoute -RoutePath "/invokegraph" -ScriptBlock $invokegraph_Route;
Set-MiniServerRoute -RoutePath "/getmgcontext" -ScriptBlock $getmgcontext_Route;
$fullPathToStaticFiles = "<full path to static files you want to serve (images, scripts, stylesheets, etc.)>";
Set-MiniServerStaticRoutes -StaticRoute "/static" -LocalPath $fullPathToStaticFiles;

# Start the web server
Start-MiniServer -Hostname "localhost" -Port "9797";

# Open url in default browser
Start-Process "http://localhost:9797";
