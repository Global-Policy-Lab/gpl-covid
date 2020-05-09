from src import utils as cutil
import pandas as pd
import operator
import json
import argparse

parser = argparse.ArgumentParser()

parser.add_argument(
    "--c",
    choices=sorted(cutil.ISOS),
    default=None,
    type=str.upper,
    help="Country ISO code",
)

parser.add_argument("--l", default=False, action="store_true", help="Print logs")

args = parser.parse_args()
print_logs = args.l


def get_country_list(country_input):
    if country_input != None:
        return [country_input]
    return cutil.ISOS


country_list = get_country_list(args.c)


def get_preprocessed_datasets():
    # Read each country's preprocessed datasets into `preprocessed`
    preprocessed = dict()

    for country in country_list:
        preprocessed[country] = dict()
        for adm in ["adm0", "adm1", "adm2"]:
            path_preprocessed = (
                cutil.DATA_PREPROCESSED / f"{adm}" / f"{country}_processed.csv"
            )
            if path_preprocessed.exists():
                preprocessed[country][str(adm)] = path_preprocessed

    return preprocessed


with open(
    cutil.DATA_RAW / "multi_country" / "policy_implication_rules.json", "r"
) as js:
    implies_dict = json.load(js)

op_dict = {
    ">": operator.gt,
    "<": operator.lt,
    ">=": operator.ge,
    "<=": operator.le,
    "=": operator.eq,
}


def apply_rule(df, src_policy, op_str, src_val, dst_rule):
    dst_policy, dst_val = dst_rule

    src_policy_cols = [c for c in df.columns if c.startswith(src_policy)]

    # Get operator function from operator string
    op = op_dict[op_str]

    for src_col in src_policy_cols:
        suffix = src_col[len(src_policy) :]
        dst_col = dst_policy + suffix

        if dst_col not in df.columns:
            continue

        df.loc[op(df[src_col], src_val), dst_col] = dst_val
        if print_logs:
            print(f"where {src_col} {op_str} {src_val}, set {dst_col} = {dst_val}")

    return df


def apply_implies(df, implies):
    for rule in implies:
        # Parse a single rule
        src_policy, op_str, src_val, dst_rules_list = rule

        # For each destination policy, set the appropriate value based on the source
        for dst_rule in dst_rules_list:
            df = apply_rule(df, src_policy, op_str, src_val, dst_rule)

    return df


def process_file(f, country_code, adm):
    out_path = cutil.DATA_PROCESSED / adm / f"{country_code}_processed.csv"
    df = pd.read_csv(f)

    if country_code in implies_dict:
        implies = implies_dict[country_code]
        df = apply_implies(df, implies)

    df = df.round(9)
    df.to_csv(out_path, index=False)


def main():
    preprocessed_files = get_preprocessed_datasets()
    for country_code in preprocessed_files:
        for adm in preprocessed_files[country_code]:
            process_file(preprocessed_files[country_code][adm], country_code, adm)


if __name__ == "__main__":
    main()
