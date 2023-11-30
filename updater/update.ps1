#requires -PSEdition Core

$RCS_PWD = $env:RCS_PASSWORD
$RCS_PORT = $env:RCS_PORT

$LOL_PWD = $env:LCU_PASSWORD
$LOL_PORT = $env:LCU_PORT
$LOL_PATCHLINE = $env:LCU_PATCHLINE

$PENGU_DIR = $env:PENGU_DIR

$RCS_DIR = 'rcs'
$LOL_DIR = 'lol/' + $LOL_PATCHLINE

function Invoke-RiotRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$port,
        [Parameter(Mandatory=$true)]  [String]$password,
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [bool]$Mandatory = $False,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    $pass = ConvertTo-SecureString $password -AsPlainText -Force
    $cred = New-Object -TypeName PSCredential -ArgumentList 'riot', $pass

    Try {
        $result = Invoke-RestMethod "https://127.0.0.1:$port$path" `
            -SkipCertificateCheck `
            -Method $method `
            -Authentication 'Basic' `
            -Credential $cred `
            -ContentType 'application/json' `
            -Body $($body | ConvertTo-Json)
    } Catch {
        # Better error info
        $error_msg = $_
        $msg = "Failed to $method '$path'! Error: $_"
        if ($Mandatory -ne $True) {
            Write-Output "::warning::$msg"
        } else {
            throw $msg
        }
    }

    if (![string]::IsNullOrEmpty($OutFile)) {
        # We need this dirty code to properly format json when outputting

        if ($result -is [string] ||
            $result -is [number]) {
            Out-File $OutFile $result
        }
        else
        {
            ConvertTo-Json $result -Depth 100 | Out-File $OutFile
        }

        return $null
    }
    
    return $result
}

function Invoke-RCSRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [bool]$Mandatory = $False,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest $RCS_PORT $RCS_PWD $path $method $body $Mandatory $OutFile
}

function Invoke-LOLRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [bool]$Mandatory = $False,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest $LOL_PORT $LOL_PWD $path $method $body $Mandatory $OutFile
}

function Create-Folder {
    Param (
        [Parameter(Mandatory=$true)] [String]$name
    )

    Return New-Item -Name $name -ItemType Directory -Force
}

function Clean-Folder {
	Param (
		[Parameter(Mandatory=$true)] [String]$name
	)

	if (Test-Path($name)) {
		return Get-ChildItem -Path $name -Include * -File -Recurse | foreach { $_.Delete()}
	} else {
		return Create-Folder $name
	}
}

function Delete-File {
	Param (
		[Parameter(Mandatory=$true)] [String]$name
	)

    if (Test-Path $name) {
        Remove-Item $name
    }
}

Create-Folder 'rcs'
Create-Folder 'lol'
Create-Folder $LOL_DIR

Write-Host 'Dumping RCS schemas...'
Invoke-RCSRequest '/swagger/v2/swagger.json' -Mandatory $True -OutFile $RCS_DIR/swagger.json
Invoke-RCSRequest '/swagger/v3/openapi.json' -Mandatory $True -OutFile $RCS_DIR/openapi.json

# Write-Host 'Dumping RCS data...'
# Invoke-RCSRequest '/product-metadata/v2/products' -OutFile $RCS_DIR/products.json
Delete-File $RCS_DIR/products.json

Write-Host 'Dumping LCU schemas...'
Invoke-LOLRequest '/swagger/v2/swagger.json' -Mandatory $True -OutFile $LOL_DIR/swagger.json
Invoke-LOLRequest '/swagger/v3/openapi.json' -Mandatory $True -OutFile $LOL_DIR/openapi.json

Write-Host 'Dumping LCU data...'
Invoke-LOLRequest '/lol-maps/v2/maps' -OutFile $LOL_DIR/maps.json
Invoke-LOLRequest '/lol-game-queues/v1/queues' -OutFile $LOL_DIR/queues.json
Invoke-LOLRequest '/lol-store/v1/catalog' -OutFile $LOL_DIR/catalog.json

Write-Host 'Dumping LOL version...'
$versionObject = @{}
$versionObject.Add('client', (Invoke-LOLRequest '/system/v1/builds' -Mandatory $True).version)
$versionObject.Add('game', (Invoke-LOLRequest '/lol-patch/v1/game-version' -Mandatory $True).TrimStart('"').TrimEnd('"'))
ConvertTo-Json $versionObject | Out-File $LOL_DIR/version.txt

Write-Host 'Copying pengu plugin...'
New-Item -Path "$PENGU_DIR/plugins/updater-pengu" -ItemType Directory -Force
Copy-Item ..\watchdog\updater-pengu\dist\index.js "$PENGU_DIR/plugins/updater-pengu/index.js"

$attempts = 5
while (-not (Test-Path "$PENGU_DIR/plugins/updater-pengu/log.txt") -And $attempts -Gt 0) {
	Write-Host "Restarting LOL UX... Attempts left: $attempts"
	Invoke-LOLRequest '/riotclient/kill-and-restart-ux' 'POST'
	
	Start-Sleep 10
	$attempts--

	if ($attempts -Eq 0) {
		Write-Output '::error Failed to install pengu plugin!'
		Exit
	}
}

# Wait until pengu dumper is done...
Write-Host 'Dumping plugins...'
$attempts = 100
while (-not (Test-Path "$PENGU_DIR/plugins/updater-pengu/status") -And $attempts -Gt 0) {
	Start-Sleep 1

	$attempts--
	Write-Host "Attempts left: $attempts"

	if ($attempts -Eq 0) {
		Write-Output '::error Failed to dump plugins!'
		Write-Host 'Log output:'
		Get-Content "$PENGU_DIR/plugins/updater-pengu/log.txt"
		Exit
	}
}

$plugins_dir = "$LOL_DIR/plugins/"

Write-Host 'Copying plugin output to content folder...'
Clean-Folder $plugins_dir
Copy-Item -Force -Recurse -Verbose -Path "$PENGU_DIR/plugins/updater-pengu/output/*" -Destination $plugins_dir

Write-Host 'Installing js beautifier...'
npm i -g js-beautify

Write-Host 'Beautifying plugins...'
Push-Location $plugins_dir
js-beautify -f * -r --type js
Pop-Location

Write-Host 'Success!'
