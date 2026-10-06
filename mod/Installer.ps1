# Batomon Pokemon-mod installer. Copies the mod into <game>\mods\batomon-mod and writes
# override.cfg next to the game exe, which makes Godot load loader.gd at startup.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ExeName = "batomon_showdown.exe"
$ModName = "batomon-mod"
$PackageDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Find-GameDir {
    $candidates = @()
    foreach ($key in @("HKCU:\Software\Valve\Steam", "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam", "HKLM:\SOFTWARE\Valve\Steam")) {
        $p = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)
        foreach ($v in @($p.SteamPath, $p.InstallPath)) { if ($v) { $candidates += $v } }
    }
    $libraries = @()
    foreach ($steam in ($candidates | Select-Object -Unique)) {
        $libraries += $steam
        $vdf = Join-Path $steam "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries += $m.Groups[1].Value -replace '\\\\', '\'
            }
        }
    }
    foreach ($lib in ($libraries | Select-Object -Unique)) {
        $dir = Join-Path $lib "steamapps\common\Batomon Showdown"
        if (Test-Path (Join-Path $dir $ExeName)) { return $dir }
    }
    # the package may already sit in <game>\mods\batomon-mod
    $up = Split-Path -Parent (Split-Path -Parent $PackageDir)
    if ($up -and (Test-Path (Join-Path $up $ExeName))) { return $up }
    return ""
}

function Get-ModDir($game) { Join-Path (Join-Path $game "mods") $ModName }
function Get-Override($game) { Join-Path $game "override.cfg" }

function Test-Installed($game) {
    $cfg = Get-Override $game
    if (-not (Test-Path $cfg)) { return $false }
    return (Get-Content $cfg -Raw) -match "BatomonMod="
}

function Count-Files($dir, $patterns) {
    if (-not (Test-Path $dir)) { return 0 }
    return @(Get-ChildItem -Path $dir -File -Include $patterns -Recurse -ErrorAction SilentlyContinue).Count
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Batomon Pokemon-mod installer"
$form.Size = New-Object System.Drawing.Size(560, 330)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Batomon Showdown game folder:"
$lblPath.Location = New-Object System.Drawing.Point(16, 16)
$lblPath.AutoSize = $true
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Location = New-Object System.Drawing.Point(16, 38)
$txtPath.Size = New-Object System.Drawing.Size(420, 24)
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(444, 36)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($btnBrowse)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(16, 76)
$lblStatus.Size = New-Object System.Drawing.Size(520, 90)
$form.Controls.Add($lblStatus)

$chkRemove = New-Object System.Windows.Forms.CheckBox
$chkRemove.Text = "When uninstalling, also delete the mod folder with sprites, cries and music"
$chkRemove.Location = New-Object System.Drawing.Point(16, 172)
$chkRemove.AutoSize = $true
$form.Controls.Add($chkRemove)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "Install"
$btnInstall.Location = New-Object System.Drawing.Point(16, 210)
$btnInstall.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($btnInstall)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text = "Uninstall"
$btnUninstall.Location = New-Object System.Drawing.Point(146, 210)
$btnUninstall.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($btnUninstall)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open mod folder"
$btnOpen.Location = New-Object System.Drawing.Point(276, 210)
$btnOpen.Size = New-Object System.Drawing.Size(130, 34)
$form.Controls.Add($btnOpen)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = "Close"
$btnClose.Location = New-Object System.Drawing.Point(414, 210)
$btnClose.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($btnClose)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Put your own sprites, cries and music in the mod folder, see README.md."
$lblHint.Location = New-Object System.Drawing.Point(16, 258)
$lblHint.AutoSize = $true
$lblHint.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblHint)

function Update-Status {
    $game = $txtPath.Text.Trim()
    if (-not $game -or -not (Test-Path (Join-Path $game $ExeName))) {
        $lblStatus.Text = "Batomon Showdown was not found in this folder. Pick the folder that contains $ExeName."
        $btnInstall.Enabled = $false; $btnUninstall.Enabled = $false; $btnOpen.Enabled = $false
        return
    }
    $mod = Get-ModDir $game
    $installed = Test-Installed $game
    $sprites = Count-Files (Join-Path $mod "sprites") @("*.png")
    $cries = Count-Files (Join-Path $mod "cries") @("*.ogg", "*.mp3", "*.wav")
    $music = Count-Files (Join-Path $mod "music") @("*.ogg", "*.mp3", "*.wav")
    $state = if ($installed) { "Installed and active." } elseif (Test-Path $mod) { "The mod files are there, but the mod is disabled." } else { "Not installed." }
    $lblStatus.Text = "$state`r`n`r`nSprites: $sprites   Cries: $cries   Music: $music"
    $btnInstall.Enabled = $true
    $btnInstall.Text = if ($installed) { "Reinstall" } else { "Install" }
    $btnUninstall.Enabled = $installed -or (Test-Path $mod)
    $btnOpen.Enabled = Test-Path $mod
}

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Pick the folder that contains $ExeName"
    if ($txtPath.Text) { $dlg.SelectedPath = $txtPath.Text }
    if ($dlg.ShowDialog() -eq "OK") { $txtPath.Text = $dlg.SelectedPath; Update-Status }
})
$txtPath.Add_TextChanged({ Update-Status })

$btnInstall.Add_Click({
    $game = $txtPath.Text.Trim()
    $mod = Get-ModDir $game
    try {
        $samePlace = (Resolve-Path $PackageDir).Path.TrimEnd('\') -eq ([System.IO.Path]::GetFullPath($mod)).TrimEnd('\')
        if (-not $samePlace) {
            New-Item -ItemType Directory -Force -Path $mod | Out-Null
            # copy the package over it; files the user added themselves stay
            Get-ChildItem -Path $PackageDir -Force | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $mod -Recurse -Force
            }
        }
        $cfg = Get-Override $game
        if ((Test-Path $cfg) -and -not (Test-Installed $game)) { Copy-Item $cfg "$cfg.bak" -Force }
        $loader = (Join-Path $mod "loader.gd") -replace '\\', '/'
        $text = "[autoload]`r`n`r`nBatomonMod=`"*$loader`"`r`n"
        [System.IO.File]::WriteAllText($cfg, $text, (New-Object System.Text.UTF8Encoding($false)))
        [System.Windows.Forms.MessageBox]::Show("The mod is installed. Start the game through Steam.", "Done") | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Installing failed: $($_.Exception.Message)", "Error") | Out-Null
    }
    Update-Status
})

$btnUninstall.Add_Click({
    $game = $txtPath.Text.Trim()
    $cfg = Get-Override $game
    try {
        if (Test-Installed $game) { Remove-Item $cfg -Force }
        if (Test-Path "$cfg.bak") { Move-Item "$cfg.bak" $cfg -Force }
        if ($chkRemove.Checked) {
            $mod = Get-ModDir $game
            $inside = (Resolve-Path $PackageDir).Path.StartsWith([System.IO.Path]::GetFullPath($mod))
            if ($inside) {
                [System.Windows.Forms.MessageBox]::Show("The installer is running from inside the mod folder, so that folder is kept. The mod is disabled.", "Note") | Out-Null
            } elseif (Test-Path $mod) { Remove-Item $mod -Recurse -Force }
        }
        [System.Windows.Forms.MessageBox]::Show("The mod is disabled.", "Done") | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Uninstalling failed: $($_.Exception.Message)", "Error") | Out-Null
    }
    Update-Status
})

$btnOpen.Add_Click({ Start-Process explorer.exe (Get-ModDir $txtPath.Text.Trim()) })
$btnClose.Add_Click({ $form.Close() })

$txtPath.Text = Find-GameDir
Update-Status
[void]$form.ShowDialog()
