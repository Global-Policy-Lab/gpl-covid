from codes import utils as cutil
import pandas as pd
import numpy as np


## load korea from regression-ready data
df_kor = pd.read_csv(cutil.REG_DATA / "KOR_reg_data.csv", parse_dates=["date"])
df_kor["name"] = df_kor.adm0_name + "_" + df_kor.adm1_name
df_kor = df_kor.set_index(["name", "date"])


## load china from regression-ready data
df_chn = pd.read_csv(cutil.REG_DATA / "CHN_reg_data.csv", parse_dates=["date"])
df_chn["name"] = df_chn.adm0_name + "_" + df_chn.adm1_name + "_" + df_chn.adm2_name
df_chn = df_chn.set_index(["name", "date"])


## combine
df_in = df_kor.append(df_chn)
# make sure we have datetime type
df_in = df_in.reset_index("date", drop=False).set_index(
    pd.to_datetime(df_in.index.get_level_values("date")), append=True
)


## prep dataset
df = df_in[
    (df_in["cum_confirmed_cases"] >= cutil.CUM_CASE_MIN_FILTER)
    & (df_in["active_cases"] > 0)
]
df = df.sort_index()
df = df.select_dtypes("number")

# calculate timesteps (bd=backward finite diff)
tstep = (
    df.index.get_level_values("date")[1:] - df.index.get_level_values("date")[:-1]
).days
tstep_bd = tstep.insert(0, np.nan)

bds = df.groupby(level="name").diff(1)

bd_cases_I_midpoint = (
    df["active_cases"] + df.groupby(level="name")["active_cases"].shift(1)
) / 2

gammas_bd = (bds["cum_confirmed_cases"] - bds.active_cases) / bd_cases_I_midpoint

# filter out 0 gammas (assume not reliable data e.g. from small case numbers)
# and filter out where we have missing dates between obs
gamma_filter = (gammas_bd > 0) & (tstep_bd == 1)
gammas_bd_filtered = gammas_bd[gamma_filter]


# if you want to weight by active cases
# (decided not to to avoid potential bias in giving longer duration cases more weight)
# weights = df["active_cases"]
# weights_bd = (weights + weights.groupby(level="name").shift(1)) / 2
# weights_bd = weights_bd[gamma_filter]
# weights_bd = weights_bd / weights_bd.mean()
# gammas_bd_filtered = gammas_bd_filtered * weights_bd * n_samples

g_chn, g_kor = (
    gammas_bd_filtered[
        gammas_bd_filtered.index.get_level_values("name").map(lambda x: "CHN" in x)
    ].median(),
    gammas_bd_filtered[
        gammas_bd_filtered.index.get_level_values("name").map(lambda x: "KOR" in x)
    ].median(),
)

g_pooled = gammas_bd_filtered.median()

pd.Series(
    [g_chn, g_kor, g_pooled],
    index=pd.Index(["CHN", "KOR", "pooled"], name="adm0_name"),
    name="gamma_est",
).to_csv(cutil.MODELS / "gamma_est.csv", index=True)
