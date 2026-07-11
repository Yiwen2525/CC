# Upload MemScan to GitHub (run after installing Git for Windows)
# https://git-scm.com/download/win

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git is not installed. Download: https://git-scm.com/download/win" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path ".git")) {
    git init
}

git add .
git status

$msg = "Update MemScan project"
git commit -m $msg 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Nothing new to commit, or commit failed." -ForegroundColor Yellow
}

$remote = git remote get-url origin 2>$null
if (-not $remote) {
    git remote add origin https://github.com/Yiwen2525/CC.git
}

Write-Host ""
Write-Host "Pushing to GitHub..." -ForegroundColor Cyan
git branch -M main
git pull origin main --allow-unrelated-histories --no-edit 2>$null
git push -u origin main

Write-Host ""
Write-Host "Done. Open Actions and run iOS Build workflow." -ForegroundColor Green
