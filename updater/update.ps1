#requires -PSEdition Core

$RCS_PWD = $env:RCS_PASSWORD
$RCS_PORT = $env:RCS_PORT

$LOL_PWD = $env:LCU_PASSWORD
$LOL_PORT = $env:LCU_PORT
$LOL_PATCHLINE = $env:LCU_PATCHLINE
$LCU_DIR = $env:LCU_DIR

$PENGU_DIR = $env:PENGU_DIR
$PENGU_PLUGIN_DIR = "$PENGU_DIR/plugins/updater-pengu"
$PENGU_PLUGIN_STATUS_PATH = "$PENGU_PLUGIN_DIR/status"
$PENGU_PLUGIN_LOG_PATH = "$PENGU_PLUGIN_DIR/log.txt"

$RCS_DIR = 'rcs'
$LOL_DIR = 'lol/' + $LOL_PATCHLINE
$LOL_GAME_DIR = "$LOL_DIR/game"

function Invoke-RiotRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$port,
        [Parameter(Mandatory=$true)]  [String]$password,
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [bool]$Mandatory = $False,
        [Parameter(Mandatory=$false)] [bool]$SilentError = $False, # only throw, dont log
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
            -Body $($body | ConvertTo-Json -Depth 100)
    } Catch {
        # Better error info
        $msg = "Failed to $method '$path'! Error: $_"
        if ($Mandatory -ne $True) {
            Warn $msg
            return $null
        } elseif ($SilentError -eq $False) {
            Fail $msg
        } else {
            throw $_
        }
    }

    if (![string]::IsNullOrEmpty($OutFile)) {
        # We need this dirty code to properly format json when outputting

        if ($result -is [string] ||
            $result -is [number]) {
            Out-File -FilePath $OutFile -InputObject $result
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
        [Parameter(Mandatory=$false)] [bool]$SilentError = $False,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest $RCS_PORT $RCS_PWD $path $method $body $SilentError $Mandatory $OutFile
}

function Invoke-LOLRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [bool]$Mandatory = $False,
        [Parameter(Mandatory=$false)] [bool]$SilentError = $False,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest $LOL_PORT $LOL_PWD $path $method $body $SilentError $Mandatory $OutFile
}

function Invoke-GameClientRequest {
    Param (
        [Parameter(Mandatory=$true)]  [String]$path,
        [Parameter(Mandatory=$false)] [String]$method = 'GET',
        [Parameter(Mandatory=$false)] $body = $null,
        [Parameter(Mandatory=$false)] [bool]$Mandatory = $False,
        [Parameter(Mandatory=$false)] [bool]$SilentError = $False,
        [Parameter(Mandatory=$false)] [String]$OutFile = $null
    )

    Return Invoke-RiotRequest 2999 'doesntmatter' $path $method $body $SilentError $Mandatory $OutFile
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

function Copy-Logs {
    $logsPath = "$env:GITHUB_WORKSPACE/updaterLogs"
    Create-Folder $logsPath
    
    Write-Output "logs-upload=true" >> $env:GITHUB_OUTPUT
    Write-Output "logs-path=$logsPath" >> $env:GITHUB_OUTPUT
    
    if (Test-Path $PENGU_PLUGIN_LOG_PATH) {
        Copy-Item $PENGU_PLUGIN_LOG_PATH -Destination "$logsPath/pengu_log.txt"
    }

    $leagueLogsPath = "$LCU_DIR/Logs/LeagueClient Logs/*"
    if (Test-Path $leagueLogsPath) {
        $path = "$logsPath/lcu/"
        Create-Folder $path
        Copy-Item -Force -Recurse -Path $leagueLogsPath -Destination $path
    }
}

$copyLogs = $false

function Warn {
    Param (
        [Parameter(Mandatory=$true)] [String]$message
    )

    $copyLogs = $True
    Write-Output "::warning::$message"
}

function Fail {
    Param (
        [Parameter(Mandatory=$true)] [String]$message
    )

    Copy-Logs
    throw $message
}

function Wait-Phase {
    Param (
        [Parameter(Mandatory=$true)] [String]$phase
    )

    do {
        Start-Sleep 1
        $gamePhase = Invoke-LOLRequest '/lol-gameflow/v1/gameflow-phase' -Mandatory $True
        Write-Host "Waiting for $phase phase. Current phase: $gamePhase"
    } while ($gamePhase -ne $phase)
}

function Wait-Game-Endpoint {
    Param (
        [Parameter(Mandatory=$true)] [String]$endpoint
    )

    do {
        Start-Sleep 1

        try {
            $result = Invoke-GameClientRequest $endpoint -Mandatory $False -SilentError $True

            if ($result.errorCode -eq $null) {
                break
            }
        } catch {
            # try again
        }
    } while ($True)
}

Create-Folder 'rcs'
Create-Folder 'lol'
Create-Folder $LOL_DIR
Create-Folder $LOL_GAME_DIR

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

Invoke-LOLRequest '/plugin-manager/v3/plugins-manifest' -Mandatory $True -OutFile $LOL_DIR/plugin-manifest.json

Write-Host 'Dumping LOL version...'
$versionObject = @{}
$versionObject.Add('client', (Invoke-LOLRequest '/system/v1/builds' -Mandatory $True).version)
$versionObject.Add('game', (Invoke-LOLRequest '/lol-patch/v1/game-version' -Mandatory $True).TrimStart('"').TrimEnd('"'))
ConvertTo-Json $versionObject | Out-File $LOL_DIR/version.txt

Write-Host 'Copying pengu plugin...'
New-Item -Path $PENGU_PLUGIN_DIR -ItemType Directory -Force
Copy-Item ..\watchdog\updater-pengu\dist\index.js "$PENGU_PLUGIN_DIR/index.js"

$attempts = 5
while (-not (Test-Path $PENGU_PLUGIN_LOG_PATH) -And $attempts -Gt 0) {
	Write-Host "Restarting LOL UX... Attempts left: $attempts"
	Invoke-LOLRequest '/riotclient/kill-and-restart-ux' 'POST'
	
	Start-Sleep 10
	$attempts--

	if ($attempts -Eq 0) {
		Fail 'Failed to install pengu plugin!'
	}
}

# Wait until pengu dumper is done...
Write-Host 'Dumping plugins...'
$attempts = 100
while (-not (Test-Path $PENGU_PLUGIN_STATUS_PATH) -And $attempts -Gt 0) {
	Start-Sleep 1

	$attempts--
	Write-Host "Attempts left: $attempts"

	if ($attempts -Eq 0) {
		Fail 'Failed to dump plugins!'
	}
}

$plugins_dir = "$LOL_DIR/plugins/"

Write-Host 'Copying plugin output to content folder...'
Clean-Folder $plugins_dir
Copy-Item -Force -Recurse -Verbose -Path "$PENGU_PLUGIN_DIR/output/*" -Destination $plugins_dir

Write-Host 'Installing js beautifier...'
npm i -g js-beautify

Write-Host 'Beautifying plugins...'
Push-Location $plugins_dir
js-beautify -f * -r --type js
Pop-Location

Write-Host 'Creating a custom lobby...'
$lobbyResponse = Invoke-LOLRequest '/lol-lobby/v2/lobby' 'POST' @{
    customGameLobby = @{
      configuration = @{
        gameMode = "CLASSIC";
        gameMutator = "";
        gameServerRegion = "";
        mapId = 11;
        mutators = @{
          id = 1
        };
        spectatorPolicy = "NotAllowed";
        teamSize = 5;
      };
      lobbyName = "uwu owo";
      lobbyPassword = "password123?";
    };
    isCustom = $True;
    queueId = -1;
}

if ($lobbyResponse.errorCode -eq $null) {
    Write-Host 'Lobby created!'
} else {
    Write-Host $lobbyResponse
}

Wait-Phase 'Lobby'

Write-Host 'Starting champion select...'
Invoke-LOLRequest '/lol-lobby/v1/lobby/custom/start-champ-select' 'POST'

Wait-Phase 'ChampSelect'

Write-Host 'Selecting a random champion...'
$champions = Invoke-LOLRequest '/lol-champ-select/v1/pickable-champion-ids'
Invoke-LOLRequest '/lol-champ-select/v1/session/actions/1' 'PATCH' @{
    completed = $True;
    championId = $champions[0]
}

Wait-Phase 'InProgress'

Write-Host 'Waiting for game API initialization...'
Wait-Game-Endpoint '/liveclientdata/activeplayername'

Write-Host 'Dumping LOL schemas...'
Invoke-GameClientRequest '/swagger/v2/swagger.json' -Mandatory $True -OutFile $LOL_GAME_DIR/swagger.json
Invoke-GameClientRequest '/swagger/v3/openapi.json' -Mandatory $True -OutFile $LOL_GAME_DIR/openapi.json

# END
Write-Host 'Finishing...'

Stop-Process -Name 'League of Legends' -ErrorAction Ignore

if ($copyLogs -Eq $True) {
    Write-Host 'Copying logs...'
    Copy-Logs
}

Write-Host 'Success!'
