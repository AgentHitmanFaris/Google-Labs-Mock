<#
.SYNOPSIS
    Jules AI Client (PowerShell Edition)
    Mimics the functionality of the official Google Jules CLI.

.DESCRIPTION
    Supports both Interactive TUI mode and CLI arguments mode.
    Examples:
      .\jules.ps1                              # Launch Interactive Menu
      .\jules.ps1 new "Write unit tests"       # Create session for current git repo
      .\jules.ps1 new --repo "owner/repo" "Hi" # Create session for specific repo
      .\jules.ps1 remote list --session        # List active sessions
      "Fix this" | .\jules.ps1 new             # Pipe input support
#>

[CmdletBinding()]
param (
    [Parameter(Position=0)]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$SubCommand,

    [Parameter(Position=2, ValueFromPipeline=$true)]
    [string]$PromptInput,

    [string]$Repo,
    [int]$Parallel = 1,
    [switch]$Session,
    [switch]$List
)

# --- CONFIGURATION ---
$baseUrl = "https://jules.googleapis.com/v1alpha"
$keyFile = Join-Path $PSScriptRoot "key"

# --- API KEY CHECK ---
if (-not (Test-Path $keyFile)) {
    Write-Error "KEY FILE MISSING: Create a file named 'key' with your API key in this directory."
    exit 1
}
$apiKey = (Get-Content -Path $keyFile -Raw).Trim()
$cleanKey = $apiKey -replace '\s+', ''
$cleanUrl = $baseUrl -replace '\s+', ''

# --- HELPER: DETECT CURRENT GIT REPO ---
function Get-Current-Git-Repo {
    try {
        $url = git config --get remote.origin.url
        if ($url) {
            # Convert "git@github.com:owner/repo.git" or "https://github.com/owner/repo" to "owner/repo"
            if ($url -match 'github\.com[:/](.+?)/(.+?)(\.git)?$') {
                return "$($matches[1])/$($matches[2])"
            }
        }
    } catch {}
    return $null
}

# --- CORE API FUNCTIONS ---

function Get-JulesRepos {
    $endpoint = "$cleanUrl/sources"
    $allRepos = @()
    $nextPageToken = $null
    do {
        $uri = if ($nextPageToken) { "$endpoint`?pageToken=$nextPageToken" } else { $endpoint }
        try {
            $resp = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ "X-Goog-Api-Key" = $cleanKey }
            if ($resp.sources) { $allRepos += $resp.sources }
            $nextPageToken = $resp.nextPageToken
        } catch { Write-Error "Failed to fetch repos: $($_.Exception.Message)"; return @() }
    } while ($nextPageToken)
    return $allRepos
}

function Start-JulesSession {
    param ($repoName, $prompt, $count = 1)

    # 1. Validate Repo
    if (-not $repoName) {
        Write-Host " [?] No repo specified. Checking current directory..." -ForegroundColor DarkGray
        $repoName = Get-Current-Git-Repo
        if (-not $repoName) {
            Write-Error "Could not detect git repo. Use --repo 'owner/name' or run inside a git folder."
            exit 1
        }
    }
    
    # 2. Find Repo Object (to get default branch)
    Write-Host " [..] Locating repo: $repoName" -ForegroundColor Cyan
    $sources = Get-JulesRepos
    # Fuzzy match logic
    $target = $sources | Where-Object { $_.name -match $repoName } | Select-Object -First 1

    if (-not $target) {
        Write-Error "Repository '$repoName' not found in your Jules access list."
        exit 1
    }

    $branch = "main"
    if ($target.githubRepo.defaultBranch.displayName) {
        $branch = $target.githubRepo.defaultBranch.displayName
    }

    # 3. Create Sessions
    for ($i = 1; $i -le $count; $i++) {
        $payload = @{
            prompt = $prompt
            sourceContext = @{
                source = $target.name
                githubRepoContext = @{ startingBranch = $branch }
            }
            title = if ($count -gt 1) { "CLI: $prompt ($i)" } else { "CLI: $prompt" }
        } | ConvertTo-Json -Depth 10

        try {
            $resp = Invoke-RestMethod -Uri "$cleanUrl/sessions" -Method Post -Body $payload -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
            Write-Host " [OK] Session Created: $($resp.name) (Ref: $repoName::$branch)" -ForegroundColor Green
            
            # If only 1 session, enter chat loop automatically
            if ($count -eq 1) {
                global:var_sessionId = $resp.name
                Enter-ChatLoop
            }
        } catch {
            Write-Error "Failed to create session: $($_.Exception.Message)"
        }
    }
}

function Get-JulesSessions {
    try {
        $resp = Invoke-RestMethod -Uri "$cleanUrl/sessions" -Method Get -Headers @{ "X-Goog-Api-Key" = $cleanKey }
        return $resp.sessions
    } catch { Write-Error "Error fetching sessions: $($_.Exception.Message)"; return @() }
}

function Enter-ChatLoop {
    if (-not $global:var_sessionId) { return }
    $sessId = $global:var_sessionId
    Write-Host "`n[ATTACHED] $sessId" -ForegroundColor Yellow
    Write-Host "Ctrl+C to exit.`n" -ForegroundColor DarkGray

    $seenIds = @()
    while ($true) {
        try {
            $resp = Invoke-RestMethod -Uri "$cleanUrl/$sessId/activities" -Method Get -Headers @{ "X-Goog-Api-Key" = $cleanKey }
            if ($resp.activities) {
                [array]::Reverse($resp.activities)
                foreach ($act in $resp.activities) {
                    if ($act.id -notin $seenIds) {
                        $seenIds += $act.id
                        
                        if ($act.agentMessaged) { 
                            Write-Host "`n[JULES] $($act.agentMessaged.agentMessage)" -ForegroundColor Green
                            $reply = Read-Host " [REPLY] > "
                            if ($reply) {
                                $body = @{ prompt = $reply } | ConvertTo-Json
                                Invoke-RestMethod -Uri "$cleanUrl/$sessId`:sendMessage" -Method Post -Body $body -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
                            }
                        }
                        elseif ($act.planGenerated) {
                            Write-Host "`n[PLAN] Proposed:" -ForegroundColor Cyan
                            $act.planGenerated.plan.steps | ForEach-Object { Write-Host " - $($_.title)" }
                            $ans = Read-Host " [APPROVE?] (Y/N) > "
                            if ($ans -eq "Y") {
                                Invoke-RestMethod -Uri "$cleanUrl/$sessId`:approvePlan" -Method Post -Body "{}" -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
                            }
                        }
                        elseif ($act.artifacts) {
                             Write-Host " [CODE] Jules generated code artifacts." -ForegroundColor Magenta
                        }
                    }
                }
            }
            Start-Sleep 2
        } catch { Start-Sleep 5 }
    }
}

# --- MAIN EXECUTION LOGIC ---

# 1. Handle Pipeline Input (for piping "echo task | jules new")
if ($input.MoveNext()) {
    $PromptInput = $input | Out-String
}

# 2. CLI MODE
if ($Command) {
    switch ($Command) {
        "new" {
            if (-not $PromptInput) { $PromptInput = $SubCommand } # Handle 'jules new "task"'
            if (-not $PromptInput) { Write-Error "Please provide instructions."; exit 1 }
            Start-JulesSession -repoName $Repo -prompt $PromptInput -count $Parallel
        }
        "remote" {
            if ($SubCommand -eq "list") {
                if ($Session) {
                    Get-JulesSessions | ForEach-Object { 
                        Write-Host "[$($_.state)] $($_.name) - $($_.title)" -ForegroundColor (if ($_.state -eq 'ACTIVE') {'Green'} else {'Gray'})
                    }
                }
                elseif ($Repo) { # 'remote list --repo' logic (flag is mapped to $Repo param typically, but here emulating via switch)
                     Get-JulesRepos | ForEach-Object { Write-Host $_.name }
                }
                else {
                    # Default to list sessions if no flag
                    Get-JulesSessions | ForEach-Object { Write-Host "[$($_.state)] $($_.name)" }
                }
            }
            elseif ($SubCommand -eq "pull") {
                Write-Warning "Pull functionality requires checking artifacts manually in this client version."
            }
        }
        "version" {
            Write-Host "Jules PowerShell Client v1.0"
        }
        Default {
            Write-Host "Unknown command. Use: new, remote list, or run without args for menu."
        }
    }
    exit 0
}

# 3. INTERACTIVE MODE (Legacy Menu)
# If no arguments provided, fall back to the TUI
function Show-Header { Clear-Host; Write-Host "=== JULES AI (INTERACTIVE) ===" -ForegroundColor Cyan }

while ($true) {
    Show-Header
    Write-Host " [1] NEW SESSION (Select Repo)"
    Write-Host " [2] NEW SESSION (Auto-Detect Current Repo)"
    Write-Host " [3] LIST SESSIONS"
    Write-Host " [4] RESUME SESSION"
    Write-Host " [Q] QUIT"
    
    $sel = Read-Host " > "
    switch ($sel) {
        "1" { 
            $repos = Get-JulesRepos
            $i=1; $repos | ForEach-Object { Write-Host "[$i] $($_.name)"; $i++ }
            $idx = Read-Host "Select #"; $r = $repos[[int]$idx-1]
            $p = Read-Host "Task"; Start-JulesSession -repoName $r.name -prompt $p
        }
        "2" {
            $p = Read-Host "Task"; Start-JulesSession -prompt $p
        }
        "3" {
            Get-JulesSessions | Format-Table name, state, title
            Pause
        }
        "4" {
            $id = Read-Host "Session ID (full string)"; 
            global:var_sessionId = $id; Enter-ChatLoop
        }
        "Q" { exit }
    }
}