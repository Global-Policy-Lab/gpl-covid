import datetime
import os

import matplotlib.colors
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

import codes.utils as cutil

# save the figure here
save_fig = True
save_data = True

fig_dir = cutil.HOME / "results" / "figures" / "fig4"
fig_data_dir = cutil.HOME / "results" / "source_data"
fig_data_fn = "Figure4_data.csv"


fig_dir.mkdir(parents=True, exist_ok=True)
fig_name = "fig4.pdf"

# for nice exporting to illustrator
matplotlib.rcParams["pdf.fonttype"] = 42

# figure aesthetics
no_policy_color = "red"
policy_color = "blue"
matplotlib.rcParams["font.sans-serif"] = "Arial"
matplotlib.rcParams["font.family"] = "sans-serif"

# column indices for prediction data
pred_no_pol_key = "predicted_cum_confirmed_cases_no_policy"
pred_pol_key = "predicted_cum_confirmed_cases_true"

data_dir = cutil.MODELS / "projections"
fn_template = os.path.join(data_dir, "{0}_bootstrap_projection.csv")

countries_in_order = ["china", "korea", "italy", "iran", "france", "usa"]

country_names = {
    "france": "France",
    "iran": "Iran",
    "usa": "United States",
    "italy": "Italy",
    "china": "China",
    "korea": "South Korea",
}


cutoff_dates = pd.read_csv(
    cutil.HOME / "codes" / "data" / "cutoff_dates.csv"
).set_index("tag")
cutoff_end = str(cutoff_dates.loc["default", "end_date"])
end_date = "{0}-{1}-{2}".format(cutoff_end[0:4], cutoff_end[4:6], cutoff_end[6:8])
start_date = "2020-01-15"


def color_add_alpha(color, alpha):
    color_rgba = list(matplotlib.colors.to_rgba(color))
    color_rgba[3] = alpha
    return color_rgba


def plot_quantiles(ax, quantiles, quantiles_dict, legend_dict, model, update_legend):
    if ax is None:
        fig, ax = plt.subplots(figsize=(10, 10))

    dates = quantiles_dict["dates"]

    quantiles_no_policy = quantiles_dict["quantiles_no_policy"]
    quantiles_policy = quantiles_dict["quantiles_policy"]

    if model is not None:
        dates_model = pd.to_datetime(model["date"])
        preds_policy = model["predicted_cum_confirmed_cases_true"]
        preds_no_policy = model["predicted_cum_confirmed_cases_no_policy"]

    num_ranges = int(len(quantiles) / 2)

    upper_idx = -1
    lower_idx = 0

    # inner to outer - hardcode for now
    alphas_fc = [0.2, 0.5]

    if model is not None:
        model_no_pol = ax.plot(
            dates_model, preds_no_policy, color=no_policy_color, lw=5, ls="--"
        )

        if update_legend:
            legend_dict["lines"].append(model_no_pol[0])
            legend_dict["labels"].append('"No policy" scenario')

    for i in range(num_ranges):
        if i >= 0:
            l_no_pol = ax.fill_between(
                pd.to_datetime(dates),
                quantiles_no_policy[:, lower_idx],
                quantiles_no_policy[:, upper_idx],
                facecolor=color_add_alpha(no_policy_color, alphas_fc[i]),
                #  edgecolor=color_add_alpha(no_policy_color, alphas_ec[i]),
                #   alpha = alphas_fc[i],
            )

            if update_legend:
                legend_dict["lines"].append(l_no_pol)
                legend_dict["labels"].append(
                    "{0}% interval".format(
                        int(100 * (quantiles[upper_idx] - quantiles[lower_idx]))
                    )
                )

        lower_idx += 1
        upper_idx -= 1

    if model is not None:
        model_pol = ax.plot(
            dates_model, preds_policy, color=policy_color, lw=5, ls="--"
        )

        if update_legend:
            legend_dict["lines"].append(model_pol[0])
            legend_dict["labels"].append("Actual policies (predicted)")

    # reset
    upper_idx = -1
    lower_idx = 0

    for i in range(num_ranges):
        if i >= 0:
            l_pol = ax.fill_between(
                pd.to_datetime(dates),
                quantiles_policy[:, lower_idx],
                quantiles_policy[:, upper_idx],
                facecolor=color_add_alpha(policy_color, alphas_fc[i]),
                # edgecolor=color_add_alpha(policy_color, alphas_ec[i]),
            )

            if update_legend:
                legend_dict["lines"].append(l_pol)
                legend_dict["labels"].append(
                    "{0}% interval".format(
                        int(100 * (quantiles[upper_idx] - quantiles[lower_idx]))
                    )
                )

        lower_idx += 1
        upper_idx -= 1

    return ax


def plot_cases(ax, this_country_cases, legend_dict, update_legend):
    if ax is None:
        fig, ax = plt.subplots()

    dates_cases = pd.to_datetime(this_country_cases["date"])
    cases = this_country_cases["cases"].values

    case_scatter = ax.scatter(
        dates_cases.values, cases, marker="o", color="black", s=36, clip_on=False
    )
    if update_legend:
        legend_dict["lines"].append(case_scatter)
        legend_dict["labels"].append("Cumulative observed cases")

    return ax


def plot_model(ax, this_country_model, legend_dict, update_legend):
    if ax is None:
        fig, ax = plt.subplots()

    dates = pd.to_datetime(this_country_model["date"])
    preds_policy = this_country_model["predicted_cum_confirmed_cases_true"]
    preds_no_policy = this_country_model["predicted_cum_confirmed_cases_no_policy"]

    l_pol = ax.plot(dates, preds_policy, color=policy_color, lw=3, ls="--")

    l_no_pol = ax.plot(dates, preds_no_policy, color=no_policy_color, lw=3, ls="--")

    if update_legend:
        legend_dict["lines"].append(l_pol)
        legend_dict["lines"].append(l_no_pol)

        legend_dict["labels"].append("Prediction with policy")
        legend_dict["labels"].append("Prediction no policy")

    return ax


def make_quantiles(this_country_df, quantiles):
    df_by_date = this_country_df.groupby("date")
    quantiles_array_policy = np.zeros((len(df_by_date.groups.keys()), len(quantiles)))
    quantiles_array_no_policy = np.zeros(
        (len(df_by_date.groups.keys()), len(quantiles))
    )

    for d, date_idx in enumerate(df_by_date.groups.keys()):
        this_day = df_by_date.get_group(date_idx)

        for q, quantile in enumerate(quantiles):
            quantiles_array_policy[d, q] = np.quantile(
                this_day["predicted_cum_confirmed_cases_true"], quantile
            )
            quantiles_array_no_policy[d, q] = np.quantile(
                this_day["predicted_cum_confirmed_cases_no_policy"], quantile
            )

    dates = pd.to_datetime(list(df_by_date.groups.keys()))

    return dates, quantiles_array_policy, quantiles_array_no_policy


def plot_bracket(ax, model_df):
    # most recent case
    last_model_day = model_df["date"].max()

    start = (
        mdates.date2num(pd.to_datetime(last_model_day) + datetime.timedelta(days=1.5)),
        model_df.loc[model_df["date"] == last_model_day, pred_pol_key].values[0],
    )

    start_cap = (
        mdates.date2num(pd.to_datetime(last_model_day) + datetime.timedelta(days=1)),
        model_df.loc[model_df["date"] == last_model_day, pred_pol_key].values[0],
    )

    end = (
        mdates.date2num(pd.to_datetime(last_model_day) + datetime.timedelta(days=1.5)),
        model_df.loc[model_df["date"] == last_model_day, pred_no_pol_key].values[0],
    )

    end_cap = (
        mdates.date2num(pd.to_datetime(last_model_day) + datetime.timedelta(days=1)),
        model_df.loc[model_df["date"] == last_model_day, pred_no_pol_key].values[0],
    )

    # geometric mean is middle b/c log space
    text_spot_start = (
        mdates.date2num(pd.to_datetime(last_model_day) + datetime.timedelta(days=1.5)),
        np.sqrt(start[1] * end[1]),
    )
    text_spot_end = (
        mdates.date2num(pd.to_datetime(last_model_day) + datetime.timedelta(days=3)),
        np.sqrt(start[1] * end[1]),
    )

    # put line
    ax.arrow(start[0], start[1], 0, end[1] - start[1], lw=2, clip_on=False)
    # put caps
    ax.arrow(
        start_cap[0], start_cap[1], start[0] - start_cap[0], 0, lw=2, clip_on=False
    )
    ax.arrow(end_cap[0], end_cap[1], end[0] - end_cap[0], 0, lw=2, clip_on=False)

    # rounds to the nearest 1,000
    # num_rounded = int(round(end[1] - start[1], -3))
    num_rounded = int(float("{0:.2}".format(end[1] - start[1])))
    annot = "~{0:,d} fewer\nestimated cases".format(num_rounded)
    # put text
    ax.annotate(
        annot,
        xy=text_spot_start,
        xytext=text_spot_end,
        annotation_clip=False,
        fontsize=30,
        va="center",
    )


def annotate_cases(ax, cases):
    # get most recent case
    lastest_cases_date = cases["date"].max()

    cases_last = cases[cases["date"] == lastest_cases_date]["cases"].values[0]
    cases_date = pd.to_datetime(lastest_cases_date)

    cases_pos = (mdates.date2num(cases_date), cases_last)

    # divide for even spacing in log scale
    text_pos = (
        mdates.date2num(cases_date + datetime.timedelta(days=2)),
        cases_last / 100.0,
    )

    annot_date = cases_date.strftime("%b %d")

    annot = "{0}: {1:,d} \nconfirmed cases".format(annot_date, int(cases_last))
    ax.annotate(
        annot,
        xy=cases_pos,
        xytext=text_pos,
        annotation_clip=False,
        fontsize=30,
        va="center",
        arrowprops={
            "arrowstyle": "->",
            "shrinkA": 10,
            "shrinkB": 10,
            "connectionstyle": "arc3,rad=0.3",
            "color": "black",
            "lw": 1.5,
        },
    )


def main():

    # initialize the dataframes that will get filled in
    dfs_by_country = [
        pd.DataFrame(
            {
                "country": country_names[c],
                "date": pd.date_range(start_date, end_date, freq="D"),
            }
        )
        for c in countries_in_order
    ]

    # read in all the cases data
    cases_dict = cutil.load_all_cases_deaths(cases_drop=True)

    # save that data
    for c, country in enumerate(countries_in_order):

        cases_df_this_country = cases_dict[country]

        dfs_by_country[c] = pd.merge(
            dfs_by_country[c].set_index("date", drop=False),
            cases_df_this_country.set_index("date"),
            left_index=True,
            right_index=True,
            how="left",
        )

    resampled_dfs_by_country = {}
    for country in countries_in_order:
        print("reading ", fn_template.format(country))
        resampled_dfs_by_country[country] = pd.read_csv(fn_template.format(country))

    # get central estimates
    model_dfs_by_country = {}
    for c, country in enumerate(countries_in_order):
        model_df_this_country = pd.read_csv(
            fn_template.replace("bootstrap", "model").format(country)
        )

        model_dfs_by_country[country] = model_df_this_country

        dfs_by_country[c] = pd.merge(
            dfs_by_country[c],
            model_df_this_country.set_index("date"),
            left_index=True,
            right_index=True,
            how="left",
        )

    # get quantile data
    quantiles = [0.025, 0.15, 0.85, 0.975]  # 95% range  # 70% range

    quantiles_by_country = {}
    for c, country in enumerate(countries_in_order):
        quantile_this_country = {}
        dates, quantiles_policy, quantiles_no_policy = make_quantiles(
            resampled_dfs_by_country[country], quantiles
        )

        quantile_this_country["dates"] = dates
        quantile_this_country["quantiles_policy"] = quantiles_policy
        quantile_this_country["quantiles_no_policy"] = quantiles_no_policy
        quantiles_by_country[country] = quantile_this_country

        # make a small df for this quantile so we can merge on date
        quantiles_this_country_dict = {}
        for q, quantile in enumerate(quantiles):
            key_start = "quantile_{0}_".format(quantile)
            quantiles_this_country_dict[key_start + "policy"] = quantiles_policy[:, q]
            quantiles_this_country_dict[key_start + "no_policy"] = quantiles_no_policy[
                :, q
            ]

        quantile_df = pd.DataFrame(
            quantiles_this_country_dict, index=pd.to_datetime(dates)
        )

        dfs_by_country[c] = pd.merge(
            dfs_by_country[c],
            quantile_df,
            how="left",
            left_index=True,
            right_index=True,
        )

    # plot
    fig, ax = plt.subplots(
        len(countries_in_order),
        figsize=(15, 7 * len(countries_in_order)),
        sharex=True,
        sharey=True,
    )

    legend_dict = {"lines": [], "labels": []}

    for c, country in enumerate(countries_in_order):
        # 1.a plot quantiles and model
        quantiles_this_country = quantiles_by_country[country]
        model_this_country = model_dfs_by_country[country]

        ax[c] = plot_quantiles(
            ax[c],
            quantiles,
            quantiles_this_country,
            legend_dict,
            model=model_this_country,
            update_legend=(c == 0),
        )

        # 1.b annotate the model on the right
        plot_bracket(ax[c], model_this_country)

        # 2.a plot cases where they overlap with predictions
        cases_this_country = cases_dict[country]
        cases_overlap_preds_mask = cases_this_country["date_str"].apply(
            lambda x: x in model_this_country["date"].values
        )
        cases_overlapping_predictions = cases_this_country.where(
            cases_overlap_preds_mask
        )
        ax[c] = plot_cases(
            ax[c], cases_overlapping_predictions, legend_dict, update_legend=(c == 0)
        )

        # 2.b annotate cases
        annotate_cases(ax[c], cases_overlapping_predictions)

        # 3. set title and axis labels
        ax[c].set_title(
            country_names[country],
            fontsize=44,
            verticalalignment="baseline",
            loc="center",
        )

        ax[c].set_ylabel("Predicted cumulative \ncases", fontsize=32)
        ax[c].set_yscale("log")

        ax[c].set_xlim(np.datetime64(start_date), np.datetime64(end_date))

        ax[c].set_ylim(10, 1e8)

        # dates on x axis
        days_all = mdates.DayLocator(interval=1)
        days_sparse = mdates.DayLocator(interval=10)
        formatter = mdates.DateFormatter("%b %d")

        ax[c].xaxis.set_major_formatter(formatter)
        ax[c].xaxis.set_minor_locator(days_all)
        ax[c].xaxis.set_major_locator(days_sparse)

        # set to mostly match fig 3
        ax[c].tick_params(axis="x", which="major", labelsize=28, length=10, width=4)
        ax[c].tick_params(axis="x", which="minor", length=5, width=1.5)
        ax[c].tick_params(axis="y", which="major", labelsize=26, length=8, width=1)

        ax[c].tick_params(axis="y", which="minor", labelsize=26, length=5, width=0.1)
        ax[c].set_yticks(ax[c].get_yticks(minor=True)[::5], minor=True)
        ax[c].set_yticks(np.logspace(1, 8, base=10, num=8))

        sns.despine(ax=ax[c], top=True)
        sns.despine(ax=ax[c], top=True)

        # thicken the axes
        plt.setp(ax[c].spines.values(), linewidth=2)
        ax[c].grid(lw=1)

    # add a legend axis
    leg_ax = fig.add_axes([1.0, 0.6, 0.2, 0.2])

    leg = leg_ax.legend(
        handles=legend_dict["lines"],
        labels=legend_dict["labels"],
        loc=(0.42, 0.82),
        fontsize=32,
        title="Legend",
        frameon=False,
        markerscale=3,
    )

    leg._legend_box.align = "left"
    plt.setp(leg.get_title(), fontsize=44)

    leg_ax.axis("off")

    df_all_countries = pd.concat(dfs_by_country).drop(["date_str"], axis=1)

    if save_data:
        out_fn = fig_data_dir / fig_data_fn
        print("saving fig data in {0}".format(out_fn))
        df_all_countries.to_csv(out_fn, index=False)

    if save_fig:
        out_fn = fig_dir / fig_name
        print("saving fig in {0}".format(out_fn))
        plt.savefig(out_fn, bbox_inches="tight", bbox_extra_artists=(leg,))


if __name__ == "__main__":
    main()
