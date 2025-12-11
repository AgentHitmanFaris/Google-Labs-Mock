# --- CONFIGURATION ---
$baseUrl = "https://jules.googleapis.com/v1alpha"

# --- API KEY LOADING ---
$keyFile = Join-Path $PSScriptRoot "key"

if (-not (Test-Path $keyFile)) {
    Write-Host "===============================================================" -ForegroundColor Red
    Write-Host " [ERROR] KEY FILE MISSING" -ForegroundColor Yellow
    Write-Host " Please create a file named 'key' in the same directory as this script" -ForegroundColor White
    Write-Host " and paste your Google Cloud API Key inside it." -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor Red
    Pause
    exit
}

$apiKey = Get-Content -Path $keyFile -Raw
$apiKey = $apiKey.Trim()

# --- SAFETY CHECK ---
if ($apiKey -eq "PASTE_YOUR_REAL_GOOGLE_API_KEY_HERE" -or $apiKey -eq "API" -or [string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Host "===============================================================" -ForegroundColor Red
    Write-Host " [ERROR] INVALID API KEY" -ForegroundColor Yellow
    Write-Host " The 'key' file must contain your actual Google Cloud API Key." -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor Red
    Pause
    exit
}

# --- GLOBAL STATE ---
$cleanKey = $apiKey -replace '\s+', ''
$cleanUrl = $baseUrl -replace '\s+', ''
$global:globalSessionId = $null

# --- HELPERS ---

<#
.SYNOPSIS
    Displays the application header.

.DESCRIPTION
    Clears the host screen and prints the application title and the current session ID if one is active.
    This function is used to refresh the UI and provide context to the user.

.OUTPUTS
    None
        This function writes directly to the host and does not return a value.
#>
function Show-Header {
    Clear-Host
    Write-Host "=== JULES AI CLIENT (V20 MODE SELECT) ===" -ForegroundColor Cyan
    if ($global:globalSessionId) {
        Write-Host "ACTIVE SESSION: $global:globalSessionId" -ForegroundColor Yellow
    } else {
        Write-Host "NO ACTIVE SESSION" -ForegroundColor DarkGray
    }
    Write-Host "------------------------------------" -ForegroundColor DarkGray
}

# --- FUNCTION 1: FETCH REPOS ---

<#
.SYNOPSIS
    Fetches available repositories from the API.

.DESCRIPTION
    Retrieves a list of repositories from the Jules AI API.
    It handles pagination automatically to ensure all available repositories are retrieved.
    Errors during the API call are caught and logged to the console.

.OUTPUTS
    System.Array
        Returns an array of repository objects. Each object contains details about a repository source.
#>
function Fetch-RepositoryData {
    $endpoint = "$cleanUrl/sources"
    $allRepos = @()
    $nextPageToken = $null

    Write-Host " [SYSTEM] Syncing Repositories..." -ForegroundColor Cyan

    do {
        if ($nextPageToken) {
            $safeToken = [Uri]::EscapeDataString($nextPageToken)
            $currentUrl = "$endpoint`?pageToken=$safeToken"
        } else {
            $currentUrl = $endpoint
        }
        try {
            $response = Invoke-RestMethod -Uri $currentUrl -Method Get -Headers @{ "X-Goog-Api-Key" = $cleanKey }
            if ($response.sources) {
                $allRepos += $response.sources
            }
            $nextPageToken = $response.nextPageToken
        }
        catch {
            Write-Host " [!] Error fetching repos: $($_.Exception.Message)" -ForegroundColor Red
            return $allRepos
        }
    } while ($nextPageToken)
    return $allRepos
}

# --- FUNCTION 2: LIVE CHAT AGENT ---

<#
.SYNOPSIS
    Starts the main chat loop for an active session.

.DESCRIPTION
    This function enters an infinite loop that polls the Jules AI API for new activities (messages, plans, code changes).
    It displays these activities to the user and handles required user actions, such as approving plans or replying to messages.
    The loop continues until an error occurs or the user interrupts execution.

    The function handles:
    - Displaying proposed plans.
    - Displaying agent messages.
    - Displaying user messages.
    - Displaying code changes and terminal output.
    - Sending user approvals for plans.
    - Sending user replies to the agent.

.OUTPUTS
    None
        This function does not return a value. It runs until interrupted.
#>
function Start-Chat-Loop {
    if ([string]::IsNullOrWhiteSpace($global:globalSessionId)) {
        Write-Host "[!] No active session." -ForegroundColor Red; Start-Sleep 2; return
    }

    Write-Host "`n[JULES CONNECTED] Session Active." -ForegroundColor Green
    Write-Host "You can now chat naturally. Press 'Ctrl+C' to exit to menu." -ForegroundColor Gray
    Write-Host "--------------------------------------------------------" -ForegroundColor DarkGray

    $seenIds = @()

    try {
        while ($true) {
            # 1. FETCH ACTIVITIES
            $url = "$cleanUrl/$($global:globalSessionId)/activities"
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{ "X-Goog-Api-Key" = $cleanKey }

            $actionRequired = $false
            $actionType = ""

            if ($response.activities) {
                $acts = $response.activities
                [array]::Reverse($acts)

                foreach ($act in $acts) {
                    if ($act.id -notin $seenIds) {
                        $seenIds += $act.id

                        # --- DISPLAY ACTIVITY ---

                        # PLAN
                        if ($act.planGenerated) {
                            Write-Host "`n[PLAN PROPOSED]" -ForegroundColor Cyan
                            foreach ($step in $act.planGenerated.plan.steps) {
                                Write-Host "   [$($step.index)] $($step.title)" -ForegroundColor White
                            }
                            $actionRequired = $true
                            $actionType = "APPROVE"
                        }

                        # AGENT MESSAGE
                        elseif ($act.agentMessaged) {
                            Write-Host "`n[JULES SAYS]" -ForegroundColor Green
                            Write-Host "   $($act.agentMessaged.agentMessage)" -ForegroundColor White
                            $actionRequired = $true
                            $actionType = "REPLY"
                        }

                        # USER MESSAGE
                        elseif ($act.userMessaged) {
                            Write-Host "`n[YOU SAID]" -ForegroundColor Blue
                            Write-Host "   $($act.userMessaged.userMessage)" -ForegroundColor Gray
                        }

                        # CODE / TERMINAL
                        elseif ($act.artifacts) {
                            foreach ($art in $act.artifacts) {
                                if ($art.changeSet) {
                                    Write-Host "   [CODE CHANGE] Jules wrote code." -ForegroundColor Magenta
                                }
                                elseif ($art.bashOutput) {
                                    Write-Host "   [TERMINAL] $($art.bashOutput.command)" -ForegroundColor DarkGray
                                }
                            }
                        }

                        # PROGRESS
                        elseif ($act.progressUpdated) {
                            Write-Host "   [WORKING] $($act.progressUpdated.title)" -ForegroundColor DarkGray
                        }
                    }
                }
            }

            # 2. HANDLE ACTIONS (Automatic Prompts)
            if ($actionRequired) {
                if ($actionType -eq "APPROVE") {
                    Write-Host ""
                    $ans = Read-Host " [ACTION] Approve this Plan? (Y/N)"
                    if ($ans -eq "Y" -or $ans -eq "y") {
                        Write-Host " [SENDING] Approving Plan..." -ForegroundColor Yellow
                        $appUrl = "$cleanUrl/$global:globalSessionId" + ":approvePlan"
                        Invoke-RestMethod -Uri $appUrl -Method Post -Body "{}" -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
                        Write-Host " [APPROVED] Jules is back to work." -ForegroundColor Green
                    }
                    else {
                         $reason = Read-Host " [FEEDBACK] What should change?"
                         $msgUrl = "$cleanUrl/$global:globalSessionId" + ":sendMessage"
                         $body = @{ prompt = $reason } | ConvertTo-Json
                         Invoke-RestMethod -Uri $msgUrl -Method Post -Body $body -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
                         Write-Host " [SENT] Feedback sent." -ForegroundColor Green
                    }
                }
                elseif ($actionType -eq "REPLY") {
                    Write-Host ""
                    $msg = Read-Host " [REPLY] Type your answer"
                    if (-not [string]::IsNullOrWhiteSpace($msg)) {
                        $msgUrl = "$cleanUrl/$global:globalSessionId" + ":sendMessage"
                        $body = @{ prompt = $msg } | ConvertTo-Json
                        Invoke-RestMethod -Uri $msgUrl -Method Post -Body $body -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
                        Write-Host " [SENT] Reply sent." -ForegroundColor Green
                    }
                }
            }
            else {
                # 3. SPINNER
                Write-Host "." -NoNewline -ForegroundColor DarkGray
                Start-Sleep 3
            }
        }
    }
    catch {
        Write-Host "`n[ERROR] Connection lost: $($_.Exception.Message)" -ForegroundColor Red
        Start-Sleep 2
    }
}

# --- FUNCTION 3: START NEW SESSION (UPDATED MODE SELECT) ---

<#
.SYNOPSIS
    Starts a new AI session.

.DESCRIPTION
    Prompts the user to select a repository, branch, and interaction mode (Interactive, Review, or Start).
    Based on the user's choices and prompt, it initiates a new session with the Jules AI API.

    The function supports three modes:
    1. Interactive: Forces the agent to discuss goals first.
    2. Review: Standard behavior where the agent generates a plan for approval.
    3. Start: Forces the agent to start working immediately without plan approval.

.PARAMETER repos
    An array of repository objects obtained from Fetch-RepositoryData.
    This parameter is required to allow the user to select a repository.

.OUTPUTS
    None
        This function does not return a value. It modifies the global session state.
#>
function Start-New-Session {
    param ($repos)
    Show-Header

    # 1. Select Repo
    Write-Host "SELECT REPO:" -ForegroundColor Cyan
    $i = 1
    foreach ($r in $repos) {
        $n = $r.name.Split('/')[-1]
        Write-Host " [$i] $n"
        $i++
    }
    while ($true) {
        $sel = Read-Host " > Number (or 'Q' to Cancel)"
        if ($sel -eq 'Q' -or $sel -eq 'q') { return }

        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $repos.Count) {
            $target = $repos[[int]$sel-1]
            break
        }
        Write-Host "[!] Invalid selection. Please try again." -ForegroundColor Red
    }

    # 2. Select Branch
    $defBranch = $null
    if ($target.githubRepo -and $target.githubRepo.defaultBranch) {
        $defBranch = $target.githubRepo.defaultBranch.displayName
    }

    Write-Host " > Selected Repo: $($target.name.Split('/')[-1])" -ForegroundColor Gray

    if ($defBranch) {
        $bSel = Read-Host " > Branch (Press Enter for '$defBranch')"
        if ([string]::IsNullOrWhiteSpace($bSel)) { $branch = $defBranch } else { $branch = $bSel }
    } else {
        while ([string]::IsNullOrWhiteSpace($branch)) { $branch = Read-Host " > Branch (Required)" }
    }

    # 3. SELECT MODE (The New Feature!)
    Write-Host "`nSELECT MODE:" -ForegroundColor Cyan
    Write-Host " [1] Interactive (Chat first, understand goals)" -ForegroundColor White
    Write-Host " [2] Review (Generate plan, wait for approval)" -ForegroundColor White
    Write-Host " [3] Start (Get started without plan approval)" -ForegroundColor White

    $modeSel = ""
    while ($true) {
        $inputSel = Read-Host " > Number (Default: 2)"
        if ([string]::IsNullOrWhiteSpace($inputSel)) { $modeSel = "2"; break }
        if ($inputSel -in "1", "2", "3") { $modeSel = $inputSel; break }
        Write-Host " [!] Invalid mode. Please select 1, 2, or 3." -ForegroundColor Red
    }

    # Mode Logic: We inject a "System Hint" to force Jules to behave
    $modeHint = ""
    if ($modeSel -eq "1") {
        $modeHint = "IMPORTANT: Please discuss the goals with me first. Do not generate a plan yet. I want to have an interactive conversation to clarify requirements. "
    }
    elseif ($modeSel -eq "3") {
        $modeHint = "IMPORTANT: Please start working immediately. Do not wait for plan approval. Just execute the necessary steps. "
    }
    # Default (2) needs no hint, it's the standard behavior.

    # 4. Instructions
    Write-Host " > Instructions (e.g., 'Fix the bug in login.py', 'Add unit tests')" -ForegroundColor Gray
    $prompt = Read-Host " > "
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        Write-Host " [!] No instructions provided. Saying 'Hello' to Jules." -ForegroundColor Yellow
        $prompt = "Hello"
    }

    # Combine Hint + Prompt
    $finalPrompt = "$modeHint $prompt"

    $payload = @{
        prompt = $finalPrompt
        sourceContext = @{
            source = $target.name
            githubRepoContext = @{ startingBranch = $branch }
        }
        title = "CLI: $($target.name.Split('/')[-1])"
    } | ConvertTo-Json -Depth 10

    Write-Host "[NET] Creating Session..." -ForegroundColor DarkGray
    try {
        $resp = Invoke-RestMethod -Uri "$cleanUrl/sessions" -Method Post -Body $payload -ContentType "application/json" -Headers @{ "X-Goog-Api-Key" = $cleanKey }
        $global:globalSessionId = $resp.name
        Write-Host "[SUCCESS] Session Created: $global:globalSessionId" -ForegroundColor Green
        Start-Sleep -Seconds 1
        Start-Chat-Loop
    }
    catch {
        Write-Host "[ERROR] Could not start session: $($_.Exception.Message)" -ForegroundColor Red
        Pause
    }
}

# --- FUNCTION 4: RESTORE SESSION ---

<#
.SYNOPSIS
    Restores a previous session.

.DESCRIPTION
    Fetches a list of recent sessions from the API and displays them to the user.
    The user can then select a session to resume. The session state (ACTIVE, WAIT, DONE, FAIL) is indicated by color.
    Upon selection, the session ID is updated globally and the chat loop is started.

.OUTPUTS
    None
        This function does not return a value. It modifies the global session state.
#>
function Restore-Session {
    Show-Header
    Write-Host "FETCHING RECENT SESSIONS..." -ForegroundColor Cyan

    try {
        $url = "$cleanUrl/sessions"
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{ "X-Goog-Api-Key" = $cleanKey }

        if (!$response.sessions) {
            Write-Host " [!] No recent sessions found on server." -ForegroundColor Yellow
            Start-Sleep 2; return
        }

        $i = 1
        $list = @()
        foreach ($sess in $response.sessions) {
            $title = if ($sess.title) { $sess.title } else { $sess.name.Split('/')[-1] }
            $state = if ($sess.state) { $sess.state } else { "UNKNOWN" }

            $color = "White"
            if ($state -eq "ACTIVE") { $color = "Green" }
            elseif ($state -match "WAIT") { $color = "Yellow" }
            elseif ($state -match "DONE" -or $state -match "SUCCEEDED") { $color = "Gray" }
            elseif ($state -match "FAIL") { $color = "Red" }

            Write-Host " [$i] [$state] $title" -ForegroundColor $color
            $list += $sess
            $i++
        }

        Write-Host ""
        while ($true) {
            $sel = Read-Host " > Select Number to Restore (or 'Q' to Cancel)"
            if ($sel -eq 'Q' -or $sel -eq 'q') { return }

            if ($sel -match '^\d+$') {
                $idx = [int]$sel - 1
                if ($idx -ge 0 -and $idx -lt $list.Count) {
                    $selectedSession = $list[$idx]
                    $global:globalSessionId = $selectedSession.name
                    Write-Host " [OK] Restored: $global:globalSessionId" -ForegroundColor Green
                    Start-Sleep 1
                    Start-Chat-Loop
                    break
                } else {
                     Write-Host " [X] Selection out of range." -ForegroundColor Red
                }
            } else {
                Write-Host " [X] Invalid selection." -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host " [ERROR] Could not fetch history: $($_.Exception.Message)" -ForegroundColor Red
        Pause
    }
}

# --- MAIN LOOP ---
$cachedRepos = $null

while ($true) {
    Show-Header

    $monitorLabel = "RESUME CHAT"
    if ($global:globalSessionId) {
        $shortId = $global:globalSessionId.Split('/')[-1]
        $monitorLabel = "RESUME CHAT (Current: ...$shortId)"
    }

    Write-Host " [1] REFRESH REPOS (Cached: $(if ($cachedRepos) { $cachedRepos.Count } else { 0 }))"
    Write-Host " [2] START NEW SESSION"

    if ($global:globalSessionId) {
        Write-Host " [3] $monitorLabel"
    }

    Write-Host " [4] RESTORE RECENT SESSION" -ForegroundColor Yellow
    Write-Host " [Q] QUIT"

    $choice = Read-Host " > Select"

    switch ($choice) {
        "1" {
            $cachedRepos = Fetch-RepositoryData
            Write-Host "Synced $($cachedRepos.Count) repos." -ForegroundColor Green
            Start-Sleep 1
        }
        "2" {
            if (-not $cachedRepos) {
                $cachedRepos = Fetch-RepositoryData
            }
            if ($cachedRepos) {
                Start-New-Session -repos $cachedRepos
            } else {
                Write-Host " [!] No repositories found. check connection." -ForegroundColor Red
                Start-Sleep 2
            }
        }
        "3" { if ($global:globalSessionId) { Start-Chat-Loop } else { Write-Host " [!] No active session." -ForegroundColor Red; Start-Sleep 1 } }
        "4" { Restore-Session }
        "Q" { exit }
        "q" { exit }
    }
}