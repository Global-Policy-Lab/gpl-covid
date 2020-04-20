import shlex
import subprocess
from pathlib import Path
from shutil import copytree

import pandas as pd


def test_readme():
    with open("README.md", "r") as f:
        readme = f.read()
    with open("run", "r") as f:
        for l in f:
            for prog in ["python", "Rscript", "stata"]:
                # skip quality check, which is not in readme
                if l.startswith(prog) and "quality-check-processed-datasets" not in l:
                    tocomp = l.rstrip("\n").split(" $")[0]
                    assert tocomp in readme, tocomp


def test_pipeline(tmp_path):
    tmp_model_path = tmp_path / "models"
    tmp_results_path = tmp_path / "results" / "source_data"
    tmp_results_path.parent.mkdir()
    copytree("models", tmp_model_path)
    copytree("results/source_data", tmp_results_path)

    # run pipeline
    cmd = shlex.split("bash run --no-download --nostata --nocensus --num-proj 2")
    subprocess.run(cmd, check=True)

    bad_files = []
    len_path = len(tmp_path.parts)
    for p in list(tmp_model_path.rglob("*.csv")) + list(
        tmp_results_path.rglob("*.csv")
    ):
        # skip for bootstrap samples which may have different num of bootstraps
        if "bootstrap" not in p.name:
            other_file = Path("").joinpath(*p.parts[len_path:])
            try:
                pd.testing.assert_frame_equal(
                    pd.read_csv(p), pd.read_csv(other_file), check_like=True
                )
            except UnicodeDecodeError:
                pass
            except:
                bad_files.append(str(other_file))
    if len(bad_files) > 0:
        raise AssertionError(
            "The folowing files produced by this code do not match the version saved "
            f"in the repo: {bad_files}"
        )
