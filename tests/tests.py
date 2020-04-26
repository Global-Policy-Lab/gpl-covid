import os
import shlex
import subprocess
from pathlib import Path
from shutil import copytree

import pandas as pd


def test_readme():
    with open("README.md", "r") as f:
        readme = f.read()
    with open("code/run.sh", "r") as f:
        for l in f:
            for prog in ["python", "Rscript", "stata"]:
                # skip quality check, which is not in readme
                if l.startswith(prog) and "quality-check-processed-datasets" not in l:
                    tocomp = l.rstrip("\n").split(" $")[0]
                    assert tocomp in readme, tocomp


def exclude_files(fileset, run_stata):
    """List all files that we know will not get updated or don't want to check:
    1) bootstraps, ED Fig 5, and ED Fig 8/9 are run with only 2 samples in tests, so 
       don't check those.
    2) SITable2.xlsx is created manually
    3) Ignore all files ``in source_data/indiv``
    4) excluded data in "models" and "results/source_data" is created by stata code
       (will not be created in SI if run on github-hosted runner)
    5) TODO: Figure out why fig1 is getting randomly sorted differently by different
       OS so that we can properly test it
    """

    files_to_exclude = (
        list(Path("models/projections").glob("*_bootstrap_projection.csv"))
        + [
            Path("results") / "source_data" / i
            for i in ["ExtendedDataFigure5_lags.xlsx", "ExtendedDataFigure89.csv", "SITable2.xlsx",]
        ]
        + list(Path("results/source_data/indiv").glob("*"))
        + list(Path("results/source_data").glob("fig1*.csv"))
    )
    if not run_stata:
        files_to_exclude += (
            list(Path("models/reg_data").glob("*.csv"))
            + list(Path("models").glob("*_preds.csv"))  # created by stata
            + list(Path("models").glob("*_ATE.csv"))  # created by stata
            + [
                Path("results") / "source_data" / i
                for i in [
                    "Figure2_data.csv",
                    "Figure3_data.csv",
                    "ExtendedDataFigure3_cross_valid.csv",
                    "ExtendedDataFigure4_cross_valid.csv",
                    "ExtendedDataFigure6.xlsx",
                    "ExtendedDataFigure10_e.csv",
                ]
            ]
        )
    files_to_exclude = set(files_to_exclude)
    return fileset - files_to_exclude


def test_pipeline(tmp_path):

    run_stata = str(os.environ.get("STATA_TESTS", "false")).lower() == "true"
    stata_flag = "" if run_stata else " --nostata"

    tmp_model_path = tmp_path / "models"
    tmp_results_path = tmp_path / "results" / "source_data"
    tmp_results_path.parent.mkdir()
    copytree("models", tmp_model_path)
    copytree("results/source_data", tmp_results_path)

    old_files = set(
        [i for i in Path("models").rglob("*") if i.is_file()]
        + [i for i in Path("results/source_data").rglob("*") if i.is_file()]
    )
    old_files = exclude_files(old_files, run_stata)

    # know when last modified
    old_mtimes = {i: i.stat().st_mtime for i in old_files}

    # run pipeline
    cmd = f"bash code/run.sh{stata_flag} --num-proj 2"
    subprocess.run(shlex.split(cmd), check=True)

    new_files = set(
        [i for i in Path("models").rglob("*") if i.is_file()]
        + [i for i in Path("results/source_data").rglob("*") if i.is_file()]
    )
    new_files = exclude_files(new_files, run_stata)

    # know when last modified
    new_mtimes = {i: i.stat().st_mtime for i in new_files}

    # find all files that either weren't created with code or were created with code
    # yet weren't already in repo
    missing_files = set([i for i in new_files if i not in old_files])
    not_generated = set(
        [i for i in old_files if i not in new_files or old_mtimes[i] == new_mtimes[i]]
    )

    to_test = new_files - missing_files - not_generated
    not_checked = []
    bad_files = []
    for other_file in new_files:
        p = tmp_path / other_file
        if p.suffix == ".csv":
            these_dfs = {"0": pd.read_csv(other_file)}
            comp_dfs = {"0": pd.read_csv(p)}
        elif p.suffix == ".xlsx":
            these_dfs = pd.read_excel(other_file, sheet_name=None)
            comp_dfs = pd.read_excel(p, sheet_name=None)
        else:
            not_checked.append(other_file)
        if p.suffix in [".csv", ".xlsx"]:
            for k in these_dfs.keys():
                try:
                    pd.testing.assert_frame_equal(
                        these_dfs[k], comp_dfs[k], check_like=True
                    )
                except AssertionError as err:
                    bad_files.append(str(other_file))
                    print(f"{other_file} DOES NOT MATCH: {err}")

    # raise errors
    if len(not_checked) > 0:
        warnings.warn(f"The following files were not checked: {not_checked}")
    if len(missing_files.union(not_generated, bad_files)) > 0:
        raise AssertionError(
            f"""The following files produced by this code do not match the version saved
            in the repo: {set(bad_files)}.

            The following files contained in this commit are NOT created by the code:
            {not_generated}

            The following files produced by the code are NOT contained in the commit:
            {missing_files}
            """
        )
