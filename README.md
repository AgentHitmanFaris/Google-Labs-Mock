# Jules AI CLI Client

A PowerShell-based command-line interface for interacting with the Jules AI Agent. This tool allows developers to manage sessions, sync repositories, and interact with the AI to perform tasks on their codebase.

## Features

*   **Sync Repositories**: Fetch and list available repositories from the Jules AI service.
*   **Start New Session**: Initiate a new AI session with a specific repository and branch.
    *   **Interactive Mode**: Discuss goals with the agent before it starts planning.
    *   **Review Mode**: Standard mode where the agent proposes a plan for your approval.
    *   **Start Mode**: Authorize the agent to start working immediately.
*   **Live Chat**: Interact with the agent in real-time, view proposed plans, approve actions, and see code changes/terminal output.
*   **Restore Session**: Resume previous sessions from the history.

## Prerequisites

*   PowerShell (v5.1 or Core 7+)
*   A valid Google Cloud API Key with access to the Jules AI API.

## Configuration

1.  Open `jules_test.ps1` in a text editor.
2.  Locate the `$apiKey` variable at the top of the file.
3.  Replace the placeholder or existing key with your valid API key.

    ```powershell
    $apiKey = "YOUR_ACTUAL_API_KEY_HERE"
    ```

## Usage

Run the script from a PowerShell terminal:

```powershell
.\jules_test.ps1
```

### Main Menu Options

1.  **SYNC REPOS**: connect to the API and retrieve the list of repositories you have access to. You must do this before starting a new session.
2.  **START NEW SESSION**: Select a repository and branch, then choose an interaction mode and provide instructions to start a new task.
3.  **RESUME CHAT**: Re-enter the chat loop for the currently active session.
6.  **RESTORE RECENT SESSION**: Fetch a list of past sessions and choose one to resume.
Q.  **QUIT**: Exit the application.

## Interaction Modes

When starting a new session, you can choose:
*   **[1] Interactive**: "I want to have an interactive conversation to clarify requirements."
*   **[2] Review** (Default): "Generate a plan, wait for approval."
*   **[3] Start**: "Start working immediately. Do not wait for plan approval."
