#requires -PSEdition Core

$RCS_PWD = $env:RCS_PASSWORD
$RCS_DIR = $env:RCS_DIR
$RCS_PORT = $env:RCS_PORT

$LOL_PWD = $env:LCU_PASSWORD
$LOL_DIR = $env:LCU_DIR
$LOL_PORT = $env:LCU_PORT

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
                -Body $($body | ConvertTo-Json) `
                -OutFile $OutFile
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

Create-Folder 'rcs'
Create-Folder 'lol'

Invoke-RCSRequest '/swagger/v2/swagger.json' -OutFile 'rcs/swagger.json'
Invoke-RCSRequest '/swagger/v3/openapi.json' -OutFile 'rcs/openapi.json'

Invoke-LOLRequest '/swagger/v2/swagger.json' -OutFile 'lol/swagger.json'
Invoke-LOLRequest '/swagger/v3/openapi.json' -OutFile 'lol/openapi.json'
Invoke-LOLRequest '/lol-patch/v1/game-version' -OutFile 'lol/version.txt'
Invoke-LOLRequest '/lol-maps/v1/maps' -OutFile 'lol/maps.json'
Invoke-LOLRequest '/lol-game-queues/v1/queues' -OutFile 'lol/queues.json'
Invoke-LOLRequest '/lol-store/v1/catalog' -OutFile 'lol/catalog.json'

Write-Host 'Success!'
