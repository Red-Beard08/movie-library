param(
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$vault = 'C:\Users\Corthon\iCloud\iCloudDrive\iCloud~md~obsidian\Red-Beard'
$legacyRoot = Join-Path $vault 'Collections\Movies'
$mediaRoot = Join-Path $vault 'Movie Library\Media'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $vault "Movie Library\.movie-library-migration-backups\legacy-movies-$stamp"

function CleanValue([object]$value) {
  if ($null -eq $value) { return '' }
  $text = [string]$value
  $text = $text.Trim().Trim('"').Trim("'")
  if ($text -match '^\[\[(.+?)(?:\|(.+?))?\]\]$') { $text = if ($Matches[2]) { $Matches[2] } else { $Matches[1].Split('/')[-1] } }
  return $text.Trim()
}

function Bool([object]$value) { return (CleanValue $value).ToLowerInvariant() -eq 'true' }
function NumberOrNull([object]$value) { $text = CleanValue $value; $number = 0.0; if ($text -and [double]::TryParse($text, [ref]$number) -and $number -gt 0) { return $number }; return $null }
function Values([object]$value) { if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { return @($value | ForEach-Object { CleanValue $_ } | Where-Object { $_ }) }; $text = CleanValue $value; if (!$text) { return @() }; return @($text -split ',' | ForEach-Object { CleanValue $_ } | Where-Object { $_ }) }
function Unique([array]$values) { $seen = @{}; return @($values | Where-Object { $_ -and !$seen.ContainsKey($_.ToLowerInvariant()) } | ForEach-Object { $seen[$_.ToLowerInvariant()] = $true; $_ }) }
function Quote([object]$value) { return ($value | ConvertTo-Json -Compress) }
function Timestamp([string]$value) { $text = (CleanValue $value) -replace '_', 'T'; if (!$text) { return (Get-Date).ToString('yyyy-MM-ddTHH:mm') }; if ($text -match '^\d{4}-\d{2}-\d{2}$') { return "$text`T00:00" }; return $text }
function Safe([string]$value) { return (($value -replace '[\\/:*?"<>|#\[\]]', '-') -replace '\s+', ' ').Trim().Substring(0, [Math]::Min(76, (($value -replace '[\\/:*?"<>|#\[\]]', '-') -replace '\s+', ' ').Trim().Length)) }
function StableId([string]$value) { $sha = [System.Security.Cryptography.SHA1]::Create(); $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($value)); return 'MED-' + (($hash | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 8).ToUpperInvariant() }

function ReadFrontmatter([string]$path) {
  $content = [IO.File]::ReadAllText($path)
  $map = @{}; $body = $content
  if ($content -match '(?s)^---\s*\r?\n(.*?)\r?\n---\s*\r?\n?(.*)$') {
    $yaml = $Matches[1]; $body = $Matches[2]
    $current = $null
    foreach ($line in ($yaml -split "`r?`n")) {
      if ($line -match '^\s*-\s*(.*)$' -and $current) { $map[$current] = @($map[$current]) + @(CleanValue $Matches[1]); continue }
      if ($line -match '^([^:#][^:]*):\s*(.*)$') { $current = $Matches[1].Trim(); $value = $Matches[2]; $map[$current] = if ($value) { CleanValue $value } else { @() } }
    }
  }
  return @{ Data = $map; Body = $body }
}

function Render([hashtable]$record, [string]$notes) {
  $family = $record.family
  $yaml = @('---', 'type: movie-library-media', ('media_id: ' + (Quote $record.id)), ('title: ' + (Quote $record.title)), ('media_type: ' + $record.mediaType), ('year: ' + (Quote $record.year)), ('runtime_minutes: ' + $record.runtime), ('genres: ' + (Quote @($record.genres))), ('director: ' + (Quote $record.director)), ('cast: ' + (Quote @($record.cast))), ('imdb_id: ' + (Quote $record.imdbId)), ('content_rating: ' + (Quote $record.contentRating)), ('plot: ' + (Quote $record.plot)), ('poster_url: ' + (Quote $record.posterUrl)), ('plex_thumb_path: ' + (Quote $record.plexThumbPath)), ('plex_rating_key: ' + (Quote $record.plexRatingKey)), ('watched: ' + $record.watched.ToString().ToLowerInvariant()), ('watchlist: ' + $record.watchlist.ToString().ToLowerInvariant()), ('owned: ' + $record.owned.ToString().ToLowerInvariant()), ('favorite: ' + $record.favorite.ToString().ToLowerInvariant()), ('personal_rating: ' + $record.personalRating), ('last_watched: ' + (Quote $record.lastWatched)), 'family:', ('  decision: ' + $family.decision), ('  min_age: ' + (Quote $family.min_age)), ('  violence: ' + $family.violence), ('  sexual_content: ' + $family.sexual_content), ('  language: ' + $family.language), ('  substances: ' + $family.substances), ('  themes: ' + $family.themes), ('  notes: ' + (Quote $family.notes)), ('  prompts: ' + (Quote $family.prompts)), ('created: ' + $record.created), ('updated: ' + $record.updated), '---') -join "`n"
  $runtimeLabel = if ($record.runtime) { $record.runtime.ToString() + ' min' } else { '--' }
  $genreLabel = if ($record.genres.Count) { $record.genres -join ', ' } else { '--' }
  $typeLabel = if ($record.mediaType -eq 'series') { 'Series' } else { 'Movie' }
  $details = @('<!-- movie-library:details:start -->', "## $($record.title)", '', "- Type: $typeLabel", "- Year: $($record.year)", "- Runtime: $runtimeLabel", "- Genres: $genreLabel", "- Family decision: Not reviewed", "- Suggested minimum age: --", '', '## Family guide', '', '- Violence and intensity: Not reviewed', '- Sexual content and nudity: Not reviewed', '- Language: Not reviewed', '- Substances: Not reviewed', '- Themes: Not reviewed', '<!-- movie-library:details:end -->') -join "`n"
  return "$yaml`n`n$details`n`n## Personal notes`n`n$notes`n"
}

$legacy = @(Get-ChildItem -LiteralPath $legacyRoot -File -Filter '*.md')
$targets = @{}
Get-ChildItem -LiteralPath $mediaRoot -File -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object { $parsed = ReadFrontmatter $_.FullName; if ($parsed.Data.type -eq 'movie-library-media') { $targets[$_.FullName] = $parsed } }
$operations = @()
foreach ($file in $legacy) {
  $parsed = ReadFrontmatter $file.FullName; $d = $parsed.Data
  $title = CleanValue $file.BaseName; $year = CleanValue $d.year; $mediaType = if ($year -match '[–—]') { 'series' } else { 'movie' }; $imdb = CleanValue $d.imdbId
  $match = $null
  foreach ($entry in $targets.GetEnumerator()) { $td = $entry.Value.Data; if (($imdb -and (CleanValue $td.imdb_id) -eq $imdb) -or ((CleanValue $td.title).ToLowerInvariant() -eq $title.ToLowerInvariant() -and (CleanValue $td.year) -eq $year -and (CleanValue $td.media_type) -eq $mediaType)) { $match = $entry; break } }
  $operations += [pscustomobject]@{ Source = $file; Parsed = $parsed; Title = $title; Year = $year; MediaType = $mediaType; Imdb = $imdb; Target = $match }
}
$matched = @($operations | Where-Object Target).Count; $new = $operations.Count - $matched
Write-Output "Preview: $($operations.Count) legacy notes; $matched updates; $new new canonical notes."
if (!$Apply) { exit 0 }

New-Item -ItemType Directory -Path (Join-Path $backupRoot 'legacy-source'), (Join-Path $backupRoot 'prior-targets') -Force | Out-Null
$journal = @()
foreach ($operation in $operations) {
  $sourceRelative = $operation.Source.FullName.Substring($legacyRoot.Length).TrimStart('\')
  Copy-Item -LiteralPath $operation.Source.FullName -Destination (Join-Path $backupRoot "legacy-source\$sourceRelative") -Force
  $d = $operation.Parsed.Data; $existing = $null; $targetPath = $null
  if ($operation.Target) { $targetPath = $operation.Target.Key; $existing = $operation.Target.Value; Copy-Item -LiteralPath $targetPath -Destination (Join-Path $backupRoot ('prior-targets\' + [IO.Path]::GetFileName($targetPath))) -Force }
  $td = if ($existing) { $existing.Data } else { @{} }
  $existingNotes = if ($existing) { $existing.Body -replace '(?s)^.*?## Personal notes\s*', '' } else { '' }
  $legacyBody = $operation.Parsed.Body.Trim()
  $legacyNotes = @('### Imported legacy metadata', "- Source: [[Collections/Movies/$($operation.Source.BaseName)]]", $(if (CleanValue $d.scoreImdb) { "- IMDb score: $(CleanValue $d.scoreImdb)" }), $(if (Values $d.Tags) { "- Legacy tags: $((Values $d.Tags) -join ', ')" }), $(if ($legacyBody) { "`n### Legacy note content`n`n$legacyBody" })) | Where-Object { $_ }
  $notes = @($existingNotes.Trim(), ($legacyNotes -join "`n")) | Where-Object { $_ } | Select-Object -Unique
  $legacyRating = NumberOrNull $d.MyRating; $currentRating = NumberOrNull $td.personal_rating
  $runtimeText = CleanValue $d.length; $runtime = if ($runtimeText -match '(\d+)') { [int]$Matches[1] } else { NumberOrNull $td.runtime_minutes }
  $record = @{ id = if (CleanValue $td.media_id) { CleanValue $td.media_id } else { StableId $operation.Source.FullName }; title = $operation.Title; mediaType = $operation.MediaType; year = $operation.Year; runtime = $runtime; genres = Unique @((Values $td.genres) + (Values $d.genre)); director = if (CleanValue $td.director) { CleanValue $td.director } else { (Values $d.director) -join ', ' }; cast = Unique @((Values $td.cast) + (Values $d.cast)); imdbId = if ($operation.Imdb) { $operation.Imdb } else { CleanValue $td.imdb_id }; contentRating = CleanValue $td.content_rating; plot = if (CleanValue $d.plot) { CleanValue $d.plot } else { CleanValue $td.plot }; posterUrl = if (CleanValue $d.poster) { CleanValue $d.poster } else { CleanValue $td.poster_url }; plexThumbPath = CleanValue $td.plex_thumb_path; plexRatingKey = CleanValue $td.plex_rating_key; watched = (Bool $d.watched) -or (Bool $td.watched); watchlist = (Bool $d.watchlist) -or (Bool $td.watchlist); owned = (Bool $d.owned) -or (Bool $td.owned); favorite = Bool $td.favorite; personalRating = if ($legacyRating) { $legacyRating } else { $currentRating }; lastWatched = CleanValue $td.last_watched; created = if (CleanValue $td.created) { Timestamp $td.created } elseif (CleanValue $d.added) { Timestamp $d.added } else { (Get-Date).ToString('yyyy-MM-ddTHH:mm') }; updated = (Get-Date).ToString('yyyy-MM-ddTHH:mm'); family = @{ decision = 'not-reviewed'; min_age = ''; violence = 'not-reviewed'; sexual_content = 'not-reviewed'; language = 'not-reviewed'; substances = 'not-reviewed'; themes = 'not-reviewed'; notes = ''; prompts = '' } }
  if (!$targetPath) { $base = Safe $record.title; $suffix = if ($record.year) { " ($($record.year))" } else { '' }; $targetPath = Join-Path $mediaRoot "$base$suffix.md"; $i = 2; while (Test-Path -LiteralPath $targetPath) { $targetPath = Join-Path $mediaRoot "$base$suffix $i.md"; $i++ } }
  [IO.File]::WriteAllText($targetPath, (Render $record ($notes -join "`n`n")), [Text.UTF8Encoding]::new($false))
  $journal += [pscustomobject]@{ source = $operation.Source.FullName; target = $targetPath; action = if ($operation.Target) { 'updated' } else { 'created' }; source_sha256 = (Get-FileHash -LiteralPath $operation.Source.FullName -Algorithm SHA256).Hash }
}
$journal | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupRoot 'migration-journal.json') -Encoding utf8
Write-Output "Migrated $($operations.Count) legacy notes. Backup and journal: $backupRoot"
