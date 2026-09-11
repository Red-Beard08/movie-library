$ErrorActionPreference = 'Stop'
$vault = 'C:\Users\Corthon\iCloud\iCloudDrive\iCloud~md~obsidian\Red-Beard'
$mediaRoot = Join-Path $vault 'Movie Library\Media'
$settingsPath = Join-Path $vault '.obsidian\plugins\movie-library\data.json'
$backupParent = Join-Path $vault 'Movie Library\.movie-library-migration-backups'
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$rawKey = [string]$settings.omdbKey
if ($rawKey -match 'apikey=([^&\s]+)') { $apiKey = $Matches[1] } else { $apiKey = $rawKey.Trim() }
if (!$apiKey) { throw 'Movie Library does not have an OMDb API key configured.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $backupParent "poster-refresh-$stamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

function ReadField([string]$content, [string]$name) { $pattern = '(?m)^' + [regex]::Escape($name) + ':\s*"?([^"\r\n]*)"?\s*$'; $match = [regex]::Match($content, $pattern); if ($match.Success) { return $match.Groups[1].Value.Trim() }; return '' }
function ReplaceField([string]$content, [string]$name, [string]$value) { $line = "${name}: $value"; $pattern = '(?m)^' + [regex]::Escape($name) + ':\s*.*$'; if ([regex]::IsMatch($content, $pattern)) { return [regex]::Replace($content, $pattern, $line, 1) }; return $content }
function Json([object]$value) { return ($value | ConvertTo-Json -Compress) }

$candidates = @()
Get-ChildItem -LiteralPath $mediaRoot -Filter '*.md' -File | ForEach-Object {
  $content = [IO.File]::ReadAllText($_.FullName)
  if ($content -notmatch '(?m)^type:\s*movie-library-media\s*$') { return }
  if (ReadField $content 'poster_url') { return }
  $candidates += [pscustomobject]@{ Path = $_.FullName; Content = $content; Title = ReadField $content 'title'; Year = ReadField $content 'year'; Imdb = ReadField $content 'imdb_id' }
}
Write-Output "Poster refresh candidates: $($candidates.Count)"
$journal = @(); $unresolved = @()
foreach ($item in $candidates) {
  if (!$item.Title) { $unresolved += "$($item.Path) (missing title)"; continue }
  $query = if ($item.Imdb -match '^tt\d+$') { "i=$([uri]::EscapeDataString($item.Imdb))" } else { "t=$([uri]::EscapeDataString($item.Title))&y=$([uri]::EscapeDataString($item.Year))" }
  try { $result = Invoke-RestMethod -Uri "https://www.omdbapi.com/?apikey=$([uri]::EscapeDataString($apiKey))&$query" -TimeoutSec 25; if ([string]$result.Response -eq 'False' -or !$result.Poster -or $result.Poster -eq 'N/A') { $unresolved += "$($item.Title) ($($result.Error ?? 'no poster'))"; continue } } catch { $unresolved += "$($item.Title) ($($_.Exception.Message))"; continue }
  $backupName = ([IO.Path]::GetFileNameWithoutExtension($item.Path) -replace '[\\/:*?"<>|]', '-') + '.md'
  $backup = Join-Path $backupRoot $backupName
  Copy-Item -LiteralPath $item.Path -Destination $backup -Force
  $next = ReplaceField $item.Content 'poster_url' (Json ([string]$result.Poster))
  $next = ReplaceField $next 'updated' ((Get-Date).ToString('yyyy-MM-ddTHH:mm'))
  [IO.File]::WriteAllText($item.Path, $next, [Text.UTF8Encoding]::new($false))
  $journal += [pscustomobject]@{ path = $item.Path; backup = $backup; imdb = [string]$result.imdbID; source_hash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash }
  Start-Sleep -Milliseconds 150
}
$journal | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupRoot 'poster-refresh-journal.json') -Encoding utf8
if ($unresolved.Count) { $unresolved | Set-Content -LiteralPath (Join-Path $backupRoot 'unresolved.txt') -Encoding utf8 }
Write-Output "Poster refresh complete: $($journal.Count) updated; $($unresolved.Count) unresolved. Backup: $backupRoot"
