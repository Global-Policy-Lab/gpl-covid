import pandas as pd
import numpy as np
import src.utils as cutil
import json
import operator
import argparse


def policy_conversion_parser():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--c",
        choices=sorted(cutil.ISOS),
        default=None,
        type=str.upper,
        help="Country ISO code",
    )

    parser.add_argument("--l", default=False, action="store_true", help="Print logs")

    return parser


parser = policy_conversion_parser()

args = parser.parse_args()
print_logs = args.l


def get_country_list(country_input):
    if country_input != None:
        return [country_input]
    return cutil.ISOS


country_list = get_country_list(args.c)

countries_wo_intensity = ["CHN", "IRN"]

op_dict = {
    ">": operator.gt,
    "<": operator.lt,
    ">=": operator.ge,
    "<=": operator.le,
    "=": operator.eq,
}


def apply_rule(df, src_policy, op_str, src_val, dst_rule, country_code):

    dst_policy, dst_val = dst_rule

    # Get operator function from operator string
    op = op_dict[op_str]

    if print_logs:
        print(
            f"{country_code}: where {src_policy} {op_str} {src_val}, set {dst_policy} = {dst_val}"
        )

    mask = df["policy"] == src_policy
    mask = (mask) & (df["optional"] != "Y")
    if country_code not in countries_wo_intensity:
        mask = (mask) & (op(df["policy_intensity"], src_val))

    pcopy = df[mask].copy()

    pcopy["policy"] = dst_policy

    pcopy["implied_policy"] = True

    if country_code not in countries_wo_intensity:
        pcopy["policy_intensity"] = dst_val

    df = pd.concat([df, pcopy], ignore_index=True).sort_values(
        "date_start", ascending=True
    )

    return df


def apply_usa_rule(df, src_policy, dst_policies):
    src_category, src_group = src_policy.split(".")

    intensity_cols = [c for c in df.columns if c.startswith("intensity_group")]
    src_category_mask = df["policy"] == src_category

    psrc = df[src_category_mask].copy()

    src_group_mask = np.zeros_like(psrc.columns[0], dtype=bool)
    for c in intensity_cols:
        src_group_mask = (src_group_mask) | (psrc[c] == src_group)

    psrc = psrc[src_group_mask].copy()

    for dst_policy in dst_policies:
        dst_category, dst_group = dst_policy.split(".")
        pcopy = psrc.copy()
        pcopy["policy"] = dst_category
        pcopy["implied_policy"] = True
        pcopy[intensity_cols[0]] = dst_group
        for c in intensity_cols[1:]:
            pcopy[c] = np.nan

        df = pd.concat([df, pcopy], ignore_index=True).sort_values(
            "date", ascending=True
        )

    return df


def apply_implies(df, implies, country_code):
    for rule in implies:
        if country_code == "USA":
            df = apply_usa_rule(df, rule, implies[rule])
        else:
            src_policy, op_str, src_val, dst_rules_list = rule

            # For each destination policy, set the appropriate value based on the source
            for dst_rule in dst_rules_list:
                df = apply_rule(df, src_policy, op_str, src_val, dst_rule, country_code)

    return df


def read_implies(
    path=cutil.DATA_RAW / "multi_country" / "policy_implication_rules.json",
):
    with open(path, "r") as js:
        implies = json.load(js)
    return implies


def clean_intensities_usa(df):

    drop_mask = df["intensity_group"].astype(str).str.lower().str.startswith("n/a")
    drop_mask = (drop_mask) & (~(df["policy"] == "testing_regime"))
    df = df.drop(df[drop_mask].index)

    intensity_cols = [c for c in df.columns if c.startswith("intensity_group")]
    for c in intensity_cols:
        df[c] = df[c].str.strip()

    return df


def process_country(country_code, implies):
    filename = f"{country_code}_policy_data_sources.csv"
    path_raw = cutil.DATA_RAW / cutil.iso_to_dirname(country_code) / filename
    path_interim = cutil.DATA_INTERIM / cutil.iso_to_dirname(country_code) / filename
    df = pd.read_csv(path_raw, encoding="latin1")
    if country_code not in implies:
        print(f"missing country: {country_code}")
    else:
        print(country_code)
        if country_code == "USA":
            df = clean_intensities_usa(df)

        df["implied_policy"] = False
        df = apply_implies(df, implies[country_code], country_code)
        df = df.reset_index(drop=True)
    df.to_csv(path_interim, index=False, float_format="%.7f")


def main():
    implies = read_implies()
    for country_code in country_list:
        process_country(country_code, implies)


if __name__ == "__main__":
    main()
