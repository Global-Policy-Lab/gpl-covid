from pathlib import Path
import pandas as pd
import shlex
import subprocess
from shutil import copytree, rmtree


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
    copytree("data", tmp_path / "data")
    copytree("models", tmp_path / "models")

    # don't check raw data
    rmtree(tmp_path / "data" / "raw")

    # run pipeline
    cmd = shlex.split("bash run --nostata --nocensus --num-proj 2")
    process = subprocess.run(cmd, check=True)

    # check that interim/processed/post_processing data and models match
    with open("tests/ignore_comparison.txt", "r") as f:
        to_skip = f.readlines()
    to_skip = [Path(tmp_path) / p for p in to_skip]

    bad_files = []
    for d in ["data", "models"]:
        path = tmp_path / d
        len_path = len(tmp_path.parts)
        for p in path.rglob("*"):
            if p.suffix == ".csv" and p not in to_skip:
                other_file = Path("").joinpath(*p.parts[len_path:])
                try:
                    pd.testing.assert_frame_equal(
                        pd.read_csv(p), pd.read_csv(other_file)
                    )
                except UnicodeDecodeError:
                    pass
                except AssertionError:
                    bad_files.append(str(other_file))
    if len(bad_files) > 0:
        raise AssertionError, f"The folowing files produced by this code do not match the version saved in the repo: {bad_files}"
