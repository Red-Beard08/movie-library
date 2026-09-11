$ErrorActionPreference = 'Stop'
$vault = 'C:\Users\Corthon\iCloud\iCloudDrive\iCloud~md~obsidian\Red-Beard'
$settingsPath = Join-Path $vault '.obsidian\plugins\movie-library\data.json'
$migrationRoot = Join-Path $vault 'Movie Library\.movie-library-migration-backups'
$migration = Get-ChildItem -LiteralPath $migrationRoot -Directory | Where-Object Name -like 'legacy-movies-*' | Sort-Object Name -Descending | Select-Object -First 1
if (!$migration) { throw 'No legacy-movie migration journal was found.' }
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$rawKey = [string]$settings.omdbKey
if ($rawKey -match 'apikey=([^&\s]+)') { $apiKey = $Matches[1] } else { $apiKey = $rawKey.Trim() }
if (!$apiKey) { throw 'Movie Library does not have an OMDb API key configured.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $migrationRoot "omdb-enrichment-$stamp"
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

function Json([object]$value) { return ($value | ConvertTo-Json -Compress) }
function ReadField([string]$content, [string]$name) { $pattern = '(?m)^' + [regex]::Escape($name) + ':\s*"?([^"\r\n]*)"?\s*$'; $match = [regex]::Match($content, $pattern); if ($match.Success) { return $match.Groups[1].Value.Trim() }; return '' }
function ReplaceField([string]$content, [string]$name, [string]$value) { $line = "${name}: $value"; $pattern = '(?m)^' + [regex]::Escape($name) + ':\s*.*$'; if ([regex]::IsMatch($content, $pattern)) { return [regex]::Replace($content, $pattern, $line, 1) }; return $content }
function List([string]$value) { if (!$value -or $value -eq 'N/A') { return @() }; return @($value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$sourceJournal = Get-Content -LiteralPath (Join-Path $migration.FullName 'migration-journal.json') -Raw | ConvertFrom-Json
$journal = @(); $success = 0; $skipped = @()
foreach ($entry in $sourceJournal) {
  $path = [string]$entry.target
  if (!(Test-Path -LiteralPath $path)) { $skipped += "$path (missing)"; continue }
  $content = [IO.File]::ReadAllText($path)
  $imdb = ReadField $content 'imdb_id'; $title = ReadField $content 'title'; $year = ReadField $content 'year'
  $query = if ($imdb -match '^tt\d+$') { "i=$([uri]::EscapeDataString($imdb))" } else { "t=$([uri]::EscapeDataString($title))&y=$([uri]::EscapeDataString($year))" }
  try { $result = Invoke-RestMethod -Uri "https://www.omdbapi.com/?apikey=$([uri]::EscapeDataString($apiKey))&$query&plot=short" -TimeoutSec 25; if ([string]$result.Response -eq 'False' -or !$result.Title) { $skipped += "$title ($($result.Error))"; continue } } catch { $skipped += "$title ($($_.Exception.Message))"; continue }
  $backupName = ([IO.Path]::GetFileNameWithoutExtension($path) -replace '[\\/:*?"<>|]', '-') + '.md'
  Copy-Item -LiteralPath $path -Destination (Join-Path $backupRoot $backupName) -Force
  $next = $content
  $next = ReplaceField $next 'title' (Json ([string]$result.Title))
  $next = ReplaceField $next 'media_type' ($(if ($result.Type -eq 'series') { 'series' } else { 'movie' }))
  $next = ReplaceField $next 'year' (Json ([string]$result.Year))
  $next = ReplaceField $next 'runtime_minutes' ($(if ([string]$result.Runtime -match '(\d+)') { $Matches[1] } else { '' }))
  $next = ReplaceField $next 'genres' (Json @(List ([string]$result.Genre)))
  $next = ReplaceField $next 'director' (Json $(if ($result.Director -eq 'N/A') { '' } else { [string]$result.Director }))
  $next = ReplaceField $next 'cast' (Json @(List $(if ($result.Actors -eq 'N/A') { '' } else { [string]$result.Actors })))
  $next = ReplaceField $next 'imdb_id' (Json $(if ($result.imdbID) { [string]$result.imdbID } else { $imdb }))
  $next = ReplaceField $next 'content_rating' (Json $(if ($result.Rated -eq 'N/A') { '' } else { [string]$result.Rated }))
  $next = ReplaceField $next 'plot' (Json $(if ($result.Plot -eq 'N/A') { '' } else { [string]$result.Plot }))
  $next = ReplaceField $next 'poster_url' (Json $(if ($result.Poster -eq 'N/A') { '' } else { [string]$result.Poster }))
  $next = ReplaceField $next 'updated' ((Get-Date).ToString('yyyy-MM-ddTHH:mm'))
  [IO.File]::WriteAllText($path, $next, [Text.UTF8Encoding]::new($false))
  $journal += [pscustomobject]@{ path = $path; backup = (Join-Path $backupRoot $backupName); imdb = [string]$result.imdbID; source_hash = (Get-FileHash -LiteralPath (Join-Path $backupRoot $backupName) -Algorithm SHA256).Hash }
  $success++; Start-Sleep -Milliseconds 150
}
$journal | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupRoot 'enrichment-journal.json') -Encoding utf8
if ($skipped.Count) { $skipped | Set-Content -LiteralPath (Join-Path $backupRoot 'unresolved.txt') -Encoding utf8 }
Write-Output "OMDb enrichment complete: $success updated; $($skipped.Count) unresolved. Backup: $backupRoot"
