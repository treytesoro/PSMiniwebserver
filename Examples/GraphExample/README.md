# aztest.ps1

You'll need the current Az module (NOT AzureRM - that's deprecated).

Check out Microsoft Docs for more info: [Installing Az Module](https://learn.microsoft.com/en-us/powershell/azure/install-azps-windows?view=azps-11.3.0&tabs=powershell&pivots=windows-psgallery)

Once installed you'll need to connect before running aztest.ps1

` Connect-AzAccount`


You will also need the official Microsoft Graph PowerShell Module - MgGraph (NOT MsGraph)

Check out this document for installing MgGraph: [Installing MgGraph](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation?view=graph-powershell-1.0#installation)

The aztest.ps1 script will attempt to start an mggraph session using `Connect-MgGraph`, you may be prompted to login again.

## Quick explanation

We're using the following for the `/` (index) page scriptblock:

```
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
    # http://localhost:9797/az URL, represented by $az_Route scripblock, expects "username" for its query.
    $output = New-MiniServerHtmlSingleQuery -Headers "DisplayName", "UPN", "Id" -Url "http://localhost:9797/az" -Queryparameter "username";

    $Response.StatusCode = 200;
    $Response.ContentLength64 = $output.Length;
    $Response.ContentType = "text/html";

    # Write index content to outputstream
    [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
    $sw.Write($output);
    $sw.Close();
}
```

And the following for the `/az` endpoint scriptblock

```
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
```