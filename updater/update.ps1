#requires -PSEdition Core

$RCS_PWD = $env:RCS_PASSWORD
$RCS_PORT = $env:RCS_PORT

$LOL_PWD = $env:LCU_PASSWORD
$LOL_PORT = $env:LCU_PORT

$PENGU_DIR = $env:PENGU_DIR
Write-Host "Pengu directory: $PENGU_DIR"

function Invoke-RiotRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$port,
        [Parameter(Mandatory=$true)]  [String]$password,
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [Int]$attempts = 100,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    While ($True) {
        Try {
            $pass = ConvertTo-SecureString $password -AsPlainText -Force
            $cred = New-Object -TypeName PSCredential -ArgumentList 'riot', $pass

            $result = Invoke-RestMethod "https://127.0.0.1:$port$path" `
                -SkipCertificateCheck `
                -Method $method `
                -Authentication 'Basic' `
                -Credential $cred `
                -ContentType 'application/json' `
                -Body $($body | ConvertTo-Json)

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
        } Catch {
            $attempts--
            If ($attempts -le 0) {
                Write-Host "Failed to $method '$path'."
                Throw $_
            }
            Write-Host "Failed to $method '$path', retrying: $_"
            Start-Sleep 5
        }
    }
}

function Invoke-RCSRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [Int]$attempts = 100,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest $RCS_PORT $RCS_PWD $path $method $body $attempts $OutFile
}

function Invoke-LOLRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [Int]$attempts = 100,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest $LOL_PORT $LOL_PWD $path $method $body $attempts $OutFile
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

Create-Folder 'rcs'
Create-Folder 'lol'

Write-Host 'Dumping RCS schemas...'
Invoke-RCSRequest '/swagger/v2/swagger.json' -OutFile 'rcs/swagger.json'
Invoke-RCSRequest '/swagger/v3/openapi.json' -OutFile 'rcs/openapi.json'

Write-Host 'Dumping RCS data...'
Invoke-RCSRequest '/product-metadata/v2/products' -OutFile 'rcs/products.json'

Write-Host 'Dumping LCU schemas...'
Invoke-LOLRequest '/swagger/v2/swagger.json' -OutFile 'lol/swagger.json'
Invoke-LOLRequest '/swagger/v3/openapi.json' -OutFile 'lol/openapi.json'

Write-Host 'Dumping LCU data...'
Invoke-LOLRequest '/lol-maps/v2/maps' -OutFile 'lol/maps.json'
Invoke-LOLRequest '/lol-game-queues/v1/queues' -OutFile 'lol/queues.json'
Invoke-LOLRequest '/lol-store/v1/catalog' -OutFile 'lol/catalog.json'

Write-Host 'Dumping LOL version...'
$versionObject = @{}
$versionObject.Add('client', (Invoke-LOLRequest '/system/v1/builds').version)
$versionObject.Add('game', (Invoke-LOLRequest '/lol-patch/v1/game-version').TrimStart('"').TrimEnd('"'))
ConvertTo-Json $versionObject | Out-File "lol/version.txt"

Write-Host 'Copying pengu plugin...'
New-Item -Path "$PENGU_DIR/plugins/updater-pengu" -ItemType Directory -Force
Copy-Item ..\watchdog\updater-pengu\dist\index.js "$PENGU_DIR/plugins/updater-pengu/index.js"

Write-Host 'Restarting LOL UX...'
Invoke-LOLRequest '/riotclient/kill-and-restart-ux' 'POST'

# Wait until pengu dumper is done...
Write-Host 'Dumping plugins...'
$attempts = 100
while (-not (Test-Path "$PENGU_DIR/plugins/updater-pengu/status")) {
	Start-Sleep 1

	$attempts--
	Write-Host "Attempts left: $attempts"
}

Write-Host 'Copying plugin output to content folder...'
Clean-Folder .\plugins\
Copy-Item -Force -Recurse -Verbose -Path "$PENGU_DIR\plugins\updater-pengu\output\*" -Destination .\plugins\

Write-Host 'Installing js beautifier...'
npm i -g js-beautify

Write-Host 'Beautifying plugins...'
Push-Location .\plugins\
js-beautify -f * -r --type js
Pop-Location

Write-Host 'Success!'
