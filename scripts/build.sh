#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
polars_work=${POLARS_WORK_DIR:-/tmp/questra-polars-315t-2.0.0}
export PYO3_PYTHON=${PYO3_PYTHON:-$repo_root/.venv/bin/python}
export PATH="$(dirname "$PYO3_PYTHON"):$PATH"
export RUSTUP_TOOLCHAIN=nightly-2026-09-01
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-4}
export CARGO_TARGET_DIR="$polars_work/target-manylinux_2_28"
export RUST_LOG=warn
# Zig selects the requested glibc baseline; host linker flags would override it.
export RUSTFLAGS=""
mkdir -p "$polars_work" "$repo_root/wheels"
"$PYO3_PYTHON" - "$polars_work" <<'PY'
import hashlib,json,os,sys,sysconfig,tarfile,urllib.request
from pathlib import Path
if sys.version_info[:2]!=(3,15) or not sysconfig.get_config_var('Py_GIL_DISABLED') or sys._is_gil_enabled(): raise RuntimeError('CPython 3.15t with GIL disabled required')
if os.environ.get('PYTHON_GIL') is not None: raise RuntimeError('unset PYTHON_GIL')
root=Path(sys.argv[1]); archive=root/'polars_runtime_32-2.0.0.tar.gz'
expected='b5f9afcc742b4a67eabd2c680ff0f12eb02ede9b4bf807bffabd6dbb9a58d5c7'
if not archive.exists():
    with urllib.request.urlopen('https://pypi.org/pypi/polars-runtime-32/2.0.0/json',timeout=30) as r: metadata=json.load(r)
    source=next(f for f in metadata['urls'] if f['packagetype']=='sdist')
    with urllib.request.urlopen(source['url'],timeout=60) as r: archive.write_bytes(r.read())
if hashlib.sha256(archive.read_bytes()).hexdigest()!=expected: raise RuntimeError('sdist digest mismatch')
if not (root/'polars_runtime_32-2.0.0').exists():
    with tarfile.open(archive) as t: t.extractall(root,filter='data')
PY
cd "$polars_work/polars_runtime_32-2.0.0"
patch_file="$repo_root/patches/polars-2.0.0-drop-abi3.diff"
if patch --batch --forward --dry-run --silent -p1 < "$patch_file"; then
    patch --batch --forward -p1 < "$patch_file"
else
    patch --batch --dry-run --silent -R -p1 < "$patch_file"
fi
build_started=$(date +%s)
maturin build --release --zig --compatibility manylinux_2_28 --strip --interpreter "$PYO3_PYTHON" --out "$repo_root/wheels" > "$polars_work/build-manylinux_2_28.log" 2>&1
build_finished=$(date +%s)
"$PYO3_PYTHON" - "$repo_root" "$polars_work" "$build_started" "$build_finished" <<'PY'
import hashlib,importlib.metadata,json,os,subprocess,sys
from pathlib import Path
repo,work=map(Path,sys.argv[1:3]);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
wheel=repo/'wheels/polars_runtime_32-2.0.0-cp315-cp315t-manylinux_2_28_x86_64.whl'
if not wheel.is_file(): raise RuntimeError('expected cp315t manylinux_2_28 x86_64 wheel absent')
report={'version':'2.0.0','version_reason':'requested Polars 2.0 free-threaded wheel','sdist_sha256':sha(work/'polars_runtime_32-2.0.0.tar.gz'),'command':['maturin','build','--release','--zig','--compatibility','manylinux_2_28','--strip','--interpreter',sys.executable,'--out',str(repo/'wheels')],'rustc':subprocess.check_output(['rustc','-Vv'],text=True),'maturin':subprocess.check_output(['maturin','--version'],text=True).strip(),'ziglang':importlib.metadata.version('ziglang'),'python':sys.version,'interpreter_sha256':sha(Path(sys.executable)),'jobs':int(os.environ['CARGO_BUILD_JOBS']),'features':['default:full','default:nightly'],'elapsed_seconds':int(sys.argv[4])-int(sys.argv[3]),'patches':[{'path':'patches/polars-2.0.0-drop-abi3.diff','sha256':sha(repo/'patches/polars-2.0.0-drop-abi3.diff')}],'wheels':[{'path':str(wheel),'sha256':sha(wheel)}],'references':['https://github.com/harshil21/polars-runtime-32-ft','https://github.com/pola-rs/polars/pull/21914']}
(repo/'wheels/build-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'wheel':wheel.name,'sha256':sha(wheel),'elapsed_seconds':report['elapsed_seconds']}))
PY
