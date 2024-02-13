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
        "/" = {
            param(
                $Request,
                $Response
            )

            $output = Get-Content -Path .\index.html -Encoding UTF8 -Raw;
            $Response.ContentType = "text/html";
            $Response.ContentLength64 = $output.Length;
            [System.IO.StreamWriter]$sw = [System.IO.StreamWriter]::new($Response.OutputStream);
            $sw.Write($output);
            $sw.Close();
        }
    })

    $jobCommands = @{
        "run"=$false
    };

    function Start-MiniServer {
        # Install-Module ThreadJob -Repository PSGallery | Out-Null
        Import-Module ThreadJob | Out-Null

        $jobCommands.run = $true;

        # Start the main httplistener and start up 4 listening contexts
        Start-ThreadJob -ScriptBlock {
            param(
                $routes,
                $jobCommands
                )

            $httpListener = [System.Net.HttpListener]::new();
            $httpListener.Prefixes.Add("http://localhost:9797/");
            $httpListener.Start();

            $MAXJOBS = 10;
            $jobcount = 0;

            while($jobCommands.run) {
                while($jobcount -lt $MAXJOBS) {
                    Start-ThreadJob -ScriptBlock {
                        param(
                            [System.Net.HttpListener]$httpListener,
                            [hashtable]$routes
                        )
                        $task = $httpListener.GetContextAsync();
                        $task.AsyncWaitHandle.WaitOne();
                        $context = $task.GetAwaiter().GetResult();

                        $requestedRoute = $($context.Request.Url.AbsolutePath)

                        $output = $requestedRoute;

                        Add-Content -Path ".\log.txt" -Value "Trying $($output)"
                        foreach($key in $routes.Keys) {
                            Add-Content -Path ".\log.txt" -Value $key
                            if($key -eq $requestedRoute) {
                                $routes[$key].Invoke( $context.Request, $context.Response )
                            }
                        }
                        $context.Response.Close();

                    } -ArgumentList $httpListener, $routes
                    $jobcount++;
                }

                Get-Job | Where State -eq "Completed" | foreach {
                    $_ | Remove-Job
                    if($jobcount -gt 0) {
                        $jobcount--;
                    }
                }
                
            }
            $httpListener.Close();
            Write-Output "Web server Closed";
        } -Name WebServerJob -ArgumentList $routes, $jobCommands
    }

    function Stop-MiniServer {
        $jobCommands.run = $false;
        Start-Sleep 3
        Get-Job | Remove-Job
    }

    function Set-MiniServerRoutes {
        param(
            $RoutePath,
            $ScriptBlock
        )

        $routes[$RoutePath] = $ScriptBlock;
    }

    function Get-MiniServerRoutes {
        Return $routes
    }
}