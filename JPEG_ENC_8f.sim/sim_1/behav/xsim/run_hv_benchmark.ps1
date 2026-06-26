<#
.SYNOPSIS
  Sweep the JPEG-LS parallel encoder across splitting modes (block / vertical /
  horizontal), block grids, and image sizes, recording compression ratio per run.

.DESCRIPTION
  Splitting mode is just the (N_H, N_V) block-grid factorization. We use ONE block
  per encoder (NUM_SLICES=1). A block grid "axb" => N_E = a*b encoders, and the
  three cut directions for that parallelism are:

      block      : a x b      (the grid as given, a 2-D grid)
      vertical   : N_E x 1     (tall column strips, cut along X)
      horizontal : 1 x N_E     (wide row strips,    cut along Y)

  Compression ratio depends only on the geometry, so the three are apples-to-apples
  at equal parallelism (same total block count = N_E).

  Geometry and image are injected by text-substituting the parameter defaults in
  tb_jls_encoder_axis.v (N_E/N_H/N_V/MAX_BYTES_PER_SLICE and PGM_FILE),
  then recompiling. (xelab -generic_top is avoided because the
  Vivado xelab.bat wrapper splits "name=value" generics on the '=' under cmd.)
  NUM_SLICES is left as its derived default (N_H*N_V)/N_E = 1.

  Each run prints a line like:
      BENCHMARK_RESULT N_H=.. N_V=.. W=.. H=.. N_E=.. NUM_SLICES=.. OUT_BYTES=..
  which is parsed here to compute ratio = (W*H) / OUT_BYTES.

  Both source files are restored to their original contents on exit.

.EXAMPLE
  .\run_hv_benchmark.ps1 -Images 300x300 -Grids 3x3,4x5
  .\run_hv_benchmark.ps1 -Images 5000x5000 -Grids 2x2,3x3,4x5 -Modes block,vertical,horizontal
#>
param(
    [string[]] $Images = @("300x300", "1500x1500"),
    [string[]] $Grids  = @("3x3", "4x5"),          # block grids "axb"; N_E = a*b (one block/encoder)
    [string[]] $Modes  = @("block", "vertical", "horizontal"),
    [string]   $VivadoBin = "C:\Xilinx\Vivado\2024.2\bin"
)

$ErrorActionPreference = "Stop"

# ---- Paths -----------------------------------------------------------------
$root    = "D:\techbistro\upwork\JPEG_Encoder_Project\JPEG_ENC_8f"
$xsimDir = Join-Path $root "JPEG_ENC_8f.sim\sim_1\behav\xsim"
$imgGen  = Join-Path $root "JPEG_ENC_8f.srcs\sim_1\imports\FPGA Encoders\tb_jls_encoder_axis.v"
$tbFile  = Join-Path $root "JPEG_ENC_8f.srcs\sim_1\imports\FPGA Encoders\tb_jls_encoder_axis.v"
$imgDir  = Join-Path $root "JPEG_ENC_8f.sim\images"
$outDir  = Join-Path $root "JPEG_ENC_8f.sim\output_block"
$results = Join-Path $outDir "hv_benchmark_results.csv"

$env:PATH = "$VivadoBin;$env:PATH"
Set-Location $xsimDir

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# "axb" -> @(a, b)
function Parse-Grid([string]$grid) {
    $p = $grid -split 'x'
    return @([int]$p[0], [int]$p[1])
}

# (mode, a, b) -> @(N_H, N_V); caller computes N_E = a*b
function Get-Geom([string]$mode, [int]$a, [int]$b) {
    $ne = $a * $b
    switch ($mode) {
        "block"      { return @($a, $b) }
        "vertical"   { return @($ne, 1) }
        "horizontal" { return @(1, $ne) }
        default      { throw "Unknown mode '$mode' (use block|vertical|horizontal)" }
    }
}

# Read/write .v as UTF-8 without BOM so Vivado's parser stays happy.
function Read-Text([string]$f)               { return [System.IO.File]::ReadAllText($f) }
function Write-Text([string]$f, [string]$t)  { [System.IO.File]::WriteAllText($f, $t, $utf8NoBom) }

function Set-PgmFile([string]$pgmPath) {
    $verilogPath = $pgmPath -replace '\\', '/'
    $t = Read-Text $imgGen
    $t = [regex]::Replace($t, 'parameter\s+PGM_FILE\s*=\s*"[^"]*"',
                          ('parameter PGM_FILE     = "{0}"' -f $verilogPath))
    Write-Text $imgGen $t
}

# Substitute integer parameter defaults in the testbench header.
function Set-TbParams([int]$ne, [int]$nh, [int]$nv, [int64]$maxBytes) {
    $t = Read-Text $tbFile
    $t = [regex]::Replace($t, '(parameter\s+integer\s+N_E\s*=\s*)\d+',                 ('${1}' + $ne))
    $t = [regex]::Replace($t, '(parameter\s+integer\s+N_H\s*=\s*)\d+',                 ('${1}' + $nh))
    $t = [regex]::Replace($t, '(parameter\s+integer\s+N_V\s*=\s*)\d+',                 ('${1}' + $nv))
    $t = [regex]::Replace($t, '(parameter\s+integer\s+MAX_BYTES_PER_SLICE\s*=\s*)\d+', ('${1}' + $maxBytes))
    Write-Text $tbFile $t
}

# ---- Preserve originals ----------------------------------------------------
$imgGenBackup = Read-Text $imgGen
$tbBackup     = Read-Text $tbFile

if (-not (Test-Path $results)) {
    "image,mode,N_H,N_V,block_w,block_h,out_bytes,ratio,run_seconds" | Out-File $results -Encoding ascii
}

try {
    foreach ($img in $Images) {
        $wh = $img -split 'x'
        $W = [int]$wh[0]; $H = [int]$wh[1]
        $pgm = Join-Path $imgDir "world_gray_$img.pgm"
        if (-not (Test-Path $pgm)) { Write-Warning "Image not found, skipping: $pgm"; continue }

        Write-Host "==== Image $img ($W x $H) ====" -ForegroundColor Cyan
        Set-PgmFile $pgm

        foreach ($grid in $Grids) {
            $ab = Parse-Grid $grid
            $N_E = $ab[0] * $ab[1]
            Write-Host ("  grid {0}  (N_E={1})" -f $grid, $N_E) -ForegroundColor Cyan

            foreach ($mode in $Modes) {
                $g = Get-Geom $mode $ab[0] $ab[1]
                $N_H = $g[0]; $N_V = $g[1]
                # Horizontal strips span the full width — line buffer caps width at 16384.
                if ($N_H -eq 1 -and $W -gt 16384) {
                    Write-Warning "Skipping horizontal for $img : width $W exceeds 16384 line-buffer limit"; continue
                }
                $blockW = [int][math]::Floor($W / $N_H)
                $blockH = [int][math]::Floor($H / $N_V)
                # Generous per-slice buffer: 2x raw pixels of one block + header slack.
                $maxBytes = [int64]([math]::Ceiling([double]($W * $H) / $N_E) * 2 + 8192)

                Write-Host ("    -> {0,-10} N_H={1} N_V={2} block={3}x{4}" -f $mode,$N_H,$N_V,$blockW,$blockH)
                Set-TbParams $N_E $N_H $N_V $maxBytes

                $tag     = "${img}_${grid}_${mode}"
                $elabLog = "elaborate_$tag.log"
                $simLog  = "simulate_$tag.log"

                & xvlog --incr --relax -prj tb_top_jls_vertical_vlog.prj -log "xvlog_$tag.log" | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "xvlog failed for $tag" }

                & xelab --debug typical --relax --mt 2 `
                    -L xil_defaultlib -L fifo_generator_v13_2_11 -L unisims_ver `
                    -L unimacro_ver -L secureip -L xpm `
                    --snapshot tb_jls_encoder_axis_behav `
                    xil_defaultlib.tb_jls_encoder_axis xil_defaultlib.glbl -log $elabLog | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "xelab failed for $tag (see $elabLog)" }

                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                & xsim tb_jls_encoder_axis_behav -tclbatch run_quit.tcl -log $simLog | Out-Null
                $sw.Stop()
                if ($LASTEXITCODE -ne 0) { throw "xsim failed for $tag (see $simLog)" }

                $line = Select-String -Path $simLog -Pattern 'BENCHMARK_RESULT' | Select-Object -Last 1
                if (-not $line) { Write-Warning "No BENCHMARK_RESULT in $simLog"; continue }
                if ($line.Line -match 'OUT_BYTES=(\d+)') {
                    $outBytes = [int64]$Matches[1]
                    $ratio = if ($outBytes -gt 0) { [math]::Round(($W * $H) / $outBytes, 2) } else { 0 }
                    $secs  = [math]::Round($sw.Elapsed.TotalSeconds, 1)
                    Add-Content $results "$img,$mode,$N_H,$N_V,$blockW,$blockH,$outBytes,$ratio,$secs"
                    Write-Host ("       out={0} bytes  ratio={1}:1  ({2}s)" -f $outBytes,$ratio,$secs) -ForegroundColor Green
                } else {
                    Write-Warning "Could not parse OUT_BYTES from $simLog"
                }
            }
        }
    }
}
finally {
    Write-Text $imgGen $imgGenBackup
    Write-Text $tbFile  $tbBackup
    Write-Host "Restored tb_jls_encoder_axis.v" -ForegroundColor DarkGray
}

Write-Host "`nResults -> $results" -ForegroundColor Cyan
Get-Content $results | Format-Table -AutoSize
