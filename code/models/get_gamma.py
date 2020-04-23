#!/usr/bin/env python
# coding: utf-8

import numpy as np

import pandas as pd
from src import utils as cutil

# range of delays between "no longer infectious" and "confirmed recovery" to test
RECOVERY_DELAYS = range(15)


def main():

    print("Estimating removal rate (gamma) from CHN and KOR timeseries...")
    ## load korea from regression-ready data
    df_kor = pd.read_csv(
        cutil.DATA_PROCESSED / "adm1" / "KOR_processed.csv", parse_dates=["date"]
    )
    df_kor["name"] = df_kor.adm0_name + "_" + df_kor.adm1_name
    df_kor = df_kor.set_index(["name", "date"])

    ## load china from regression-ready data
    df_chn = pd.read_csv(
        cutil.DATA_PROCESSED / "adm2" / "CHN_processed.csv", parse_dates=["date"]
    )
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
    cases_I_midpoint = (
        df["active_cases"] + df.groupby(level="name")["active_cases"].shift(1)
    ) / 2

    # filter where the timestep was not 1 day
    bds = bds[tstep_bd == 1]
    cases_I_midpoint = cases_I_midpoint[tstep_bd == 1]
    new_recovered = bds.cum_recoveries + bds.cum_deaths

    out = pd.Series(
        index=pd.MultiIndex.from_product(
            (("CHN", "KOR", "pooled"), RECOVERY_DELAYS),
            names=["adm0_name", "recovery_delay"],
        ),
        name="gamma",
        dtype=np.float64,
    )

    for l in RECOVERY_DELAYS:

        # shift recoveries making sure we deal with any missing days
        # this gives us the number of confirmed recoveries at t+l,
        # which is equivalent to the number of people we assume are leaving
        # the infectious group at time t
        recoveries_lag = bds.cum_recoveries.reindex(
            pd.MultiIndex.from_arrays(
                [
                    bds.cum_recoveries.index.get_level_values("name"),
                    bds.cum_recoveries.index.get_level_values("date").shift(l, "D"),
                ]
            )
        ).values
        recoveries_lag = pd.Series(recoveries_lag, index=bds.cum_recoveries.index)
        numerator = bds.cum_deaths + recoveries_lag

        # remove any confirmed recoveries that occur between now and t+l from the
        # denominator (active cases) b/c we assume they have already recovered
        fut_recovered = df.cum_recoveries.reindex(
            pd.MultiIndex.from_arrays(
                [
                    df.index.get_level_values("name"),
                    df.index.get_level_values("date").shift(l, "D"),
                ]
            )
        ).values
        fut_recovered = pd.Series(fut_recovered, index=df.index)
        cases_already_removed = fut_recovered - df.cum_recoveries
        this_cases = cases_I_midpoint - (cases_already_removed)

        gammas_bd = numerator / this_cases

        # filter out 0 gammas (assume not reliable data e.g. from small case numbers)
        gamma_filter = gammas_bd > 0
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
                gammas_bd_filtered.index.get_level_values("name").map(
                    lambda x: "CHN" in x
                )
            ].median(),
            gammas_bd_filtered[
                gammas_bd_filtered.index.get_level_values("name").map(
                    lambda x: "KOR" in x
                )
            ].median(),
        )

        g_pooled = gammas_bd_filtered.median()
        out.loc["CHN", l] = g_chn
        out.loc["KOR", l] = g_kor
        out.loc["pooled", l] = g_pooled

    cutil.MODELS.mkdir(exist_ok=True, parents=True)
    out.to_csv(cutil.MODELS / "gamma_est.csv", index=True)


if __name__ == "__main__":
    main()
