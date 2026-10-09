# InGe+ DELTA installer. Run from extracted ZIP; no Git installation required.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath,[switch]$CheckOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $ProjectPath).Path.TrimEnd('\')
$data=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$plan=@()
$errors=@()
foreach($f in @($data.changes)){
    $rel=[string]$f.path
    if(!$rel -or $rel.StartsWith('/') -or $rel.Contains('\') -or $rel.Contains(':') -or
       @(($rel -split '/') | Where-Object {$_ -in @('','.','..')}).Count -gt 0 -or
       $rel -eq '.git' -or $rel.StartsWith('.git/')) {throw "Unsafe path: $rel"}
    $native=$rel.Replace('/','\')
    $target=Join-Path $root $native
    if(!$target.StartsWith($root+'\', [StringComparison]::OrdinalIgnoreCase)){throw "Unsafe target: $rel"}
    $parent=Split-Path -Parent $target
    while($parent -and $parent.Length -ge $root.Length){
        if(Test-Path -LiteralPath $parent){
            if(((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw "Symlink/junction in path: $parent"
            }
        }
        if($parent -eq $root){break}
        $parent=Split-Path -Parent $parent
    }
    $exists=Test-Path -LiteralPath $target
    if($exists -and !(Test-Path -LiteralPath $target -PathType Leaf)) { $errors+= "Not a file: $rel"; continue }
    if($exists -and (((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){throw "Symlink: $rel"}
    $now=if($exists){(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()}else{''}
    $old=[string]$f.before_sha256
    $new=[string]$f.after_sha256
    $done=if($f.operation -eq 'delete'){!$exists}else{$exists -and $now -eq $new}
    $source=Join-Path (Join-Path $PSScriptRoot 'files') $native
    if(!$done){
        if($old -ne $now){$errors+="Local file diverged from base: $rel"}
        elseif($f.operation -ne 'delete'){
            if(!(Test-Path -LiteralPath $source -PathType Leaf)){$errors+="Missing from ZIP: $rel"}
            elseif((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $new){
                $errors+="Corrupt ZIP content: $rel"
            }
        }
    }
    $plan+= [pscustomobject]@{Rel=$native;Target=$target;Source=$source;Op=$f.operation;Done=$done;Exists=$exists}
}
if($errors.Count -gt 0){
    Write-Warning 'DELTA NOT APPLIED: local changes would be overwritten or ZIP is incomplete.'
    $errors | ForEach-Object {Write-Warning $_}
    exit 2
}
$todo=@($plan | Where-Object {!$_.Done})
Write-Host "Preflight OK: $($plan.Count) entries, $($todo.Count) pending."
if($CheckOnly){Write-Host 'Check-only: nothing changed.';exit 0}
if($todo.Count -eq 0){Write-Host 'Already applied.';exit 0}
$backup=Join-Path (Split-Path $root -Parent) ('_InGePlus_DELTA_backup_'+$data.head_commit.Substring(0,12)+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach($f in $todo){
    if($f.Exists){
        $copy=Join-Path $backup $f.Rel
        New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $f.Target -Destination $copy -Force
    }
}
foreach($f in $todo){
    if($f.Op -eq 'delete'){Remove-Item -LiteralPath $f.Target -Force}
    else{
        New-Item -ItemType Directory -Path (Split-Path $f.Target -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $f.Source -Destination $f.Target -Force
    }
}
Write-Host "DELTA applied ($($todo.Count) files). Backup: $backup"
