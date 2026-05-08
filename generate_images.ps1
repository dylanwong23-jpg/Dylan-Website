<#
  Generate the 7 TesterTech.html product/hero images via Kie.ai's Nano Banana API.

  Prereqs:
    1. Add your Kie.ai API key to Day2/.env  (KIE_AI_API_KEY=sk-...)
       Or set it in the OS environment as KIE_AI_API_KEY.
    2. Run from the project root:  powershell -File generate_images.ps1
    3. Images land in ./images/ as PNGs. Re-runs skip files that already exist.

  API reference:
    POST https://api.kie.ai/api/v1/jobs/createTask
    GET  https://api.kie.ai/api/v1/jobs/recordInfo?taskId=<id>
    https://docs.kie.ai/market/google/nano-banana
#>

# Force TLS 1.2 (older Windows defaults can break HTTPS to api.kie.ai)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ApiBase     = "https://api.kie.ai/api/v1/jobs"
$Model       = "google/nano-banana"
$ProjectRoot = $PSScriptRoot
$ImagesDir   = Join-Path $ProjectRoot "images"
$EnvFile     = Join-Path $ProjectRoot "Day2\.env"
$PollIntervalSec = 4
$PollTimeoutSec  = 240

# Each entry: filename (no extension), aspect ratio, prompt
$Prompts = @(
  @{ name="mark-vii-watch";   aspect="1:1"; prompt="A futuristic smartwatch product shot. Square red and gold metallic case with brushed-titanium bezel. Cyan glowing holographic display showing biometric data and a small arc reactor icon. Black leather band. Floating against pure black background with subtle cyan rim light. Cinematic product photography, ultra sharp, 8K detail, three-quarter angle." },
  @{ name="hud-glasses";      aspect="1:1"; prompt="Sleek smart glasses, gold metallic frame, cyan glowing lenses with faint HUD interface visible inside. Floating on pure black background with red rim light from the right. Premium tech product photography, three-quarter angle, sharp focus." },
  @{ name="jarvis-hub";       aspect="1:1"; prompt="Cylindrical smart speaker, dark gunmetal body with hot-rod red trim ring at the base, glowing cyan light ring at the top. Standing on a glossy black reflective surface. Cinematic product shot, dramatic side lighting, 8K detail." },
  @{ name="sentinel-drone";   aspect="1:1"; prompt="Quadcopter drone, X-shaped frame with red and gold metallic arms, four glowing cyan rotors, central arc reactor core glowing bright blue. Hovering against pure black background with subtle smoke trail. Cinematic, three-quarter view, ultra detailed." },
  @{ name="nano-wristband";   aspect="1:1"; prompt="Futuristic triangular wrist-worn smart device with overlapping crimson red and warm gold metallic armor plates arranged in a geometric segmented pattern, brushed-titanium edges. A small glowing cyan circular power core in the center triangle emitting soft blue light. Floating against pure black background with red and cyan rim lighting. Cinematic product photography, ultra sharp, 8K." },
  @{ name="repulsor-earbuds"; aspect="1:1"; prompt="Pair of premium wireless earbuds with polished crimson red and warm gold metallic finish, segmented armor-style faceted panels, tiny cyan LED indicator glowing on each. Floating side by side on a pure black reflective surface. Macro product photography, sharp focus, dramatic side lighting, 8K." },
  @{ name="iron-helmet";      aspect="3:4"; prompt="Stylized futuristic mech pilot helmet, sharp angular faceplate, classic crimson red and warm gold metallic finish, glowing cyan eye slits emitting visible light beams, three-quarter front angle. Floating against pitch-black background with strong red rim light. Cinematic, ultra realistic, 8K, hero product shot." }
)

function Get-ApiKey {
  if (Test-Path $EnvFile) {
    foreach ($line in Get-Content $EnvFile -Encoding UTF8) {
      $trim = $line.Trim()
      if ($trim -eq "" -or $trim.StartsWith("#")) { continue }
      $idx = $trim.IndexOf("=")
      if ($idx -lt 0) { continue }
      $k = $trim.Substring(0, $idx).Trim()
      $v = $trim.Substring($idx + 1).Trim().Trim('"').Trim("'")
      if ($k -eq "KIE_AI_API_KEY" -and $v -ne "") { return $v }
    }
  }
  if ($env:KIE_AI_API_KEY) { return $env:KIE_AI_API_KEY }
  Write-Error "KIE_AI_API_KEY is empty. Add it to $EnvFile or set it as an env var."
  exit 1
}

function New-KieTask {
  param([string]$ApiKey, [string]$Prompt, [string]$Aspect)
  $headers = @{
    "Authorization" = "Bearer $ApiKey"
    "Content-Type"  = "application/json"
  }
  $body = @{
    model = $Model
    input = @{
      prompt        = $Prompt
      output_format = "png"
      image_size    = $Aspect
    }
  } | ConvertTo-Json -Depth 4 -Compress

  $res = Invoke-RestMethod -Method Post -Uri "$ApiBase/createTask" -Headers $headers -Body $body -ErrorAction Stop
  if ($res.code -ne 200) { throw "createTask failed: $($res | ConvertTo-Json -Depth 4 -Compress)" }
  return $res.data.taskId
}

function Wait-KieResult {
  param([string]$ApiKey, [string]$TaskId)
  $headers  = @{ "Authorization" = "Bearer $ApiKey" }
  $deadline = (Get-Date).AddSeconds($PollTimeoutSec)
  while ((Get-Date) -lt $deadline) {
    $res   = Invoke-RestMethod -Method Get -Uri "$ApiBase/recordInfo?taskId=$TaskId" -Headers $headers -ErrorAction Stop
    $state = ($res.data.state).ToString().ToLower()
    if ($state -eq "success") {
      $parsed = $res.data.resultJson | ConvertFrom-Json
      if (-not $parsed.resultUrls -or $parsed.resultUrls.Count -eq 0) {
        throw "task $TaskId succeeded but resultUrls is empty"
      }
      return $parsed.resultUrls[0]
    }
    if ($state -in @("fail","failed","error")) {
      throw "task $TaskId failed: $($res.data.failMsg)"
    }
    Start-Sleep -Seconds $PollIntervalSec
  }
  throw "task $TaskId did not complete within $PollTimeoutSec seconds"
}

function Save-Image {
  param([string]$Url, [string]$Dest)
  Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop | Out-Null
}

# ---- main ----

$apiKey = Get-ApiKey
if (-not (Test-Path $ImagesDir)) { New-Item -ItemType Directory -Path $ImagesDir | Out-Null }

Write-Output "Output directory: $ImagesDir"
Write-Output "Prompts queued:   $($Prompts.Count)"
Write-Output ""

$failures = @()

foreach ($p in $Prompts) {
  $dest = Join-Path $ImagesDir ($p.name + ".png")
  if (Test-Path $dest) {
    Write-Output "  skip  $($p.name).png  (already exists)"
    continue
  }
  Write-Output "  gen   $($p.name)  ($($p.aspect)) ..."
  try {
    $taskId = New-KieTask -ApiKey $apiKey -Prompt $p.prompt -Aspect $p.aspect
    Write-Output "        task: $taskId"
    $url = Wait-KieResult -ApiKey $apiKey -TaskId $taskId
    Save-Image -Url $url -Dest $dest
    Write-Output "        ok -> images/$($p.name).png"
  } catch {
    Write-Output "        FAIL: $($_.Exception.Message)"
    $failures += [pscustomobject]@{ name = $p.name; error = $_.Exception.Message }
  }
}

Write-Output ""
if ($failures.Count -gt 0) {
  Write-Output "$($failures.Count) failed:"
  foreach ($f in $failures) { Write-Output "  - $($f.name): $($f.error)" }
  exit 1
}
Write-Output "All images generated."
exit 0
