# run_unit_tests.ps1 — compile + run every Cleave RV32I module unit test with Icarus Verilog.
#
# Usage (from anywhere):
#   powershell -File test\unit\run_unit_tests.ps1
# Exit code: 0 if all modules pass, 1 otherwise (CI-friendly).
#
# Each bench prints "ALL <module> TESTS PASSED" on success and calls $fatal
# (non-zero exit) on any mismatch. This script treats a module as passing only
# when vvp exits 0 AND that banner is present.

$ErrorActionPreference = "Stop"

# Icarus Verilog from the msys2 install; its bin dir must be on PATH for the DLLs.
$IVERILOG = "C:\msys64\mingw64\bin\iverilog.exe"
$VVP      = "C:\msys64\mingw64\bin\vvp.exe"
$env:PATH = "C:\msys64\mingw64\bin;" + $env:PATH

$UnitDir  = $PSScriptRoot
$SrcDir   = (Resolve-Path (Join-Path $UnitDir "..\..\src")).Path
$BuildDir = Join-Path $UnitDir "build"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

# Ordered map: module name -> DUT source file(s) it needs (bench is tb_<name>.v).
$Tests = [ordered]@{
  "cleave_pc"      = @("cleave_pc.v")
  "cleave_imem"    = @("cleave_imem.v")
  "cleave_regfile" = @("cleave_regfile.v")
  "cleave_alu"     = @("cleave_alu.v")
  "cleave_immgen"  = @("cleave_immgen.v")
  "cleave_branch"  = @("cleave_branch.v")
  "cleave_control" = @("cleave_control.v")
  "cleave_dmem"    = @("cleave_dmem.v")
  "cleave_core"    = @("cleave_core.v", "cleave_pc.v", "cleave_imem.v", "cleave_regfile.v",
                       "cleave_alu.v", "cleave_immgen.v", "cleave_branch.v", "cleave_control.v",
                       "cleave_dmem.v")
  # Integration proof: runs the committed cleave_imem program end-to-end (full RV32I).
  "cleave_proof"   = @("cleave_core.v", "cleave_pc.v", "cleave_imem.v", "cleave_regfile.v",
                       "cleave_alu.v", "cleave_immgen.v", "cleave_branch.v", "cleave_control.v",
                       "cleave_dmem.v")
}

$results = @()
foreach ($name in $Tests.Keys) {
  $tb   = Join-Path $UnitDir  ("tb_" + $name + ".v")
  $out  = Join-Path $BuildDir ($name + ".vvp")
  $srcs = $Tests[$name] | ForEach-Object { Join-Path $SrcDir $_ }

  # Compile (-DSIMULATION so regfile zero-inits deterministically).
  & $IVERILOG -g2012 -DSIMULATION -o $out $tb $srcs
  if ($LASTEXITCODE -ne 0) {
    $results += [pscustomobject]@{ Module = $name; Status = "COMPILE-FAIL" }
    continue
  }

  # Run and inspect output.
  $log = (& $VVP $out | Out-String)
  if (($LASTEXITCODE -eq 0) -and ($log -match "ALL .* TESTS PASSED")) {
    $results += [pscustomobject]@{ Module = $name; Status = "PASS" }
  } else {
    Write-Host "----- $name output -----"
    Write-Host $log
    $results += [pscustomobject]@{ Module = $name; Status = "FAIL" }
  }
}

Write-Host ""
Write-Host "==== Cleave RV32I unit tests ===="
foreach ($r in $results) {
  $color = if ($r.Status -eq "PASS") { "Green" } else { "Red" }
  Write-Host ("  {0,-16} {1}" -f $r.Module, $r.Status) -ForegroundColor $color
}
$passN = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$total = $results.Count
Write-Host ""
Write-Host ("  {0}/{1} modules passed" -f $passN, $total)

if ($passN -ne $total) { exit 1 } else { exit 0 }
