# Crop a P5 PGM into sub-images without loading the whole thing into .NET imaging.
# Usage: invoked directly below.

param(
    [string]$Src,
    [int]$CropW,
    [int]$CropH,
    [string]$Dst
)

Write-Host "Opening $Src ..."
$fs = [System.IO.File]::OpenRead($Src)
$sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::ASCII, $false, 4096)

# Read magic
$magic = $sr.ReadLine().Trim()
if ($magic -ne "P5") { throw "Not a P5 PGM: $magic" }

# Skip comment lines
$line = $sr.ReadLine().Trim()
while ($line.StartsWith("#")) { $line = $sr.ReadLine().Trim() }

# Width Height
$parts = $line -split '\s+'
$W = [int]$parts[0]
$H = [int]$parts[1]

# Max value
$maxval = [int]$sr.ReadLine().Trim()

Write-Host "Source: ${W}x${H} maxval=$maxval"
if ($CropW -gt $W) { $CropW = $W }
if ($CropH -gt $H) { $CropH = $H }
Write-Host "Cropping to ${CropW}x${CropH} -> $Dst"

# After StreamReader we need the exact byte offset of the binary data start.
# Easiest: close and re-open, scan manually.
$sr.Close()
$fs.Close()

$raw = [System.IO.File]::ReadAllBytes($Src)
$pos = 0

# find end of header (3 newlines after "P5")
$nl = 0
while ($nl -lt 3 -and $pos -lt $raw.Length) {
    if ($raw[$pos] -eq 10) { $nl++ }
    $pos++
}
$dataOffset = $pos
Write-Host "Binary data starts at byte $dataOffset"

# Write output PGM
$outFs = [System.IO.File]::Open($Dst, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($outFs)
$header = [System.Text.Encoding]::ASCII.GetBytes("P5`n$CropW $CropH`n$maxval`n")
$bw.Write($header)

for ($y = 0; $y -lt $CropH; $y++) {
    $rowStart = $dataOffset + ($y * $W)
    $bw.Write($raw, $rowStart, $CropW)
}

$bw.Close()
$outFs.Close()
Write-Host "Written: $Dst"
