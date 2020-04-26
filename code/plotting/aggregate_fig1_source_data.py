import pandas as pd

import src.utils as cutil

out_dir = cutil.RESULTS / "source_data"
source_dir = out_dir / "indiv"

files = (source_dir).glob("fig1_*.csv")
dfs = []
names = []
for f in files:
    dfs.append(pd.read_csv(f, index_col=0))
    names.append(f.stem)

with pd.ExcelWriter(out_dir / "Figure1_data.xlsx") as writer:
    for ix, i in enumerate(dfs):
        i.to_excel(writer, index=False, sheet_name=names[ix], float_format="%.3f")
