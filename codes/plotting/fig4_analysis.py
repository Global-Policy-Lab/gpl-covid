import numpy as np
import pandas as pd
import os
import codes.utils as cutil


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
    data_dir = cutil.DATA / "post_processing"
    fn_template = os.path.join(data_dir, "{0}_bootstrap_projection.csv")

    countries = ["china", "korea", "italy", "iran", "france", "usa"]

    # get resampled data
    resampled_dfs_by_country = {}
    for country in countries:
        print("reading from ", fn_template.format(country))
        resampled_dfs_by_country[country] = pd.read_csv(fn_template.format(country))

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
        latest_date_this_country = preds_this_country["date"].max()
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

    est_diffs = modeled_no_policy - modeled_with_policy

    print("estimated diff in cumulative cases using central estimates:")
    for c, country in enumerate(countries):
        print("in {0},".format(country), end=" ")
        print("at day {0},".format(latest_dates[c]), end=" ")
        print(
            "we predict a difference of {0:,} cumulative cases due to to policy".format(
                int(est_diffs[c, 0])
            )
        )

    # total across countries
    # don't actually print this since the predictions end on different days
    # print()
    # est_diffs_with_reported_cases = modeled_no_policy - cases_confirmed

    # print("the estimated total reduction is {0:,}".format(int(est_diffs.sum())))

    # print(
    #     "using actual case (black dots) baseline this number would be {0:,}".format(
    #         int(est_diffs_with_reported_cases.sum()))
    # )

    # print()
    # est_diffs = modeled_no_policy - modeled_with_policy
    # print("checking on predictions vs actual reported cases:")
    # for c, country in enumerate(countries):
    #     print("in {0},".format(country), end=" ")
    #     print("at day {0},".format(latest_dates[c]), end=" ")
    #     print(
    #         "we predict {0:,} cumulative cases; in total there were {1:,}".format(
    #             int(modeled_with_policy[c, 0]), cases_confirmed[c, 0]
    #         )
    #     )
    # print()
    # print("estimated cumulative cases had there been no policies:")
    # for c, country in enumerate(countries):
    #     print("in {0},".format(country), end=" ")
    #     print("at day {0},".format(latest_dates[c]), end=" ")
    #     print(
    #         "we predict there would have been {0:,} had no policies been enacted".format(
    #             int(modeled_no_policy[c, 0])
    #         )
    #    )

    # 4. use resampled predictions to get intervals
    df_no_pol_pred = aggregate_preds_by_country(
        countries, resampled_dfs_by_country, pred_no_pol_key, latest_dates
    )

    df_pol_pred = aggregate_preds_by_country(
        countries, resampled_dfs_by_country, pred_pol_key, latest_dates
    )

    # aggregate in this df
    est_diffs_by_country = pd.DataFrame(df_no_pol_pred["date"].copy())
    for country in countries:
        pred_no_pol = df_no_pol_pred[pred_no_pol_key + "_" + country]
        pred_pol = df_pol_pred[pred_pol_key + "_" + country]

        est_diffs_by_country[country] = pred_no_pol - pred_pol

    est_diffs_by_country["all"] = est_diffs_by_country.sum(axis=1)

    small_ends = est_diffs_by_country.quantile(0.025)
    big_ends = est_diffs_by_country.quantile(0.975)

    # Print out the final form:
    print()
    print("we estimate that there would be:", end="\n")
    for c, country in enumerate(countries):
        print(
            "{0:,} (95% resample range [{1:,} to {2:,}]) more cases in {3} (cumulative, on {4}), ".format(
                int(est_diffs[c, 0]),
                int(np.floor(small_ends[c])),
                int(np.ceil(big_ends[c])),
                country,
                latest_dates[c],
            ),
            end="\n",
        )


if __name__ == "__main__":
    main()
