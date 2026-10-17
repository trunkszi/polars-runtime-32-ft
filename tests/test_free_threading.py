"""Require native free threading and exercise deterministic frame operations."""

import os
import subprocess
import sys
import sysconfig


def test_import_keeps_gil_disabled():
    assert sys.version_info[:2] == (3, 15)
    assert sysconfig.get_config_var("Py_GIL_DISABLED") == 1
    assert "PYTHON_GIL" not in os.environ
    subprocess.run(
        [sys.executable, "-W", "error::RuntimeWarning", "-c",
         "import sys, polars, importlib.metadata as md; assert not sys._is_gil_enabled(); "
         "assert md.version('polars') == md.version('polars-runtime-32') == '2.0.0'; "
         "assert polars.__version__ == '2.0.0'"],
        check=True,
    )


def test_frame_sort_group_and_integer_precision():
    import polars as pl

    frame = pl.DataFrame({"time_ns": [1782345600000000001, 1782345600000000000],
                          "group": [1, 1], "value": [2.0, 1.0]})
    assert frame.sort("time_ns")["time_ns"].to_list() == [1782345600000000000, 1782345600000000001]
    assert frame.group_by("group").agg(pl.col("value").sum())["value"].to_list() == [3.0]
    assert not sys._is_gil_enabled()


def test_parallel_frames_keep_gil_disabled():
    from concurrent.futures import ThreadPoolExecutor
    import polars as pl

    def calculate(offset):
        return pl.DataFrame({"x": [offset, offset + 1]}).select(pl.col("x").sum()).item()

    with ThreadPoolExecutor(max_workers=2) as pool:
        assert list(pool.map(calculate, [1, 5])) == [3, 11]
    assert not sys._is_gil_enabled()
