# Defender-Monitor.ps1
# Microsoft Defender Baseline & Real-Time Configuration Monitor
#
# A) Create trusted baseline
# B) Compare current state to baseline and continuously monitor
#
# Read-only: Does NOT modify Microsoft Defender.

Clear-Host

$BaselineFile = ".\defender_baseline.json"

# ============================================================
# GET DEFENDER STATE
# ============================================================

function Get-DefenderState {

    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        $preferences = Get-MpPreference -ErrorAction Stop
    }
    catch {
        throw "Unable to retrieve Microsoft Defender configuration: $($_.Exception.Message)"
    }

    $files = @()
    $folders = @()

    # Defender stores both file and folder exclusions
    # inside ExclusionPath.
    foreach ($path in @($preferences.ExclusionPath)) {

        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        if (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue) {

            $files += $path
        }
        elseif (Test-Path -LiteralPath $path -PathType Container -ErrorAction SilentlyContinue) {

            $folders += $path
        }
        else {

            # Attempt to classify exclusions whose target
            # currently does not exist.

            if ($path.EndsWith("\") -or $path.EndsWith("/")) {

                $folders += $path
            }
            elseif ([System.IO.Path]::GetExtension($path)) {

                $files += $path
            }
            else {

                $folders += $path
            }
        }
    }

    $fileTypes = @(
        $preferences.ExclusionExtension |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }
    )

    $processes = @(
        $preferences.ExclusionProcess |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }
    )

    # Cloud-delivered protection
    $cloudProtection = (
        $preferences.MAPSReporting -ne 0
    )

    # Automatic sample submission
    $sampleSubmission = (
        $preferences.SubmitSamplesConsent -eq 1 -or
        $preferences.SubmitSamplesConsent -eq 3
    )

    return [PSCustomObject]@{

        Created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        RealTimeProtection = [bool]$status.RealTimeProtectionEnabled
        CloudProtection    = [bool]$cloudProtection
        SampleSubmission   = [bool]$sampleSubmission
        TamperProtection   = [bool]$status.IsTamperProtected

        Files     = @($files)
        Folders   = @($folders)
        FileTypes = @($fileTypes)
        Processes = @($processes)
    }
}


# ============================================================
# DISPLAY PROTECTION STATE
# ============================================================

function Show-ProtectionState {

    param(
        [string]$Name,
        [bool]$Enabled
    )

    Write-Host ("{0,-32}: " -f $Name) -NoNewline

    if ($Enabled) {

        Write-Host "ENABLED" -ForegroundColor Green
    }
    else {

        Write-Host "DISABLED" -ForegroundColor Red
    }
}


# ============================================================
# DISPLAY EXCLUSIONS
# ============================================================

function Show-Exclusions {

    param(
        [string]$Title,
        $Items
    )

    Write-Host "`n[ $Title ]" -ForegroundColor Yellow

    if (@($Items).Count -eq 0) {

        Write-Host "  None" -ForegroundColor Green
        return
    }

    foreach ($item in @($Items)) {

        Write-Host "  [!] $item" -ForegroundColor Red
    }
}


# ============================================================
# SECURITY ALERT
# ============================================================

function Write-SecurityAlert {

    param(
        [string]$Message
    )

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "                  SECURITY ALERT                     " -ForegroundColor Red
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "[$time] $Message" -ForegroundColor Red
    Write-Host ""
}


# ============================================================
# RESTORED MESSAGE
# ============================================================

function Write-Restored {

    param(
        [string]$Message
    )

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host "[$time] [+] $Message" -ForegroundColor Green
}


# ============================================================
# MENU
# ============================================================

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "       WINDOWS DEFENDER SECURITY MONITOR"             -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "What would you like to do?"
Write-Host ""
Write-Host "    A) Create new Defender baseline"
Write-Host "    B) Monitor Defender using saved baseline"
Write-Host ""

$response = Read-Host "Please enter 'A' or 'B'"

Write-Host ""


# ============================================================
# OPTION A
# CREATE BASELINE
# ============================================================

if ($response -eq "A") {

    Write-Host "[*] Collecting Microsoft Defender configuration..." `
        -ForegroundColor Yellow

    try {

        $baseline = Get-DefenderState
    }
    catch {

        Write-Host "`n[ERROR] $_" -ForegroundColor Red
        exit 1
    }

    # --------------------------------------------------------
    # Show protection status
    # --------------------------------------------------------

    Write-Host "`n[ PROTECTION STATUS ]" -ForegroundColor Yellow
    Write-Host ""

    Show-ProtectionState `
        "Real-Time Protection" `
        $baseline.RealTimeProtection

    Show-ProtectionState `
        "Cloud-Delivered Protection" `
        $baseline.CloudProtection

    Show-ProtectionState `
        "Automatic Sample Submission" `
        $baseline.SampleSubmission

    Show-ProtectionState `
        "Tamper Protection" `
        $baseline.TamperProtection


    # --------------------------------------------------------
    # Show exclusions
    # --------------------------------------------------------

    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "                 DEFENDER EXCLUSIONS"                -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    Show-Exclusions "EXCLUDED FILES" `
        $baseline.Files

    Show-Exclusions "EXCLUDED FOLDERS" `
        $baseline.Folders

    Show-Exclusions "EXCLUDED FILE TYPES" `
        $baseline.FileTypes

    Show-Exclusions "EXCLUDED PROCESSES" `
        $baseline.Processes


    # --------------------------------------------------------
    # Save baseline
    # --------------------------------------------------------

    try {

        $baseline |
            ConvertTo-Json -Depth 5 |
            Set-Content -Path $BaselineFile -Encoding UTF8
    }
    catch {

        Write-Host "`n[ERROR] Unable to save baseline." `
            -ForegroundColor Red

        exit 1
    }

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "                   BASELINE CREATED"                  -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "[+] Defender baseline successfully created." `
        -ForegroundColor Green

    Write-Host "[+] Baseline saved to: $BaselineFile" `
        -ForegroundColor Green

    Write-Host ""
}


# ============================================================
# OPTION B
# MONITOR AGAINST BASELINE
# ============================================================

elseif ($response -eq "B") {

    # --------------------------------------------------------
    # Check for baseline
    # --------------------------------------------------------

    if (-not (Test-Path $BaselineFile)) {

        Write-Host "[ERROR] No Defender baseline exists." `
            -ForegroundColor Red

        Write-Host ""
        Write-Host "Run the script again and select:" `
            -ForegroundColor Yellow

        Write-Host "A) Create new Defender baseline" `
            -ForegroundColor Yellow

        Write-Host ""

        exit 1
    }


    # --------------------------------------------------------
    # Load baseline
    # --------------------------------------------------------

    try {

        $baseline = Get-Content $BaselineFile -Raw |
            ConvertFrom-Json
    }
    catch {

        Write-Host "[ERROR] Unable to read Defender baseline." `
            -ForegroundColor Red

        exit 1
    }


    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "                   BASELINE LOADED"                   -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "[+] Baseline created: $($baseline.Created)" `
        -ForegroundColor Green


    # ========================================================
    # GET CURRENT STATE BEFORE MONITORING
    # ========================================================

    try {

        $current = Get-DefenderState
    }
    catch {

        Write-Host "[ERROR] Unable to retrieve current Defender state." `
            -ForegroundColor Red

        exit 1
    }


    Write-Host ""
    Write-Host "[*] Comparing current configuration to baseline..." `
        -ForegroundColor Yellow

    $differencesFound = $false


    # ========================================================
    # INITIAL PROTECTION COMPARISON
    # ========================================================

    if ($current.RealTimeProtection -ne $baseline.RealTimeProtection) {

        $differencesFound = $true

        Write-SecurityAlert `
            "REAL-TIME PROTECTION DOES NOT MATCH BASELINE"
    }


    if ($current.CloudProtection -ne $baseline.CloudProtection) {

        $differencesFound = $true

        Write-SecurityAlert `
            "CLOUD-DELIVERED PROTECTION DOES NOT MATCH BASELINE"
    }


    if ($current.SampleSubmission -ne $baseline.SampleSubmission) {

        $differencesFound = $true

        Write-SecurityAlert `
            "AUTOMATIC SAMPLE SUBMISSION DOES NOT MATCH BASELINE"
    }


    if ($current.TamperProtection -ne $baseline.TamperProtection) {

        $differencesFound = $true

        Write-SecurityAlert `
            "TAMPER PROTECTION DOES NOT MATCH BASELINE"
    }


    # ========================================================
    # INITIAL EXCLUSION COMPARISON
    # ========================================================

    foreach ($item in @($current.Files)) {

        if ($item -notin @($baseline.Files)) {

            $differencesFound = $true

            Write-SecurityAlert `
                "FILE EXCLUSION NOT IN BASELINE: $item"
        }
    }


    foreach ($item in @($current.Folders)) {

        if ($item -notin @($baseline.Folders)) {

            $differencesFound = $true

            Write-SecurityAlert `
                "FOLDER EXCLUSION NOT IN BASELINE: $item"
        }
    }


    foreach ($item in @($current.FileTypes)) {

        if ($item -notin @($baseline.FileTypes)) {

            $differencesFound = $true

            Write-SecurityAlert `
                "FILE TYPE EXCLUSION NOT IN BASELINE: $item"
        }
    }


    foreach ($item in @($current.Processes)) {

        if ($item -notin @($baseline.Processes)) {

            $differencesFound = $true

            Write-SecurityAlert `
                "PROCESS EXCLUSION NOT IN BASELINE: $item"
        }
    }


    # --------------------------------------------------------
    # Clean baseline
    # --------------------------------------------------------

    if (-not $differencesFound) {

        Write-Host ""
        Write-Host "[+] Current Defender configuration matches baseline." `
            -ForegroundColor Green
    }


    # ========================================================
    # BEGIN MONITORING
    # ========================================================

    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "                   LIVE MONITOR"                     -ForegroundColor Cyan
    Write-Host "=====================================================" -ForegroundColor Cyan

    Write-Host ""
    Write-Host "[+] Monitoring Defender for changes..." `
        -ForegroundColor Green

    Write-Host "[+] Press CTRL+C to stop monitoring." `
        -ForegroundColor DarkGray

    Write-Host ""


    # Current state becomes the initial observed state.
    #
    # IMPORTANT:
    # This does NOT replace the saved baseline.
    $lastState = $current


    # ========================================================
    # LIVE MONITORING LOOP
    # ========================================================

    while ($true) {

        Start-Sleep -Seconds 1

        try {

            $current = Get-DefenderState
        }
        catch {

            Write-Host "[!] Unable to query Defender. Retrying..." `
                -ForegroundColor Yellow

            continue
        }


        # ====================================================
        # REAL-TIME PROTECTION
        # ====================================================

        if (
            $current.RealTimeProtection -ne
            $lastState.RealTimeProtection
        ) {

            if ($current.RealTimeProtection -eq $baseline.RealTimeProtection) {

                Write-Restored `
                    "Real-Time Protection restored to baseline: ENABLED"
            }
            else {

                Write-SecurityAlert `
                    "REAL-TIME PROTECTION CHANGED: ENABLED -> DISABLED"
            }
        }


        # ====================================================
        # CLOUD PROTECTION
        # ====================================================

        if (
            $current.CloudProtection -ne
            $lastState.CloudProtection
        ) {

            if ($current.CloudProtection -eq $baseline.CloudProtection) {

                Write-Restored `
                    "Cloud-Delivered Protection restored to baseline: ENABLED"
            }
            else {

                Write-SecurityAlert `
                    "CLOUD-DELIVERED PROTECTION CHANGED: ENABLED -> DISABLED"
            }
        }


        # ====================================================
        # SAMPLE SUBMISSION
        # ====================================================

        if (
            $current.SampleSubmission -ne
            $lastState.SampleSubmission
        ) {

            if ($current.SampleSubmission -eq $baseline.SampleSubmission) {

                Write-Restored `
                    "Automatic Sample Submission restored to baseline: ENABLED"
            }
            else {

                Write-SecurityAlert `
                    "AUTOMATIC SAMPLE SUBMISSION CHANGED: ENABLED -> DISABLED"
            }
        }


        # ====================================================
        # TAMPER PROTECTION
        # ====================================================

        if (
            $current.TamperProtection -ne
            $lastState.TamperProtection
        ) {

            if ($current.TamperProtection -eq $baseline.TamperProtection) {

                Write-Restored `
                    "Tamper Protection restored to baseline: ENABLED"
            }
            else {

                Write-SecurityAlert `
                    "TAMPER PROTECTION CHANGED: ENABLED -> DISABLED"
            }
        }


        # ====================================================
        # NEW FILE EXCLUSIONS
        # ====================================================

        foreach ($item in @($current.Files)) {

            if (
                $item -notin @($lastState.Files)
            ) {

                if ($item -notin @($baseline.Files)) {

                    Write-SecurityAlert `
                        "NEW FILE EXCLUSION ADDED: $item"
                }
            }
        }


        # ====================================================
        # NEW FOLDER EXCLUSIONS
        # ====================================================

        foreach ($item in @($current.Folders)) {

            if (
                $item -notin @($lastState.Folders)
            ) {

                if ($item -notin @($baseline.Folders)) {

                    Write-SecurityAlert `
                        "NEW FOLDER EXCLUSION ADDED: $item"
                }
            }
        }


        # ====================================================
        # NEW FILE TYPE EXCLUSIONS
        # ====================================================

        foreach ($item in @($current.FileTypes)) {

            if (
                $item -notin @($lastState.FileTypes)
            ) {

                if ($item -notin @($baseline.FileTypes)) {

                    Write-SecurityAlert `
                        "NEW FILE TYPE EXCLUSION ADDED: $item"
                }
            }
        }


        # ====================================================
        # NEW PROCESS EXCLUSIONS
        # ====================================================

        foreach ($item in @($current.Processes)) {

            if (
                $item -notin @($lastState.Processes)
            ) {

                if ($item -notin @($baseline.Processes)) {

                    Write-SecurityAlert `
                        "NEW PROCESS EXCLUSION ADDED: $item"
                }
            }
        }


        # ====================================================
        # REMOVED FILE EXCLUSIONS
        # ====================================================

        foreach ($item in @($lastState.Files)) {

            if ($item -notin @($current.Files)) {

                if ($item -notin @($baseline.Files)) {

                    Write-Restored `
                        "Unauthorized file exclusion removed: $item"
                }
            }
        }


        # ====================================================
        # REMOVED FOLDER EXCLUSIONS
        # ====================================================

        foreach ($item in @($lastState.Folders)) {

            if ($item -notin @($current.Folders)) {

                if ($item -notin @($baseline.Folders)) {

                    Write-Restored `
                        "Unauthorized folder exclusion removed: $item"
                }
            }
        }


        # ====================================================
        # REMOVED FILE TYPE EXCLUSIONS
        # ====================================================

        foreach ($item in @($lastState.FileTypes)) {

            if ($item -notin @($current.FileTypes)) {

                if ($item -notin @($baseline.FileTypes)) {

                    Write-Restored `
                        "Unauthorized file type exclusion removed: $item"
                }
            }
        }


        # ====================================================
        # REMOVED PROCESS EXCLUSIONS
        # ====================================================

        foreach ($item in @($lastState.Processes)) {

            if ($item -notin @($current.Processes)) {

                if ($item -notin @($baseline.Processes)) {

                    Write-Restored `
                        "Unauthorized process exclusion removed: $item"
                }
            }
        }


        # ====================================================
        # UPDATE OBSERVED STATE
        # ====================================================

        $lastState = $current

        # defender_baseline.json is NEVER changed here.
    }
}


# ============================================================
# INVALID INPUT
# ============================================================

else {

    Write-Host "[ERROR] Invalid selection." -ForegroundColor Red
    Write-Host "Please run the script again and enter A or B."
    Write-Host ""
}