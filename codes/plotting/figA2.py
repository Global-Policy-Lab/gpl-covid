import pandas as pd
import matplotlib.pyplot as plt
import warnings
from urllib.error import HTTPError

import matplotlib
import datetime
import matplotlib.dates as mdates
import codes.utils as cutil

matplotlib.rcParams["pdf.fonttype"] = 42
matplotlib.rcParams["axes.linewidth"] = 2


def main():
    out_dir = cutil.HOME / "results" / "figures" / "appendix"
    out_dir.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(cutil.DATA_PROCESSED / "adm2" / "CHN_processed.csv")
    df.loc[:, "date"] = pd.to_datetime(df["date"])

    # Validate with JHU provincial data

    # validate with JHU
    url = (
        "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/"
        "csse_covid_19_data/csse_covid_19_time_series/"
        "time_series_covid19_confirmed_global.csv"
    )
    try:
        jhu = pd.read_csv(url)
    except HTTPError:
        warnings.warn(
            "JHU data no longer available at URL. Unable to scrape data for Fig A2."
        )
        return None
    jhu = jhu.loc[jhu["Country/Region"] == "China", :].copy()
    jhu = jhu.drop(columns=["Country/Region", "Lat", "Long"])
    jhu = jhu.rename({'Province/State': 'adm1_name'}, axis=1)
    jhu = jhu.melt(
        id_vars=["adm1_name"],
        var_name="date",
        value_name="cum_confirmed_cases_JHU",
    )
    jhu.loc[:, "date"] = pd.to_datetime(jhu["date"])
    jhu.set_index("adm1_name", inplace=True)

    # agg for visualization
    df_viz = (
        df.groupby(["adm1_name", "date"])
        .sum()
        .reset_index()
        .set_index(["adm1_name"])
    )
    df_viz = df_viz.loc[:, ["date", 'cum_confirmed_cases_imputed']].copy()
    df_viz = df_viz.rename({'cum_confirmed_cases_imputed': 'cum_confirmed_cases_ours'}, axis=1)

    # plot visualization
    fig, ax = plt.subplots(nrows=2, ncols=2, figsize=(8, 6), sharex=True)
    for i, province_viz in enumerate(["Hubei", "Zhejiang", "Guangdong", "Henan"]):
        ax_i = ax[i // 2, i % 2]
        jhu.loc[province_viz, :].plot(
            x="date",
            y="cum_confirmed_cases_JHU",
            alpha=0.3,
            ax=ax_i,
            linewidth=3,
            color="dimgray",
            legend=False,
        )
        df_viz.loc[province_viz, :].plot(
            x="date",
            y="cum_confirmed_cases_ours",
            style=".",
            alpha=1,
            ax=ax_i,
            color="dimgray",
            marker="o",
            markeredgecolor="none",
            markersize=3,
            legend=False,
        )
        # df_viz.loc[province_viz, :].plot(x='date', y='cum_recoveries', ax=ax)
        # df_viz.loc[province_viz, :].plot(x='date', y='cum_deaths', ax=ax)
        ax_i.set_title(province_viz)
        ax_i.xaxis.set_major_formatter(mdates.DateFormatter(""))
        ax_i.set_xlabel("")
        ax_i.spines["top"].set_visible(False)
        ax_i.spines["right"].set_visible(False)
        ax_i.spines["bottom"].set_color("dimgray")
        ax_i.spines["left"].set_color("dimgray")
        ax_i.tick_params(direction="out", length=6, width=2, colors="dimgray")
        x_ticks = [20200110, 20200210, 20200310, 20200407]
        x_ticklabels = ["Jan 10", "Feb 10", "Mar 10", "Apr 7"]
        x_ticks = [datetime.datetime.strptime(str(x), "%Y%m%d") for x in x_ticks]
        ax_i.minorticks_off()
        ax_i.set_xticks(x_ticks)
        ax_i.set_xticklabels(x_ticklabels)
    fig.tight_layout()
    fig.savefig(out_dir / "figA2-1.pdf")

    df_kor = pd.read_csv(cutil.DATA_INTERIM / "korea" / "KOR_JHU_data_comparison.csv")
    df_kor.loc[:, "date"] = pd.to_datetime(df_kor["date"])
    df_kor = df_kor.rename({'cum_confirmed_cases_data': 'cum_confirmed_cases_ours'}, axis=1)

    # plot visualization
    fig, ax_i = plt.subplots(figsize=(4, 3))
    df_kor.plot(
        x="date",
        y="cum_confirmed_cases_JHU",
        alpha=0.3,
        ax=ax_i,
        linewidth=3,
        color="dimgray",
        legend=False,
    )
    df_kor.plot(
        x="date",
        y="cum_confirmed_cases_ours",
        style=".",
        alpha=1,
        ax=ax_i,
        color="dimgray",
        marker="o",
        markeredgecolor="none",
        markersize=3,
        legend=False,
    )
    # df_viz.loc[province_viz, :].plot(x='date', y='cum_recoveries', ax=ax)
    # df_viz.loc[province_viz, :].plot(x='date', y='cum_deaths', ax=ax)
    ax_i.set_title("Korea")
    ax_i.xaxis.set_major_formatter(mdates.DateFormatter(""))
    ax_i.set_xlabel("")
    ax_i.spines["top"].set_visible(False)
    ax_i.spines["right"].set_visible(False)
    ax_i.spines["bottom"].set_color("dimgray")
    ax_i.spines["left"].set_color("dimgray")
    ax_i.tick_params(direction="out", length=6, width=2, colors="dimgray")
    x_ticks = [20200122, 20200220, 20200320, 20200406]
    x_ticklabels = ["Jan 22", "Feb 20", "Mar 20", "Apr 6"]
    x_ticks = [datetime.datetime.strptime(str(x), "%Y%m%d") for x in x_ticks]
    ax_i.set_xticks(x_ticks)
    ax_i.set_xticklabels(x_ticklabels)
    ax_i.minorticks_off()
    fig.tight_layout()
    fig.savefig(out_dir / "figA2-2.pdf")

    out_dir_csv = str(cutil.HOME / "results" / "source_data" / "ExtendedDataFigure2.csv")
    df_chn = pd.merge(df_viz, jhu, how='inner', on=['adm1_name', 'date'])
    pd.concat([
        df_chn.assign(
            adm0_name='CHN',
            adm1_name=df_chn.index),
        df_kor.assign(adm0_name='KOR'),
    ], sort=False).to_csv(out_dir_csv, index=False)


if __name__ == "__main__":
    main()
