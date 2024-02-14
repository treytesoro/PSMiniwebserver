# param (
#     [bool]$relaunched
# )

# Set-Location $PSScriptRoot

# if(!$relaunched) {
#     Write-Host "Relaunching...";
#     Start-Process -Verb RunAs powershell.exe  -ArgumentList "-NoExit -Command `"$($PSCommandPath)`" -relaunched `$True";
#     Exit;
# }

New-Module -Name PodgeModule -ScriptBlock {
    $_currenthostname = "";
    $_currentport = "";
    # Hold our routes, a default route for index has been added for example
    $routes = [Hashtable]::Synchronized( @{
        # Example of a route's hash value is routepath=scripblock:
        # "/" = {
        #     param(
        #         $Request,
        #         $Response
        #     )
 
        #     $output = Get-Content -Path .\index.html -Encoding UTF8 -Raw;
        #     $Response.ContentType = "text/html";
        #     $Response.ContentLength64 = $output.Length;
        #     [System.IO.StreamWriter]$sw = [System.IO.StreamWriter]::new($Response.OutputStream);
        #     $sw.Write($output);
        #     $sw.Close();
        # };

        # These 3 built-in endpoints are for supporting the pipeline cmdlets like Out-MiniServerTable
        "/setpspipeline" = {
            param(
                $Request,
                $Response,
                [Hashtable]$pipelinedata
            )

            $input = @{};
            $output = '{"status": "ok"}';
        
            [System.IO.StreamReader]$sr = [System.IO.StreamReader]::new($Request.InputStream);
            $input = $sr.ReadToEnd() | ConvertFrom-Json;
            $sr.Close();
        
            $pipelinedata.data = $input;

            $output = $pipelinedata.data | ConvertTo-Json;

            $Response.StatusCode = 200;
            $Response.ContentLength64 = $output.Length;
            $Response.ContentType = "application/Json";
        
            # Write JSON data to outputstream
            [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
            $sw.Write($output);
            $sw.Close();
        };
        "/getpspipeline" = {
            param(
                $Request,
                $Response,
                [Hashtable]$pipelinedata
            )

            ## TODO: accept parameters for things like sort, filter, etc.

            # $input = @{};
            $output = "[]";
            if($pipelinedata.data.Count -lt 2) {
                $output = "[" +($pipelinedata.data | ConvertTo-Json) + "]";
            }
            else{
                $output = $pipelinedata.data | ConvertTo-Json;
            }

            # Keep pipelinedata - we'll need another endpoint to clear it on demand
            # $pipelinedata.Remove("data");
        
            # [System.IO.StreamReader]$sr = [System.IO.StreamReader]::new($Request.InputStream);
            # $input = $sr.ReadToEnd() | ConvertFrom-Json;
            # $sr.Close();
        
            # $global:pipelinedata = $input;

            $Response.StatusCode = 200;
            $Response.ContentLength64 = $output.Length;
            $Response.ContentType = "application/Json";
        
            # Write JSON data to outputstream
            [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
            $sw.Write($output);
            $sw.Close();
        };
        "/pipelinetable" = {
            param(
                $Request,
                $Response
            )
    
            $output = New-MiniServerWebTable -Url "http://localhost:9797/getpspipeline";
        
            $Response.StatusCode = 200;
            $Response.ContentLength64 = $output.Length;
            $Response.ContentType = "text/html";
        
            # Write index content to outputstream
            [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
            $sw.Write($output);
            $sw.Close();
        }
    })

    $jobCommands = @{
        "run"=$false
    };

    function Start-MiniServer {
        param(
            [Parameter(Position=0,mandatory=$true)]
            [string]$Hostname,
            [Parameter(Position=1,mandatory=$true)]
            [string]$Port
        )
        # Install-Module ThreadJob -Repository PSGallery | Out-Null
        Import-Module ThreadJob | Out-Null;

        $jobCommands.hostname = $Hostname;
        $jobCommands.port = $Port;
        $jobCommands.run = $true;

        $_currenthostname = $Hostname;
        $_currentport = $Port;

        # Start the main httplistener and start up 4 listening contexts
        $serverJob = Start-ThreadJob -ScriptBlock {
            param(
                $routes,
                $jobCommands
            )

            $hostname = $jobCommands.hostname;
            $port = $jobCommands.port;
            $baseURL = "http://$hostname`:$port/"

            [System.Net.HttpListener]$httpListener = $null;
            

            try {
                $httpListener = [System.Net.HttpListener]::new();
                $httpListener.Prefixes.Add($baseURL);
                $httpListener.Start();
            }
            catch {
                Write-Output "Could not start server.";
                Write-Output $_;
                Exit;
            }

            # Temp variable for pipeline data
            $pipelinedata = [Hashtable]::Synchronized(@{});

            $MAXJOBS = 10;
            $jobcount = 0;

            while($jobCommands.run) {
                while($jobcount -lt $MAXJOBS) {
                    Start-ThreadJob -ScriptBlock {
                        param(
                            [System.Net.HttpListener]$httpListener,
                            [Hashtable]$routes,
                            [Hashtable]$pipelinedata
                        )
                        # Not sure if they are any benefits to async here
                        # since we're waiting. May switch back to synched GetContent()
                        $task = $httpListener.GetContextAsync();
                        $task.AsyncWaitHandle.WaitOne();
                        $context = $task.GetAwaiter().GetResult();

                        # Get path 
                        $requestedRoute = $($context.Request.Url.AbsolutePath);
                        # Get query
                        $requestedQuery = $($context.Request.Url.Query);

                        ## TODO: create a better default output? For now just reply with the requested path
                        $output = $requestedRoute;

                        ## TODO: Create a logging strategy
                        #Add-Content -Path ".\log.txt" -Value "Trying $($output)"
                        
                        foreach($key in $routes.Keys) {
                            ## TODO: Create a logging strategy
                            #Add-Content -Path ".\log.txt" -Value $key

                            # If route is found in our route hash, invoke it's scriptblock.
                            if($key -eq $requestedRoute) {
                                if($key -eq "/setpspipeline" -or $key -eq "/getpspipeline") {
                                    $routes[$key].Invoke( $context.Request, $context.Response, $pipelinedata );
                                }
                                else{
                                    $routes[$key].Invoke( $context.Request, $context.Response );
                                }
                            }
                        }
                        $context.Response.Close();

                    } -ArgumentList $httpListener, $routes, $pipelinedata | Out-Null
                    $jobcount++;
                }

                Get-Job | Where-Object State -eq "Completed" | ForEach-Object {
                    $_ | Remove-Job
                    if($jobcount -gt 0) {
                        $jobcount--;
                    }
                }
            }
            
            $httpListener.Close();
            Write-Output "Web server Closed";
        } -Name WebServerJob -ArgumentList $routes, $jobCommands | Out-Null

        Write-Host "";
        Write-Host "====================================================================================";
        Write-Host "Server started and listening on http://$($Hostname)`:$($Port)/";
        Write-Host "";
        Write-Host "To stop server, close window or run cmdlet:";
        Write-Host "     Stop-MiniServer";
        Write-Host "";
        Write-Host "To add a route, run cmdlet:";
        Write-Host "     Set-MiniServerRoute -RoutePath `"<routpath>`" -ScriptBlock `{ <scriptblock`> }";
        Write-Host "";
        Write-Host "To Start server, run cmdlet:";
        Write-Host "     Start-MiniServer -Hostname `"<hostname>`" -port `"<port>`""
        Write-Host "====================================================================================";
        Write-Host "";
    }

    function Stop-MiniServer {
        $jobCommands.run = $false;
        Start-Sleep 3;
        $job = Get-Job | Where-Object Name -eq "WebServerJob";
        $result = Receive-Job -Job $job;
        $result;
        Get-Job | Remove-Job | Out-Null;
    }

    function Set-MiniServerRoute {
        param(
            [Parameter(Position=0,mandatory=$true)]
            $RoutePath,
            [Parameter(Position=1,mandatory=$true)]
            $ScriptBlock
        )

        $routes[$RoutePath] = $ScriptBlock;
    }

    function Get-MiniServerRoutes {
        Return $routes;
    }

    # This function is not ready for primetime but works in simple use cases
    function New-MiniServerWebTable {
        param(
            [Parameter(Position=0,mandatory=$true)]
            [string]$Url
        )

        $htmlstring = @"
<html>
<head>
    <title>Table</title>
<script>

function getdata() {
    let tablerows = document.getElementById("rows");
    let tableheader = document.getElementById("header");
    tablerows.innerHTML = "";
    tableheader.innerHTML = "";

    fetch("{URL}",{
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        }
    }).then((response) => {
        response.json().then((data) => {
            console.log(data);
            let tablerows = document.getElementById("rows");
            let tableheader = document.getElementById("header");
            for(let dr in data) {
                let row = document.createElement("tr");
                let datarow = data[dr];
                for(let cell in datarow) {
                    let cellElement = document.createElement("td");
                    cellElement.innerHTML = datarow[cell];
                    row.appendChild(cellElement);
                    tablerows.appendChild(row);
                }
                if(dr == 0) {
                    let headrow = document.createElement("tr");
                    for(let cell in datarow) {
                        let headElement = document.createElement("th");
                        headElement.innerHTML = cell;
                        headrow.appendChild(headElement);
                        tableheader.appendChild(headrow);
                    }
                }
            }
        });
    });
}
addEventListener("DOMContentLoaded", (event) => {
    document.getElementById("getdata").addEventListener("click", (event) => {
        getdata();
    })
    getdata();
});
</script>
</head>
<body>
    <button id="getdata">Get Data</button>
    <table border=`"1`">
        <thead id="header" style="font-weight: bold;">
        <tbody id="rows">
        </tbody>
        <tbody>
    </table>
</body>
</html>
"@;

        ## TODO: Figure out a header strategy for pipelinetable
        # $headerString = "";
        # $Headers = $Headers -split ","
        # if($Headers.Length -gt 0) {
        #     foreach($header in $Headers) {
        #         $headerString += "<th>$header</th>";
        #     }
        # }

        # $htmlstring = $htmlstring -replace "{HEADER}", $headerString
        $htmlstring = $htmlstring -replace "{URL}", $Url

        Write-Output $htmlstring;
    }

    # Generates html for api request with single query
    function New-MiniServerHtmlSingleQuery {
        param(
            [Parameter(Position=0,mandatory=$true)]
            [string[]]$Headers,
            [Parameter(Position=1,mandatory=$true)]
            [string]$Url,
            [Parameter(Position=2,mandatory=$true)]
            [string]$Queryparameter
        )

        $htmlstring = @"
<html>
<head>
    <title>Table</title>
<script>
addEventListener("DOMContentLoaded", (event) => {
    document.getElementById("getdata").addEventListener("click", (event) => {
        let query = document.getElementById("query").value;
        let tablerows = document.getElementById("rows");
        let tableheader = document.getElementById("header");

        tablerows.innerHTML = "";
        tableheader.innerHTML = "";

        fetch("{URL}",{
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({ {Queryparameter} : query })
        }).then((response) => {
            response.json().then((data) => {
                console.log(data);
                let tablerows = document.getElementById("rows");
                let tableheader = document.getElementById("header");
                // use first row as header
                for(let dr in data) {
                    let row = document.createElement("tr");
                    let datarow = data[dr];
                    for(let cell in datarow) {
                        let cellElement = document.createElement("td");
                        cellElement.innerHTML = datarow[cell];
                        row.appendChild(cellElement);
                        tablerows.appendChild(row);
                    }
                    if(dr == 0) {
                        let headrow = document.createElement("tr");
                        for(let cell in datarow) {
                            let headElement = document.createElement("th");
                            headElement.innerHTML = cell;
                            headrow.appendChild(headElement);
                            tableheader.appendChild(headrow);
                        }
                    }
                }
            })
        }) 
    })
});
</script>
</head>
<body>
    <input type="text" id="query" name="query" value="">
    <button id="getdata">Get Data</button>
    <table border=`"1`">
        <thead id="header" style="font-weight: bold;">
        {HEADER}
        </thead>
        <tbody id="rows">
        </tbody>
        <tbody>
    </table>
</body>
</html>
"@;

        $headerString = "";
        $Headers = $Headers -split ","
        if($Headers.Length -gt 0) {
            foreach($header in $Headers) {
                $headerString += "<th>$header</th>";
            }
        }

        $htmlstring = $htmlstring -replace "{HEADER}", $headerString
        $htmlstring = $htmlstring -replace "{URL}", $Url
        $htmlstring = $htmlstring -replace "{Queryparameter}", $Queryparameter

        Write-Output $htmlstring;
    }

    function Out-MiniServerTable {
        [CmdletBinding()]
        param(
            [Parameter(Position=0,mandatory=$true,ValueFromPipeline=$true)]
            [Array]$InputData
        )
        begin {
            $blockdata = [System.Collections.ArrayList]::new();
        }
        process {
            $datatype = $InputData[0].GetType()
            if($datatype -eq [System.Collections.Hashtable]) {
                # has keys
                # maybe later I'll create metadata for headers
                # for now just create headers in javascript
                # using the property names of the first row.
            }
            $blockdata.AddRange($InputData) | Out-Null;
        }
        end {
            # $blockdata | ConvertTo-Json | Write-Output
            $json="";
            if($blockdata.Count -lt 2) {
                $json = "[" + ($blockdata | ConvertTo-Json) + "]";
            }
            else {
                $json = $blockdata | ConvertTo-Json;
            }
            write-Output $json; # allows us to pipe the resulting json to another command
            $setapiurl = "http://$($jobCommands.hostname)`:$($jobCommands.port)/setpspipeline";
            $pipelinetableurl = "http://$($jobCommands.hostname)`:$($jobCommands.port)/pipelinetable";
            Invoke-WebRequest -Method "POST" -Uri "$setapiurl" -Body $json -ContentType "application/json" | Out-Null;
            Start-Process $pipelinetableurl # should open in default browser
        }
    }
}