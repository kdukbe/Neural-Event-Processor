param(
    [ValidateSet('always_on_8mhz','event_driven_8mhz','always_on_1mhz')][string]$Mode='always_on_8mhz',
    [ValidateSet('burst','real1','real2','real3')][string]$Dataset='burst',
    [ValidateSet('Export','Activity','Power')][string]$Stage='Export',
    [switch]$Start,
    [switch]$SkipCompile
)
$ErrorActionPreference='Stop'
if(-not $Start) {
    Write-Output "Selected: $Mode / $Dataset / $Stage. Add -Start to execute."
    return
}
$manifest=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest_portable.json') | ConvertFrom-Json
$system=$manifest.systems.$Mode
$workload=$manifest.workloads.$Dataset
$project=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$data=Join-Path $project "data/prepared/$Dataset"
if(-not [IO.Path]::IsPathRooted($system.dcp)){$system.dcp=Join-Path $project $system.dcp}
$buildRoot=if($env:NEURAL_BUILD_DIR){$env:NEURAL_BUILD_DIR}else{Join-Path $project 'build'}
$build=Join-Path $buildRoot "power/$Mode"
$resultRoot=if($env:NEURAL_POWER_RESULTS){$env:NEURAL_POWER_RESULTS}else{Join-Path $buildRoot 'power/results'}
$env:NEURAL_POWER_RESULTS=$resultRoot
$out=Join-Path $resultRoot "evidence/$Dataset/$Mode"
$bin=if($env:NEURAL_VIVADO_BIN){$env:NEURAL_VIVADO_BIN}
     elseif($env:XILINX_VIVADO){Join-Path $env:XILINX_VIVADO 'bin'}
     else{
         $tool=Get-Command vivado.bat -ErrorAction SilentlyContinue
         if(-not $tool){throw 'Vivado not found. Use its command prompt or set NEURAL_VIVADO_BIN.'}
         Split-Path -Parent $tool.Source
     }
$glbl=Join-Path (Split-Path -Parent $bin) 'data/verilog/src/glbl.v'
$python=if($env:NEURAL_PYTHON){$env:NEURAL_PYTHON}else{'python'}
if((Get-FileHash -LiteralPath $system.dcp -Algorithm SHA256).Hash.ToLower() -ne $system.dcp_sha256) {throw 'Archived DCP changed'}
foreach($entry in $workload.file_sha256.PSObject.Properties) {
    if((Get-FileHash -LiteralPath (Join-Path $data $entry.Name) -Algorithm SHA256).Hash.ToLower() -ne $entry.Value) {throw "Prepared input/config changed: $($entry.Name)"}
}
New-Item -ItemType Directory -Force -Path $build,$out | Out-Null
$env:NEURAL_DCP=$system.dcp.Replace('\','/')
$env:NEURAL_IP=$system.ip_scope
$env:NEURAL_BUILD=$build
$env:NEURAL_MODE=$Mode
$env:NEURAL_OUT=$out.Replace('\','/')
Push-Location -LiteralPath $build
try {
    if($Stage -eq 'Export') {
        & "$bin/vivado.bat" -mode batch -source (Join-Path $PSScriptRoot 'export_netlist.tcl') -log export.log -journal export.jou
        if($LASTEXITCODE -ne 0) {throw 'Netlist export failed'}
        $system.dcp_sha256 | Set-Content -LiteralPath 'exported_dcp.sha256'
    } elseif($Stage -eq 'Activity') {
        if(-not(Test-Path -LiteralPath 'exported_dcp.sha256')) {throw 'Run Export first'}
        if((Get-Content -Raw -LiteralPath 'exported_dcp.sha256').Trim() -ne $system.dcp_sha256) {throw 'Stale exported netlist'}
        $defines=if($Mode -eq 'always_on_1mhz'){@()}else{@('-d','SFE8')}
        if(-not $SkipCompile) {
            & "$bin/xvlog.bat" -sv @defines 'board_ip_funcsim.v' (Join-Path $PSScriptRoot 'tb_RoutedPower.sv') $glbl
            if($LASTEXITCODE -ne 0) {throw 'xvlog failed'}
            & "$bin/xelab.bat" tb_RoutedPower glbl -L unisims_ver -debug all -s power_sim
            if($LASTEXITCODE -ne 0) {throw 'xelab failed'}
        }
        $env:NEURAL_COMPARE_SAIF=(Join-Path $out 'activity.saif')
        $env:NEURAL_COMPARE_OBSERVATION_NS=[string]$workload.observation_ns
        $pairs=@("DATA_DIR=$($data.Replace('\','/'))", "OUT_DIR=$($out.Replace('\','/'))",
            "INPUT_COUNT=$($workload.input_rows)","EXPECTED_EVENTS=$($workload.expected_events)",
            "THRESHOLD=$($workload.threshold)","OBSERVATION_NS=$($workload.observation_ns)")
        $testargs=@()
        foreach($pair in $pairs) {$testargs+=@('-testplusarg',('"'+$pair+'"'))}
        & "$bin/xsim.bat" power_sim -tclbatch ((Join-Path $PSScriptRoot 'capture.tcl').Replace('\','/')) @testargs -log (Join-Path $out 'simulation.log')
        if($LASTEXITCODE -ne 0) {throw 'xsim failed'}
        $log=Get-Content -Raw -LiteralPath (Join-Path $out 'simulation.log')
        if($log -notmatch 'PASS routed IP' -or $log -match '(?m)^Fatal:|^ERROR:|^ERROR record') {throw 'Golden/activity validation failed'}
        @{dcp_sha256=$system.dcp_sha256; threshold=$workload.threshold; file_sha256=$workload.file_sha256;
          observation_ns=$workload.observation_ns} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $out 'activity_inputs.json')
    } else {
        $record=Get-Content -Raw -LiteralPath (Join-Path $out 'activity_inputs.json') | ConvertFrom-Json
        if($record.dcp_sha256 -ne $system.dcp_sha256 -or $record.threshold -ne $workload.threshold -or $record.observation_ns -ne $workload.observation_ns) {throw 'Activity was captured with different settings'}
        foreach($entry in $workload.file_sha256.PSObject.Properties) {
            if($record.file_sha256.($entry.Name) -ne $entry.Value) {throw "Stale activity input: $($entry.Name)"}
        }
        & $python (Join-Path $PSScriptRoot 'clock_activity.py') $Mode $Dataset
        if($LASTEXITCODE -ne 0) {throw 'Clock activity validation failed'}
        & $python (Join-Path $PSScriptRoot 'map_saif.py') $Mode $Dataset
        if($LASTEXITCODE -ne 0) {throw 'SAIF mapping failed'}
        & "$bin/vivado.bat" -mode batch -source (Join-Path $PSScriptRoot 'apply_power.tcl') -log (Join-Path $out 'power.log') -journal (Join-Path $out 'power.jou')
        if($LASTEXITCODE -ne 0) {throw 'Power calculation failed'}
        & "$bin/vivado.bat" -mode batch -source (Join-Path $PSScriptRoot 'audit_power.tcl') -log (Join-Path $out 'audit.log') -journal (Join-Path $out 'audit.jou')
        if($LASTEXITCODE -ne 0) {throw 'Clock-model audit failed'}
        & $python (Join-Path $PSScriptRoot 'collect_results.py') --case $Mode $Dataset
        if($LASTEXITCODE -ne 0) {throw 'Evidence/coverage audit failed'}
    }
} finally {Pop-Location}
