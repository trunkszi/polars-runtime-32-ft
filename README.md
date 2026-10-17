# Polars 2.0 on CPython 3.15t

This fork builds **Polars 2.0.0** for the free-threaded CPython 3.15 ABI.
It supplies a local `polars-runtime-32` wheel for Linux x86_64 with a
`manylinux_2_28` baseline. aarch64 and Windows are placeholders until matching
wheels are built and tested; they are not claimed as supported targets.

The [original project](https://github.com/harshil21/polars-runtime-32-ft) supplies
Polars 1.37.1 wheels. This fork updates the pinned source and Python package to
2.0.0, tracks the ABI patch and build recipe, and tests default GIL behavior.
Upstream free-threaded work is tracked in
[Polars PR #21914](https://github.com/pola-rs/polars/pull/21914).

## Install and verify

Use uv on Linux x86_64:

```bash
uv sync --frozen --python 3.15.0t --group dev
env -u PYTHON_GIL uv run --frozen python -W error::RuntimeWarning -m pytest -q
```

`pyproject.toml` selects the local wheel in `wheels/` with a platform marker.
The environment must use `cp315t`; an ordinary `cp315` interpreter is not an
acceptance substitute. Tests import Polars in a fresh process without forcing
`PYTHON_GIL`, verify that the GIL stays disabled, and exercise frames, exact
nanosecond integers, CSV scans and concurrent frame operations.

## Rebuild the wheel

The source archive is `polars_runtime_32-2.0.0.tar.gz`, SHA256:

```text
b5f9afcc742b4a67eabd2c680ff0f12eb02ede9b4bf807bffabd6dbb9a58d5c7
```

Bootstrap a build environment if the wheel has not been created yet:

```bash
uv venv --python 3.15.0t .venv
uv pip install --python .venv/bin/python 'maturin[zig]==1.15.0' pytest
rustup toolchain install nightly-2026-09-01 --profile minimal
bash scripts/build.sh
uv sync --python 3.15.0t --group dev
```

The script downloads and checks the sdist, applies
[the two-line ABI patch](patches/polars-2.0.0-drop-abi3.diff), and runs:

```bash
maturin build --release --zig --compatibility manylinux_2_28 --strip \
  --interpreter .venv/bin/python --out wheels
```

`abi3-py310` selects the GIL-build stable ABI. Removing that feature in both
Cargo manifests lets PyO3 build for the selected interpreter's `cp315t` ABI.
The source modules already declare `gil_used=false`; the patch does not change
frame semantics or force an unsafe GIL setting.

Zig supplies a glibc 2.28 link target even on a newer build host. Maturin audits
the resulting compatibility tag; the wheel is not renamed to imply compatibility.
Build sources and Cargo outputs remain under `/tmp/questra-polars-315t-2.0.0`
by default (`POLARS_WORK_DIR` overrides this). Cargo uses four jobs by default
(`CARGO_BUILD_JOBS` overrides this). The upstream default features are `full,nightly`.

`wheels/build-manifest.json` records source/patch/wheel hashes, Rust and maturin
versions, Zig version, exact command, features and elapsed seconds. The wheel
and manifest are local artifacts until explicitly published.

The pinned Python package version and the native `PYPOLARS_VERSION` are both
`2.0.0`; acceptance checks package metadata and the native version.
