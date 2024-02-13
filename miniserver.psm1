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
    # Hold our routes, a default route for index has been added for example
    $routes = [Hashtable]::Synchronized( @{
        # Example hash value is routepath=scripblock:
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
        # }
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

            $MAXJOBS = 10;
            $jobcount = 0;

            while($jobCommands.run) {
                while($jobcount -lt $MAXJOBS) {
                    Start-ThreadJob -ScriptBlock {
                        param(
                            [System.Net.HttpListener]$httpListener,
                            [hashtable]$routes
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
                                $routes[$key].Invoke( $context.Request, $context.Response );
                            }
                        }
                        $context.Response.Close();

                    } -ArgumentList $httpListener, $routes | Out-Null
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

    # DO NOT USE YET - STILL WORKING ON THIS
    function New-MiniServerHtml {
        param(
            [string[]]$Headers,
            [string]$Url
        )

        $htmlstring = @"
<html>
<head>
    <title>Table</title>
<script>
addEventListener("DOMContentLoaded", (event) => {
    document.getElementById("getdata").addEventListener("click", (event) => {
        fetch("{URL}").then((response) => {
            response.json().then((data) => {
                console.log(data);
                let tablerows = document.getElementById("rows");
                for(let dr in data) {
                    let row = document.createElement("tr");
                    let datarow = data[dr];
                    for(let cell in datarow) {
                        let cellElement = document.createElement("td");
                        cellElement.innerHTML = datarow[cell];
                        row.appendChild(cellElement);
                    }
                    tablerows.appendChild(row);
                }
            })
        })
    })
});
</script>
</head>
<body>
    <button id="getdata">Get Data</button>
    <table border=`"1`">
        <thead>
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

        Write-Output $htmlstring;
    }
}