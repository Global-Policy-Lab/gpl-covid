import os
import shlex
import subprocess
from pathlib import Path
from shutil import copytree
import warnings

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


def test_r_stata_match():
    cmd = "Rscript code/models/test_that_r_coefs_match_stata.R"
    subprocess.run(shlex.split(cmd), check=True)


def exclude_files(fileset, run_stata):
    """List all files that we know will not get updated or don't want to check:
    1) Ignore all files in ``source_data/indiv``
    2) Ignore all files in ``models/projections/raw``
    3) SITable2.xlsx is created manually
    4) ED figures 5, 8, and 9 + bootstraps are created using 1000 samples, while testing
       runs only with 2
    5) Extra excluded data in "models" and "results/source_data" is created by stata
       code (will not be created in SI if run on github-hosted runner)
    6) TODO: Figure out why Fig 1 is getting randomly sorted differently by different
       OS so that we can properly test it
    """

    files_to_exclude = (
        list(Path("results/source_data/indiv").glob("*"))
        + list(Path("models/projections/raw").glob("*"))
        + list(Path("models/projections").glob("*_bootstrap_projection.csv"))
        + [
            Path("results") / "source_data" / i
            for i in [
                "Figure1_data.xlsx",
                "SITable2.xlsx",
                "ExtendedDataFigure5_lags.xlsx",
                "ExtendedDataFigure89.csv",
            ]
        ]
        + [Path("data/processed/[country]_processed.csv")]
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
            + [Path("data/processed/adm1/FRA_processed.csv")]
        )
    files_to_exclude = set(files_to_exclude)
    return fileset - files_to_exclude


def copy_to_tmp(tmp_path, paths):
    for p in paths:
        this_tmp_dir = tmp_path / p
        copytree(p, this_tmp_dir)
    return None


def get_all_files(paths, run_stata):
    files_list = []
    for p in paths:
        files_list += [i for i in p.rglob("*") if i.is_file()]

    files = exclude_files(set(files_list), run_stata)

    # know when last modified
    mtimes = {i: i.stat().st_mtime for i in files}

    return files, mtimes


def test_pipeline(tmp_path):

    run_stata = str(os.environ.get("STATA_TESTS", "false")).lower() == "true"
    stata_flag = "" if run_stata else " --nostata"

    paths_to_test = [
        Path("models"),
        Path("results/source_data"),
        Path("data/processed"),
    ]

    # copy all pre-pipeline files to temp dir
    copy_to_tmp(tmp_path, paths_to_test)

    # get all files and modification times in the directories pre-pipeline
    old_files, old_mtimes = get_all_files(paths_to_test, run_stata)

    # run pipeline
    cmd = f"bash code/run.sh{stata_flag} --num-proj 2"
    subprocess.run(shlex.split(cmd), check=True)

    # get all files and modification times in the directories post-pipeline
    new_files, new_mtimes = get_all_files(paths_to_test, run_stata)

    # find all files that either weren't created with code or were created with code
    # yet weren't already in repo
    missing_files = set([i for i in new_files if i not in old_files])
    not_generated = set(
        [i for i in old_files if i not in new_files or old_mtimes[i] == new_mtimes[i]]
    )

    to_test = new_files - missing_files - not_generated
    not_checked = []
    bad_files = []
    for other_file in to_test:
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
