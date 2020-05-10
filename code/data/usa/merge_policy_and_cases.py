import os

import pandas as pd

import src.merge as merge
import src.utils as cutil

raw_data_dir = str(cutil.DATA_RAW / "usa")
int_data_dir = str(cutil.DATA_INTERIM / "usa")
proc_data_dir = str(cutil.DATA_PROCESSED / "adm1")


def main():

    add_testing_regime = True
    output_csv_name = "USA_processed.csv"
    out_dir = proc_data_dir

    cases_data = pd.read_csv(os.path.join(int_data_dir, "usa_usafacts_state.csv"))
    cases_data["date"] = pd.to_datetime(cases_data["date"])

    # drop any cases data columns that are all null
    cases_data = cases_data.dropna(how="all", axis=1)

    policy_data = pd.read_csv(
        os.path.join(int_data_dir, "USA_policy_data_sources.csv"), encoding="latin"
    )

    # drop any rows which are all nan
    policy_data = policy_data.dropna(how="all", axis=0)

    policy_data = policy_data.rename(columns={"Optional": "optional"})
    policy_data = policy_data.rename(columns={"date": "date_start"})

    policy_data.loc[:, "date_start"] = pd.to_datetime(policy_data["date_start"])
    policy_data["date_end"] = pd.to_datetime("2099-12-31")

    df_merged = merge.assign_policies_to_panel(cases_data, policy_data, 1, method="USA")

    if add_testing_regime:
        testimg_regime_csv = os.path.join(
            int_data_dir, "usa_states_covidtrackingdotcom_int_with_testing_regimes.csv"
        )
        testing_regime_data = pd.read_csv(testimg_regime_csv).loc[
            :, ["date", "adm1_name", "testing_regime"]
        ]
        testing_regime_data["date"] = pd.to_datetime(testing_regime_data["date"])

        # drop the old testing_regime category
        df_merged = df_merged.drop(["testing_regime"], axis=1)

        merged_with_policy = pd.merge(
            df_merged,
            testing_regime_data,
            how="left",
            left_on=["date", "adm1_name"],
            right_on=["date", "adm1_name"],
        )

        # sort by date, then forward fill; the rest should be 0
        merged_with_policy = merged_with_policy.sort_values("date")
        merged_with_policy["testing_regime"] = merged_with_policy[
            "testing_regime"
        ].fillna(method="ffill")
        # anything left over should have a zero
        merged_with_policy["testing_regime"] = merged_with_policy[
            "testing_regime"
        ].fillna(0)

        df_merged = merged_with_policy

    else:
        output_csv_name = output_csv_name.replace(".csv", "no_testing_regime.csv")
        out_dir = int_data_dir

    # publish
    print(
        "writing merged policy and cases data to ",
        os.path.join(out_dir, output_csv_name),
    )
    df_merged.to_csv(os.path.join(out_dir, output_csv_name), index=False)


if __name__ == "__main__":
    main()
