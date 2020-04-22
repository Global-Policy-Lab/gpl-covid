import os

import numpy as np

import codes.utils as cutil
import pandas as pd

countries_in_order = ["china", "korea", "italy", "iran", "france", "usa"]

country_abbrievations = {
    "france": "FRA",
    "iran": "IRN",
    "usa": "USA",
    "italy": "ITA",
    "china": "CHN",
    "korea": "KOR",
}

cutoff_dates = pd.read_csv(
    cutil.HOME / "codes" / "data" / "cutoff_dates.csv"
).set_index("tag")
cutoff_end = str(cutoff_dates.loc["default", "end_date"])
end_date = "{0}-{1}-{2}".format(cutoff_end[0:4], cutoff_end[4:6], cutoff_end[6:8])
start_date = "2020-01-15"

# country specfic cutoff dates
cutoff_dates_by_country = {}
for country in countries_in_order:
    key_this_country = "{0}_analysis".format(country_abbrievations[country])

    if key_this_country in cutoff_dates.index:
        cutoff_this_country = str(cutoff_dates.loc[key_this_country, "end_date"])
        cutoff_dates_by_country[country] = "{0}-{1}-{2}".format(
            cutoff_this_country[0:4], cutoff_this_country[4:6], cutoff_this_country[6:8]
        )
    else:
        cutoff_dates_by_country[country] = end_date


def aggregate_preds_by_country(
    countries, resampled_dfs_by_country, pred_key, latest_dates
):
    for c, country in enumerate(countries):
        # use the most recent date for this country
        date_this = latest_dates[c]
        df_this = resampled_dfs_by_country[country]

        if c == 0:
            # seed the big df with 0th country
            df_this_key = resampled_dfs_by_country[countries[c]]
            # take date and preds
            df_this_key = df_this[df_this["date"] == date_this][
                ["date", pred_key]
            ].reset_index(drop=True)

        else:
            # append
            df_this_day = df_this[df_this["date"] == date_this][[pred_key]].reset_index(
                drop=True
            )
            df_this_key = df_this_key.merge(
                df_this_day,
                left_index=True,
                right_index=True,
                suffixes=("", "_" + country),
            )

    # add the first country back in as a suffix
    df_this_key = df_this_key.rename(
        columns={pred_key: pred_key + "_{0}".format(countries[0])}
    )

    # sum across countries and add to the data frame
    country_columns = [pred_key + "_{0}".format(c) for c in countries]
    df_this_key["sum_across_countries"] = df_this_key[country_columns].sum(axis=1)

    return df_this_key


def main():

    # 1. read cases data
    cases_dict = cutil.load_all_cases_deaths(cases_drop=False)

    # 2. read in the central model estimates and the resampled trials
    data_dir = cutil.MODELS / "projections"
    fn_template = os.path.join(data_dir, "{0}_bootstrap_projection.csv")

    countries = ["china", "korea", "italy", "iran", "france", "usa"]

    # get resampled data
    resampled_dfs_by_country = {}
    for country in countries:
        print("reading from ", fn_template.format(country))
        resampled_dfs_by_country[country] = pd.read_csv(fn_template.format(country))

        # print(resampled_dfs_by_country[country].shape)

    # get central estimates
    model_dfs_by_country = {}
    for country in countries:
        model_dfs_by_country[country] = pd.read_csv(
            fn_template.replace("bootstrap", "model").format(country)
        )

    # 3. get most recent predictions by country.

    # specifies keys once caues they're long
    pred_no_pol_key = "predicted_cum_confirmed_cases_no_policy"
    pred_pol_key = "predicted_cum_confirmed_cases_true"

    # these will get filled in
    latest_dates = []
    modeled_no_policy = []
    modeled_with_policy = []
    cases_confirmed = []

    # get central predictions and actual cases
    for country in countries:
        preds_this_country = model_dfs_by_country[country]

        # use the most recent date that we have data for this country
        latest_date_this_country = cutoff_dates_by_country[country]
        latest_dates.append(latest_date_this_country)

        # get predictions without policy
        pred_no_pol = preds_this_country[
            preds_this_country["date"] == latest_date_this_country
        ][pred_no_pol_key].values
        modeled_no_policy.append(pred_no_pol)

        # get predictions with policy
        pred_pol = preds_this_country[
            preds_this_country["date"] == latest_date_this_country
        ][pred_pol_key].values
        modeled_with_policy.append(pred_pol)

        # get confirmed cases (with policy)
        cases_this_country = cases_dict[country]
        cases = cases_this_country[
            cases_this_country["date"] == latest_date_this_country
        ]["cases"].values
        cases_confirmed.append(cases)

    modeled_no_policy = np.array(modeled_no_policy)
    modeled_with_policy = np.array(modeled_with_policy)
    cases_confirmed = np.array(cases_confirmed)

    # report numbers for central predictions and actual cases

    est_diffs_modeled = modeled_no_policy - modeled_with_policy

    # 4. use resampled predictions to get intervals
    df_no_pol_pred = aggregate_preds_by_country(
        countries, resampled_dfs_by_country, pred_no_pol_key, latest_dates
    )

    df_pol_pred = aggregate_preds_by_country(
        countries, resampled_dfs_by_country, pred_pol_key, latest_dates
    )

    # aggregate in this df
    est_diffs_by_country = pd.DataFrame()
    est_nopol_by_country = pd.DataFrame()
    for country in countries:
        pred_no_pol = df_no_pol_pred[pred_no_pol_key + "_" + country]
        pred_pol = df_pol_pred[pred_pol_key + "_" + country]

        est_diffs_by_country[country] = pred_no_pol - pred_pol
        est_nopol_by_country[country] = pred_no_pol

    est_diffs_by_country["all"] = est_diffs_by_country.sum(axis=1)

    small_ends = est_diffs_by_country.quantile(0.025)
    big_ends = est_diffs_by_country.quantile(0.975)

    # print out actual # cases
    # Print out the final form of differences:
    print()
    print("there are:", end="\n")
    for c, country in enumerate(countries):
        print(
            "{0:,} confirmed cases in in {1} (cumulative, on {2}), ".format(
                int(cases_confirmed[c]), country, latest_dates[c],
            ),
            end="\n",
        )

    print("this adds to {0}".format(np.sum(cases_confirmed)))

    print()

    # Print out the final form of differences:
    print()
    print("we estimate that there would be:", end="\n")
    for c, country in enumerate(countries):
        print(
            "{0:,} (95% resample range [{1:,} to {2:,}]) more cases in {3} (cumulative, on {4}), ".format(
                int(est_diffs_modeled[c, 0]),
                int(np.floor(small_ends[c])),
                int(np.ceil(big_ends[c])),
                country,
                latest_dates[c],
            ),
            end="\n",
        )

    print()

    print("we estimate that there would be:", end="\n")

    c_all = len(countries)
    print(
        "{0:,} (95% resample range [{1:,} to {2:,}]) more cases ".format(
            int(est_diffs_modeled[:, 0].sum()),
            int(np.floor(small_ends[c_all])),
            int(np.ceil(big_ends[c_all])),
        ),
        end="",
    )
    print("across countries (accumulated over the specific dates for each countries)")

    # Print predictions for no policy interventions
    est_nopol_by_country["all"] = est_nopol_by_country.sum(axis=1)

    small_ends_no_pol = est_nopol_by_country.quantile(0.025)
    big_ends_no_pol = est_nopol_by_country.quantile(0.975)

    print()
    print("we estimate that there would be:", end="\n")
    for c, country in enumerate(countries):
        print(
            "{0:,} (95% pred_no_pol range [{1:,} to {2:,}]) total cases in {3} (cumulative, on {4}), ".format(
                int(modeled_no_policy[c, 0]),
                int(np.floor(small_ends_no_pol[c])),
                int(np.ceil(big_ends_no_pol[c])),
                country,
                latest_dates[c],
            ),
            end="\n",
        )

    print()
    print("we estimate that there would be:", end="\n")

    c_all = len(countries)
    print(
        "{0:,} (95% resample range [{1:,} to {2:,}]) total cases ".format(
            int(modeled_no_policy[:, 0].sum()),
            int(np.floor(small_ends_no_pol[c_all])),
            int(np.ceil(big_ends_no_pol[c_all])),
        ),
        end="",
    )
    print("across countries (accumulated over the specific dates for each countries)")


if __name__ == "__main__":
    main()
