from pathlib import Path
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

                    
def test_no_data_change():
    path = Path("tests/test_data")
    for p in path.rglob("*"):
        if p.is_file() and not any([l.startswith(".") for l in p.parts]):
            other_file = Path("data").joinpath(*p.parts[2:])
            try:
                pd.testing.assert_frame_equal(pd.read_csv(p), pd.read_csv(other_file))
            except UnicodeDecodeError:
                pass