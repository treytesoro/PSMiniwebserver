# Powershell Miniserver
Cmdlets to control a .Net HttpListener web server

## How TO:

### Starting server

Start-MiniServer -Hostname "\<hostname\>" -port "\<port\>"

### Stopping server

Stop-MiniServer

### Adding routes

Set-MiniServerRoute -RoutePath "\<routpath\>" -ScriptBlock { \<scriptblock\> }";