# Powershell Miniserver
Cmdlets to control a .Net HttpListener web server

## How TO:

[Check out my blog for more information on how to use this module.](https://idevudev.blogspot.com/2024/02/super-simple-powershell-webserver.html)

### Starting server

Start-MiniServer -Hostname "\<hostname\>" -port "\<port\>"

### Stopping server

Stop-MiniServer

### Adding routes

Set-MiniServerRoute -RoutePath "\<routpath\>" -ScriptBlock { \<scriptblock\> }";

### Pipeline support

Though still a work in progress, you can pipe simple data directly to an HTML table using the `Out-MiniServerTable` cmdlet.
#### For example, this will open a web browser to http://localhost:9797/pipelinetable and display the piped data in an HTML table.

```
# Import the module and start the mini server on localhost and port
Import-Module .\miniserver.psm1
Start-MiniServer -Hostname "localhost" -Port "9797";

# Connect to the graph for this example since we're using Get-MgUser
Connect-MgGraph

# Pipe the Get-MgUser results to Out-MiniServerTable
(Get-MgUser -Filter "startsWith(DisplayName, 'James')" | Select-Object -Property DisplayName, UserPrincipalName, Id) | Out-MiniServerTable
```
