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

    ## list all files that we know will not get updated
    # 1) bootstraps are run with only 2 samples in tests, so don't check those
    # 2) excluded data in "models" and "results/source_data" is created by stata code
    #    that does not run in CI
    # 3) TODO: Figure out why fig1 is getting randomly sorted differently by different
    #    OS so that we can properly test it
    files_to_exclude = set(
        list(Path("models/reg_data").glob("*.csv"))
        + list(Path("models").glob("*_preds.csv"))  # created by stata
        + list(Path("models").glob("*_ATE.csv"))  # created by stata
        + [  # created by stata
            Path("results") / "source_data" / i
            for i in [
                "Figure2_data.csv",
                "Figure3_data.csv",
                "ExtendedDataFigure3_cross_valid.csv",
                "ExtendedDataFigure4_cross_valid.csv",
                "ExtendedDataFigure6.xlsx" "ExtendedDataFigure10_e.csv",
            ]
        ]
        + list(Path("models/projections").glob("*_bootstrap_projection.csv"))
        + list(Path("results/source_data").glob("fig1*.csv"))
    )

    tmp_model_path = tmp_path / "models"
    tmp_results_path = tmp_path / "results" / "source_data"
    tmp_results_path.parent.mkdir()
    copytree("models", tmp_model_path)
    copytree("results/source_data", tmp_results_path)

    old_files = set(
        [i for i in Path("models").rglob("*") if i.is_file()]
        + [i for i in Path("results/source_data").rglob("*") if i.is_file()]
    )
    old_files = old_files - files_to_exclude

    # know when last modified
    old_mtimes = {i: i.stat().st_mtime for i in old_files}

    # run pipeline
    cmd = shlex.split("bash run --no-download --nostata --nocensus --num-proj 2")
    subprocess.run(cmd, check=True)

    bad_files = []

    new_files = set(
        [i for i in Path("models").rglob("*") if i.is_file()]
        + [i for i in Path("results/source_data").rglob("*") if i.is_file()]
    )
    new_files = new_files - files_to_exclude

    # know when last modified
    new_mtimes = {i: i.stat().st_mtime for i in new_files}

    # find all files that either weren't created with code or were created with code
    # yet weren't already in repo
    missing_files = set([i for i in new_files if i not in old_files])
    not_generated = set([i for i in old_files if old_mtimes[i] == new_mtimes[i]])

    to_test = new_files - missing_files - not_generated
    for other_file in to_test:
        p = tmp_path / other_file
        try:
            pd.testing.assert_frame_equal(
                pd.read_csv(p), pd.read_csv(other_file), check_like=True
            )
        except UnicodeDecodeError:
            pass
        except:
            bad_files.append((str(other_file), str(p)))

    # raise errors
    if len(missing_files.union(not_generated, bad_files)) > 0:
        if len(bad_files) > 0:
            print("Dumped contents of non-matched files:\n")
            for other_file, p in bad_files:
                cmd = shlex.split(f"cat {other_file}")
                subprocess.run(cmd)
                cmd = shlex.split(f"cat {p}")
                subprocess.run(cmd)
        raise AssertionError(
            f"""The folowing files produced by this code do not match the version saved 
            in the repo: {set([x for x, _ in bad_files])}.
            
            The folowing files contained in this commit are NOT created by the code:
            {not_generated}
            
            The folowing files produced by the code are NOT contained in the commit:
            {missing_files}
            """
        )
