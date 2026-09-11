$ErrorActionPreference = 'Stop'
$vault = 'C:\Users\Corthon\iCloud\iCloudDrive\iCloud~md~obsidian\Red-Beard'
$mediaRoot = Join-Path $vault 'Movie Library\Media'
$backupParent = Join-Path $vault 'Movie Library\.movie-library-migration-backups'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $backupParent "series-classification-$stamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

$corrections = @{
  '1917 (2019).md' = @{ type = 'series'; title = '1917' }
  'All Creatures Great & Small (2020) (2020).md' = @{ type = 'series'; title = 'All Creatures Great & Small' }
  'Lewis and Clark- The Journey of the Corps of Discovery (1997).md' = @{ type = 'series'; title = 'Lewis and Clark: The Journey of the Corps of Discovery' }
  'Little House on the Prairie (2026) (2026).md' = @{ type = 'series'; title = 'Little House on the Prairie' }
  'Lost in Space (2018) (2018).md' = @{ type = 'series'; title = 'Lost in Space' }
  'SAS Rogue Heroes (2022).md' = @{ type = 'series'; title = 'SAS Rogue Heroes' }
  'Yellowstone (2018) (2018).md' = @{ type = 'series'; title = 'Yellowstone' }
}
function ReplaceField([string]$content, [string]$name, [string]$value) { $pattern = '(?m)^' + [regex]::Escape($name) + ':\s*.*$'; $line = "${name}: $value"; return [regex]::Replace($content, $pattern, $line, 1) }
$journal = @()
foreach ($name in $corrections.Keys) {
  $path = Join-Path $mediaRoot $name
  if (!(Test-Path -LiteralPath $path)) { throw "Expected record is missing: $name" }
  $backup = Join-Path $backupRoot $name
  Copy-Item -LiteralPath $path -Destination $backup -Force
  $content = [IO.File]::ReadAllText($path)
  $next = ReplaceField $content 'media_type' $corrections[$name].type
  $next = ReplaceField $next 'title' ($corrections[$name].title | ConvertTo-Json -Compress)
  $next = ReplaceField $next 'updated' ((Get-Date).ToString('yyyy-MM-ddTHH:mm'))
  [IO.File]::WriteAllText($path, $next, [Text.UTF8Encoding]::new($false))
  $journal += [pscustomobject]@{ path = $path; backup = $backup; source_hash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash }
}
$journal | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupRoot 'correction-journal.json') -Encoding utf8
Write-Output "Corrected $($journal.Count) series records. Backup: $backupRoot"
