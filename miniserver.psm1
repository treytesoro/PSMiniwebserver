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
    # $_currenthostname = "";
    # $_currentport = "";
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
        };
        "/graphbrowser" = {
            param(
                $Request,
                $Response,
                [Hashtable]$pipelinedata
            )
    
            $output = New-MiniServerGraphViewer -IntialOData $pipelinedata;
        
            $Response.StatusCode = 200;
            $Response.ContentLength64 = $output.Length;
            $Response.ContentType = "text/html";
        
            # Write index content to outputstream
            [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
            $sw.Write($output);
            $sw.Close();
        };
        "/graphinvoke" = {
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
        
            # $graphurl = [URI]::EscapeUriString($graphurl);
            $output = (Invoke-MgGraphRequest -Method GET -Uri $graphurl | ConvertTo-Json -Depth 10);
            
            $Response.StatusCode = 200;
            $Response.ContentLength64 = $output.Length;
            $Response.ContentType = "application/Json";
        
            # Write JSON data to outputstream
            [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($Response.OutputStream);
            $sw.Write($output);
            $sw.Close();
        }
    });

    $staticRoutes = [Hashtable]::Synchronized( @{

    } );

    $jobCommands = @{
        "run"=$false # controls runstate of the creation of context getter threadjobs
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

        # $_currenthostname = $Hostname;
        # $_currentport = $Port;

        # Start the main httplistener and start up 4 listening contexts
        $serverJob = Start-ThreadJob -ScriptBlock {
            param(
                $routes,
                $staticRoutes,
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
                            [Hashtable]$staticRoutes,
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
                        # Add-Content -Path ".\log.txt" -Value "Trying $($output)"
                        
                        $isHandled = false;

                        foreach($key in $routes.Keys) {
                            ## TODO: Create a logging strategy
                            #Add-Content -Path ".\log.txt" -Value $key

                            # If route is found in our route hash, invoke it's scriptblock.
                            if($key -eq $requestedRoute) {
                                if($key -eq "/setpspipeline" -or $key -eq "/getpspipeline" -or $key -eq "/graphbrowser") {
                                    $routes[$key].Invoke( $context.Request, $context.Response, $pipelinedata );
                                }
                                else{
                                    $routes[$key].Invoke( $context.Request, $context.Response );
                                }
                                $isHandled = true;
                            }
                        }

                        # not handled by scriptblock so check for static files
                        if(!$isHandled) {       
                            Add-Content -Path ".\log.txt" -Value "NOT HANDLED";
                            foreach($key in $staticRoutes.Keys) {
                                # if($key -eq $requestedRoute) {
                                    $windowpath = $requestedRoute -replace "/", "\";
                                    if($windowpath.Length -gt 1) {
                                        Add-Content -Path ".\log.txt" -Value "Getting $($staticRoutes[$key] + $windowpath)";
                                        if(Test-Path -Path $($staticRoutes[$key] + $windowpath)) {
                                            $mimetype = "text/plain";
                                            
                                            try {
                                                $ext = "."+($windowpath -split "\.")[-1];
                                                Add-Content -Path ".\static.log" -Value "EXTENSION $($ext)";
                                                $registeredfiletype = get-item HKLM:\SOFTWARE\Classes\$ext;
                                                $mimetype = $registeredfiletype.GetValue("Content Type");
                                            }
                                            catch {
                                                <#Do this if a terminating exception happens#>
                                            }

                                            Add-Content -Path ".\static.log" -Value $mimetype;
                                            # $output = Get-Content -Path $($staticRoutes[$key] + $windowpath) -Encoding Byte -Raw;

                                            $output = [System.IO.FileStream]::new($($staticRoutes[$key] + $windowpath) , [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read);

                                            $context.Response.StatusCode = 200;
                                            $context.Response.ContentLength64 = $output.Length;
                                            $context.Response.ContentType = $mimetype;
                                            $output.CopyTo($context.Response.OutputStream);
                                            $output.Close();

                                            # Write index content to outputstream
                                            # [System.IO.StreamWriter] $sw = [System.IO.StreamWriter]::new($context.Response.OutputStream);
                                            # $sw.Write($output);
                                            # $sw.Close();
                                            # $context.Response.OutputStream.Close();
                                        }
                                    }
                                # }
                            }
                        }

                        $context.Response.Close();

                    } -ArgumentList $httpListener, $routes, $staticRoutes, $pipelinedata | Out-Null
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
        } -Name WebServerJob -ArgumentList $routes, $staticRoutes, $jobCommands | Out-Null

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

    function Set-MiniServerStaticRoutes {
        param(
            [Parameter(Position=0,mandatory=$true)]
            $StaticRoute,
            [Parameter(Position=1,mandatory=$true)]
            $LocalPath
        )

        $staticroutes[$StaticRoute] = $LocalPath;
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

    function New-MiniServerGraphViewer {
        param(
            [Parameter(Position=0,mandatory=$true)]
            [Hashtable]$IntialOData
        )

        $htmlstring = @"
<html>
<head>
    <title>Table</title>
<script>

var nexturl = "{URL}";
var headerorder = [{HEADERORDER}];
var tabledata = [{TABLEDATA}];

function getdata() {
    let tablerows = document.getElementById("rows");
    let tableheader = document.getElementById("header");
    //tablerows.innerHTML = "";
    //tableheader.innerHTML = "";

    fetch("/graphinvoke",{
        method: "POST",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({ graphurl: nexturl })
    }).then((response) => {
        response.json().then((odatas) => {
            console.log(odatas);
            let tablerows = document.getElementById("rows");
            let tableheader = document.getElementById("header");
            let data = odatas.value;
            tabledata.push(...data);

            nexturl = "";
            nexturl = odatas["@odata.nextLink"];

            renderData();

            //if(nexturl == "" || nexturl == undefined) {
            //    document.getElementById("getdata").style.display = "none";
            //}

            //for(let dr in data) {
            //    let row = document.createElement("tr");
            //    let datarow = data[dr];

            //    for(let i in headerorder) {
            //        let cell = datarow[headerorder[i]];
            //        let cellElement = document.createElement("td");
            //        cellElement.innerHTML = cell; //datarow[cell];
            //        row.appendChild(cellElement);
            //        tablerows.appendChild(row);
            //    }
            //}
        });
    });
}

function renderData() {
    // TODO: Do not rebuild tablerows on every request.
    // TODO: Instead, add/remove rows as necessary.
    // TODO: This will require some type of key to identify a row.
    let tablerows = document.getElementById("rows");
    tablerows.innerHTML = "";

    if(nexturl == "" || nexturl == undefined) {
        //document.getElementById("getdata").style.display = "none";
        document.getElementById("getdata").setAttribute("disabled", "true");
    }

    let data = tabledata;
    for(let dr in data) {
        let row = document.createElement("tr");
        let datarow = data[dr];

        for(let i in headerorder) {
            let cell = datarow[headerorder[i]];
            let cellElement = document.createElement("td");
            let spanElement = document.createElement("span");
            spanElement.classList.add("celltext");

            spanElement.innerHTML = cell; //datarow[cell];
            cellElement.appendChild(spanElement);
            row.appendChild(cellElement);
            tablerows.appendChild(row);
        }
    }
}

function setupTable(table) {
    let tableheader = table.getElementsByTagName("thead")[0];
    let tableheadercells = tableheader.getElementsByTagName("th");
    let tableleft = table.offsetLeft;

    for(let th of tableheadercells) {
        let handle = th.getElementsByClassName("handle")[0];
        //let thleft = th.offsetLeft;
        let thwidth = th.offsetWidth;
        th.style.width = thwidth + "px";
        thwidth = parseInt(th.style.width);
        // let thpaddingleft = th.style.paddingLeft;
        // let thpaddingright = th.style.paddingRight;
        // let handlewidth = handle.offsetWidth;

        handle.style.left = thwidth - 2 + "px";
        handle.style.height = th.offsetHeight + "px";

        handle.addEventListener("mousedown", (event) => {
            table.classList.add("unselectable");
            let currentHandle = event.target;
            let xdown = event.clientX;
            let func = resizeColumn(currentHandle, xdown, event);
            document.addEventListener("mousemove", func);

            function reset(event) {
                document.removeEventListener("mousemove", func);
                document.removeEventListener("mouseup", reset);
                table.classList.remove("unselectable");
            }
            document.addEventListener("mouseup", reset)
        })
    }
    table.style.width = "0";
}

// Function factory for resizing a column.
// Stores initial thwidth within this closure, then returns
// a function to handle the resize.
function resizeColumn(currentHandle, xdown, event) {
    let thwidth = parseInt(currentHandle.parentElement.style.width);
    return (event) => {
        let diff = event.clientX - xdown;

        let parentth = currentHandle.parentElement;
        parentth.style.width = thwidth + diff + "px";
        currentHandle.style.left = thwidth + diff - 2 + "px";
    }
}

function filterTable() {
    let filterValue = document.getElementById("filter").value;
    let trNodes = document.getElementById('rows').childNodes;

    let rgx = new RegExp(".*?" + filterValue + ".*", "gi");
    for(let tr of trNodes) {
        // Look at all inner text of a row to match against the filter.
        if(!(tr.innerText.match(rgx))) {
            tr.style.display = "none";
        }
        else {
            tr.style.display = "table-row";
        }
    }
}

addEventListener("DOMContentLoaded", (event) => {
    // Setup getdata button event
    document.getElementById("getdata").addEventListener("click", (event) => {
        getdata();
    });

    // Setup tables to be resizable
    var tables = document.getElementsByClassName("graphtable");
    for(let tbl of tables) {
        setupTable(tbl);
    }

    // Perform initial render
    renderData();

    // Setup filtering
    var filtertimer = null;
    document.getElementById("filter").addEventListener("keyup", (event) => {
        if(filtertimer != null) {
            clearTimeout(filtertimer);
        }
        filtertimer = setTimeout(filterTable, 1000);
    })
});
</script>

<style>
.graphtable {
    border-collapse: collapse;
    border: solid 0px #777;
    border-radius: 20px;
    table-layout: fixed;
    vertical-align: middle;
    font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
}
.unselectable {
    user-select: none;
}
.graphtable th {
    border: solid 0px green;
    position: relative;
    text-align: center;
}
.graphtable th span.headertext {
    background-color: #dddddd;
}
.graphtable th span.headertext,
.graphtable td span.celltext {
    display: block;
    border: solid 1px #999999;
    padding: 4px;
    border-radius: 6px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
}
button {
    border: solid 2px #444444;
    background-color: white;
    padding: 6px;
    margin: 4px;
    border-radius: 30px;
}
button:hover {
    background-color: lightgray;
    box-shadow: 0px 0px 10px 0px #000000;
}
.handle {
    display: inline-block;
    position: absolute;
    width: 10px;
    height: 10px;
    background-color: transparent;
    z-index: 1;
    cursor: col-resize;
}

#filter {
    display: inline-block;
    border: solid 2px #555555;
    padding: 6px;
    border-radius: 10px;
}
</style>
</head>
<body>
    <div style="max-width: 800px; margin: 10px;">
        <div style="float: left;"><button id="getdata">Get More Data</button></div>
        <div style="float: right;"><input type="text" id="filter" placeholder="Filter..."></div>
        <div style="clear: both;"></div>
    </div>
    <table class="graphtable">
        <thead id="header" style="font-weight: bold;">
        {HEADER}
        <tbody id="rows">
        {TROWS}
        </tbody>
    </table>
</body>
</html>
"@;

        $thead = "";
        $trows = "";
        $headerorder = "";
        $tabledata = "";

        $odata = $IntialOData.data[0]
        # property names or headers
        $k = $odata.value[0];
        $props =  ($k | Get-Member -MemberType NoteProperty);
        foreach($prop in $props) {
            # Add-Content ".\outputdata.txt" -Value $prop.Name;
            $thead += "<th><span class='handle'></span><span class='headertext'>$($prop.Name)</span></th>";
            $headerorder += "'" + $prop.Name + "',";
        }

        # iterate values
        foreach($val in $odata.value) {
            # Add-Content ".\outputdata.txt" -Value (ConvertTo-Json $val);
            $props =  ($k | Get-Member -MemberType NoteProperty);
            $trows += "<tr>";
            $tabledata += "{";
            foreach($prop in $props) {
                # Add-Content ".\outputdata.txt" -Value $val."$($prop.Name)";
                $trows += "<td><span class='celltext'>$($val."$($prop.Name)")</span></td>";
                $tabledata += "'$($prop.Name)': '$($val."$($prop.Name)")', ";
            }
            $tabledata =$tabledata.TrimEnd(", ");
            $tabledata += "},";
            $trows += "</tr>";
        }
        $tabledata = $tabledata.TrimEnd(",");

        $htmlstring = $htmlstring -replace "{URL}", ($odata."@odata.nextLink")
        $htmlstring = $htmlstring -replace "{HEADER}", ($thead)
        $htmlstring = $htmlstring -replace "{TROWS}", ($trows)
        $htmlstring = $htmlstring -replace "{HEADERORDER}", ($headerorder)
        $htmlstring = $htmlstring -replace "{TABLEDATA}", ($tabledata)
        # Add-Content -Path ".\outputdata.txt" -Value (ConvertTo-Json $odata.value[0]);
        # Add-Content -Path ".\outputdata.txt" -Value ($odata."@odata.nextLink");

        Write-Output $htmlstring;
    }

    <#
    .SYNOPSIS
    #
    
    .DESCRIPTION
    Accepts array of hashtables and displays in web browser table
    
    .PARAMETER InputData
    Array of Hashtable values or objects
    
    .EXAMPLE
    #
    
    .NOTES
    General notes
    #>
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

    <#
    .SYNOPSIS
    #
    
    .DESCRIPTION
    Accepts results of Invoke-MgWebRequest on input pipeline and displays in web browser table
    
    .PARAMETER InputData
    Results of Invoke-MgWebRequest
    
    .EXAMPLE
    Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices" | Out-MiniServerMsGraph
    
    .NOTES
    General notes
    #>
    function Out-MiniServerMsGraph {
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
            $pipelinetableurl = "http://$($jobCommands.hostname)`:$($jobCommands.port)/graphbrowser";
            Invoke-WebRequest -Method "POST" -Uri "$setapiurl" -Body $json -ContentType "application/json" | Out-Null;
            Start-Process $pipelinetableurl # should open in default browser
        }
    }
}