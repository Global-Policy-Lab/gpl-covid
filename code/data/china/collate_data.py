from os.path import join

import numpy as np

import geopandas as gpd
import matplotlib.pyplot as plt
import pandas as pd
from src import utils as cutil


def convert_non_monotonic_to_nan(array):
    """Converts a numpy array to a monotonically increasing one.

    Args:
        array (numpy.ndarray [N,]): input array

    Returns:
        numpy.ndarray [N,]: some values marked as missing, all non-missing
            values should be monotonically increasing

    Usage:
        >>> convert_non_monotonic_to_nan(np.array([0, 0, 5, 3, 4, 6, 3, 7, 6, 7, 8]))
        np.array([ 0.,  0., np.nan,  3., np.nan, np.nan,  3., np.nan,  6.,  7.,  8.])
    """
    keep = np.arange(0, len(array))
    is_monotonic = False
    while not is_monotonic:
        is_monotonic_array = np.hstack(
            (array[keep][1:] >= array[keep][:-1], np.array(True))
        )
        is_monotonic = is_monotonic_array.all()
        keep = keep[is_monotonic_array]
    out_array = np.full_like(array.astype(np.float), np.nan)
    out_array[keep] = array[keep]
    return out_array


def log_interpolate(array):
    """Interpolates assuming log growth.

    Args:
        array (numpy.ndarray [N,]): input array with missing values

    Returns:
        numpy.ndarray [N,]: all missing values will be filled

    Usage:
        >>> log_interpolate(np.array([0, np.nan, 2, np.nan, 4, 6, np.nan, 7, 8]))
        np.array([0, 0, 2, 3, 4, 6, 7, 7, 8])
    """
    idx = np.arange(0, len(array))
    log_array = np.log(array.astype(np.float32) + 1e-1)
    interp_array = np.interp(
        x=idx, xp=idx[~np.isnan(array)], fp=log_array[~np.isnan(array)]
    )
    return np.round(np.exp(interp_array)).astype(int)


DATA_CHINA = cutil.DATA_RAW / "china"
health_dxy_file = join(DATA_CHINA, "DXYArea.csv")
health_jan_file = join(DATA_CHINA, "china_city_health_jan.xlsx")
policy_file = join(DATA_CHINA, "CHN_policy_data_sources.csv")
pop_file = join(DATA_CHINA, "china_city_pop.csv")
output_file = cutil.DATA_PROCESSED / "adm2" / "CHN_processed.csv"
match_file = join(DATA_CHINA, "match_china_city_name_w_adm2.csv")
shp_file = cutil.DATA_INTERIM / "adm" / "adm2" / "adm2.shp"

end_date_file = cutil.DATA / "cutoff_dates.csv"

end_date = pd.read_csv(end_date_file)
(end_date,) = end_date.loc[end_date["tag"] == "default", "end_date"].values
end_date = str(end_date)
print("End Date: ", end_date)

## Load and clean pre 01/24 data

# load pre 01/24 data
df_jan = pd.read_excel(health_jan_file, sheet_name=None)

# process pre 1/24 data
df_jan_merged = pd.DataFrame(columns=["adm0_name", "adm1_name", "adm2_name", "date"])
for old_col, new_col in zip(
    ["confirmed", "death", "recovery"],
    ["cum_confirmed_cases", "cum_deaths", "cum_recoveries"],
):
    melted = (
        df_jan[old_col]
        .melt(
            id_vars=["adm0_name", "adm1_name", "adm2_name"],
            var_name="date",
            value_name=new_col,
        )
        .dropna()
    )
    df_jan_merged = pd.merge(
        df_jan_merged,
        melted,
        how="outer",
        on=["adm0_name", "adm1_name", "adm2_name", "date"],
    )
df_jan_merged = df_jan_merged.loc[df_jan_merged["adm2_name"] != "Unknown", :]

## Load and clean main data (scraped), harmonize city names

# data downloaded from
# https://github.com/BlankerL/DXY-COVID-19-Data
df = pd.read_csv(health_dxy_file)

# drop aggregates and cases in other countries
df = df.loc[df["countryEnglishName"] == "China", :]
df = df.loc[df["cityName"].notna(), :]

# df.describe(include='all')  # quick summary
# df['provinceName'].unique()  # looks clean
# df['provinceEnglishName'].unique()  # looks clean
# df['cityName'].unique()  # looks messy, will keep raw data

# # check unique English name for obs with the same Chinese cityName
# for cn_name, group in df.groupby(['provinceName', 'cityName']):
#     en_name = group['cityEnglishName'].unique()
#     if len(en_name) > 1:
#         print(cn_name)
#         print(en_name)
#         print(group['cityEnglishName'].shape)
#         print(group['cityEnglishName'].value_counts())

# # check all english city names
# for en_name, _ in df.groupby(['provinceEnglishName', 'cityEnglishName']):
#     print(en_name)

# # check all chinese city names
# for cn_name, _ in df.groupby(['provinceName', 'cityName']):
#     print(cn_name)

# set and sort index
df = df.set_index(["provinceName", "cityName"]).sort_index()
# record notes
df.loc[:, "notes"] = np.nan

# recode city English names based on Chinese names
cityEnglishName_dict = {
    # 'provinceName', 'cityName': 'cityEnglishName', 'assignedToCity'
    # for prisons
    ("浙江省", "省十里丰监狱"): ("Shilifeng Prison", "prison"),
    ("山东省", "任城监狱"): ("Rencheng Prison", "prison"),
    ("湖北省", "监狱系统"): ("Prison", "prison"),
    # for harmonizing names
    ("四川省", "凉山"): ("Liangshan Yi Autonomous Prefecture", np.nan),
    ("四川省", "凉山州"): ("Liangshan Yi Autonomous Prefecture", np.nan),
    # for imported cases
    (None, "境外输入人员"): ("International Imported Cases", "imported"),
    (None, "外地来沪人员"): ("Domestic Imported Cases", "imported"),
    (None, "武汉来京人员"): ("Domestic Imported Cases", "imported"),
    (None, "外地来京人员"): ("Domestic Imported Cases", "imported"),
    (None, "外地来津"): ("Domestic Imported Cases", "imported"),
    (None, "外地来津人员"): ("Domestic Imported Cases", "imported"),
    (None, "外地来穗人员"): ("Domestic Imported Cases", "imported"),
    (None, "外地来粤人员"): ("Domestic Imported Cases", "imported"),
    # for unknown
    (None, "待明确地区"): ("Unknown", "unknown"),
    (None, "未明确地区"): ("Unknown", "unknown"),
    (None, "未知"): ("Unknown", "unknown"),
    (None, "未知地区"): ("Unknown", "unknown"),
    (None, "不明地区"): ("Unknown", "unknown"),
    (None, "未明确地区"): ("Unknown", "unknown"),
    (None, "待明确"): ("Unknown", "unknown"),
}

# clean up cityEnglishName
for cn_name, values in cityEnglishName_dict.items():
    cn_name = tuple(slice(s) if s is None else s for s in cn_name)
    df.loc[cn_name, ["cityEnglishName", "notes"]] = values

# # check remaining missing values
# df.loc[df['cityEnglishName'].isna(), :].index.unique().tolist()

# add new admin level
df.loc[:, "adm3_name"] = "N/A"

# recode city English names based on Chinese names
cityEnglishName_dict = {
    ("上海市", "金山"): "Jinshan District",
    ("云南省", "红河"): "Honghe",
    ("云南省", "西双版纳州"): "Xishuangbanna",
    ("内蒙古自治区", "赤峰市松山区"): ("Chifeng", "Songshan"),
    ("内蒙古自治区", "赤峰市林西县"): ("Chifeng", "Linxi"),
    ("内蒙古自治区", "通辽市经济开发区"): "Tongliao",
    ("内蒙古自治区", "鄂尔多斯东胜区"): ("Ordos", "Dongsheng"),
    ("内蒙古自治区", "鄂尔多斯鄂托克前旗"): ("Ordos", "Etuokeqianqi"),
    ("内蒙古自治区", "锡林郭勒"): "Xilingol League",
    ("内蒙古自治区", "锡林郭勒盟"): "Xilingol League",
    ("内蒙古自治区", "锡林郭勒盟二连浩特"): ("Xilingol League", "Erlianhaote"),
    ("内蒙古自治区", "锡林郭勒盟锡林浩特"): ("Xilingol League", "Xilinhaote"),
    ("北京市", "石景山"): "Shijingshan District",
    ("北京市", "西城"): "Xicheng District",
    ("北京市", "通州"): "Tongzhou District",
    ("北京市", "门头沟"): "Mentougou District",
    ("北京市", "顺义"): "Shunyi District",
    (
        "新疆维吾尔自治区",
        "石河子",
    ): "Shihezi, Xinjiang Production and Construction Corps 8th Division",
    ("新疆维吾尔自治区", "第七师"): "Xinjiang Production and Construction Corps 7th Division",
    ("新疆维吾尔自治区", "第九师"): "Xinjiang Production and Construction Corps 9th Division",
    (
        "新疆维吾尔自治区",
        "第八师",
    ): "Shihezi, Xinjiang Production and Construction Corps 8th Division",
    (
        "新疆维吾尔自治区",
        "第八师石河子",
    ): "Shihezi, Xinjiang Production and Construction Corps 8th Division",
    (
        "新疆维吾尔自治区",
        "第八师石河子市",
    ): "Shihezi, Xinjiang Production and Construction Corps 8th Division",
    ("新疆维吾尔自治区", "第六师"): "Xinjiang Production and Construction Corps 6th Division",
    ("新疆维吾尔自治区", "胡杨河"): (
        "Xinjiang Production and Construction Corps 7th Division",
        "Huyanghe",
    ),
    ("新疆维吾尔自治区", "阿克苏"): "Akesu",
    ("河北省", "邯郸市"): "Handan",
    ("河南省", "邓州"): "Zhengzhou",
    ("河南省", "长垣"): "Changyuan",
    ("河南省", "长垣县"): "Changyuan",
    ("河南省", "鹤壁市"): "Hebi",
    ("海南省", "陵水县"): "Lingshui Li Autonomous County",
    ("甘肃省", "白银市"): "Baiyin",
    ("甘肃省", "金昌市"): "Jinchang",
    ("重庆市", "石柱"): "Shizhu Tujia Autonomous County",
    ("重庆市", "秀山"): "Xiushan Tujia and Miao Autonomous County",
    ("重庆市", "酉阳"): "Youyang Tujia and Miao Autonomous County",
    ("青海省", "西宁市"): "Xining",
    # this is not missing but a typo in the original dataset
    ("河南省", "邓州"): "Dengzhou",
    ("江苏省", "淮安"): "Huai'an",
}

# clean up cityEnglishName
for cn_name, values in cityEnglishName_dict.items():
    if isinstance(values, str):
        df.loc[cn_name, "cityEnglishName"] = values
    elif len(values) == 2:
        df.loc[cn_name, ["cityEnglishName", "adm3_name"]] = values

# rename variables
df.rename(
    {
        "provinceEnglishName": "adm1_name",
        "cityEnglishName": "adm2_name",
        "city_confirmedCount": "cum_confirmed_cases",
        "city_deadCount": "cum_deaths",
        "city_curedCount": "cum_recoveries",
    },
    axis=1,
    inplace=True,
)

# extract dates
df.loc[:, "updateTime"] = pd.to_datetime(df["updateTime"])
df.loc[:, "date"] = df["updateTime"].dt.date
df.loc[:, "date"] = pd.to_datetime(df["date"])

# choose the latest observation in each day
df = df.sort_values(by=["updateTime"])
df = df.drop_duplicates(
    subset=["adm1_name", "adm2_name", "adm3_name", "date"], keep="last"
)

# subset columns
df = df.loc[
    :,
    [
        "adm1_name",
        "adm2_name",
        "adm3_name",
        "date",
        "notes",
        "cum_confirmed_cases",
        "cum_deaths",
        "cum_recoveries",
    ],
]

# for big cities, adjust adm level
mask = df["adm1_name"].isin(["Shanghai", "Beijing", "Tianjin", "Chongqing"])
df.loc[mask, "adm3_name"] = df.loc[mask, "adm2_name"].tolist()
df.loc[mask, "adm2_name"] = df.loc[mask, "adm1_name"].tolist()

# drop cases unassigned to cities
df = df.loc[df["notes"] != "prison", :]
df = df.loc[
    ~df["adm2_name"].isin(
        ["International Imported Cases", "Domestic Imported Cases", "Unknown"]
    ),
    :,
]

# aggregate to city level
df = (
    df.groupby(["adm1_name", "adm2_name", "date"])
    .agg(
        cum_confirmed_cases=pd.NamedAgg(
            column="cum_confirmed_cases", aggfunc=np.nansum
        ),
        cum_deaths=pd.NamedAgg(column="cum_deaths", aggfunc=np.nansum),
        cum_recoveries=pd.NamedAgg(column="cum_recoveries", aggfunc=np.nansum),
    )
    .reset_index()
)

# fill adm0_name variable
df.loc[:, "adm0_name"] = "CHN"

## Merge with pre 01/24 data, create balanced panel

# merge with pre 1/24 data
df = pd.concat([df, df_jan_merged], sort=False)

# createa balanced panel
adm = df.loc[:, ["adm0_name", "adm1_name", "adm2_name"]].drop_duplicates()
days = pd.date_range(start="20200110", end=end_date)
adm_days = pd.concat([adm.assign(date=d) for d in days])
print(f"Sample: {len(adm)} cities; {len(days)} days.")
df = pd.merge(
    adm_days, df, how="left", on=["adm0_name", "adm1_name", "adm2_name", "date"]
)

# fill N/A for the first day
df.loc[df["date"] == pd.Timestamp("2020-01-10"), :] = df.loc[
    df["date"] == pd.Timestamp("2020-01-10"), :
].fillna(0)

# forward fill
df = df.set_index(["adm0_name", "adm1_name", "adm2_name"]).sort_index()
for _, row in adm.iterrows():
    df.loc[tuple(row), :] = df.loc[tuple(row), :].fillna(method="ffill")

## Load and clean policy data

# load dataset of the policies in China
df_policy = pd.read_csv(policy_file).dropna(how="all")
# subset columns
df_policy = df_policy.loc[
    :, ["adm0_name", "adm1_name", "adm2_name", "date_start", "date_end", "policy"]
]
# save set of policies
policy_set = df_policy["policy"].unique().tolist()

# parse
df_policy.loc[:, "date_start"] = pd.to_datetime(df_policy["date_start"])
df_policy.loc[:, "date_end"] = pd.to_datetime(df_policy["date_end"])

# check city name agreement
policy_city_set = set(
    df_policy.loc[:, ["adm0_name", "adm1_name", "adm2_name"]]
    .drop_duplicates()
    .apply(tuple, axis=1)
    .tolist()
)
adm2_set = set(adm.drop_duplicates().apply(tuple, axis=1).tolist())
adm1_set = set(
    adm.loc[:, ["adm0_name", "adm1_name"]]
    .drop_duplicates()
    .apply(lambda x: (*x, "All"), axis=1)
    .tolist()
)
print("Mismatched: ", policy_city_set - (adm1_set | adm2_set))

# subset adm1 policies
adm1_policy = df_policy.loc[df_policy["adm2_name"] == "All", :]
# merge to create balanced panel
adm1_policy = pd.merge(
    adm,
    adm1_policy.drop(["adm2_name"], axis=1),
    how="left",
    on=["adm0_name", "adm1_name"],
).dropna(subset=["policy"])
print("no. of adm1 policies: ", adm1_policy.shape[0])

# subset adm2 policies
adm2_policy = df_policy.loc[df_policy["adm2_name"] != "All", :]
print("no. of adm2 policies: ", adm2_policy.shape[0])

# concat policies at different levels
df_policy = pd.concat([adm1_policy, adm2_policy])

# sort by date to discard duplicates
df_policy = df_policy.sort_values(by=["date_start"])

# drop duplicates
df_policy = df_policy.drop_duplicates(
    subset=["adm1_name", "adm2_name", "policy"], keep="first"
)

df_policy_set = set(
    df_policy.loc[:, ["adm0_name", "adm1_name", "adm2_name"]]
    .drop_duplicates()
    .apply(tuple, axis=1)
    .tolist()
)
print("Cities without any policies: ", len(adm2_set - df_policy_set))
print(adm2_set - df_policy_set)

# unstack to flip policy type to columns
df_policy = df_policy.set_index(
    ["adm0_name", "adm1_name", "adm2_name", "policy"]
).unstack("policy")

# prepare to merge with multi index
adm_days.set_index(["adm0_name", "adm1_name", "adm2_name"], inplace=True)
adm_days.columns = pd.MultiIndex.from_tuples([("date", "")])

# merge to create balanced panel
df_policy = pd.merge(
    adm_days, df_policy, how="left", on=["adm0_name", "adm1_name", "adm2_name"]
)

# fill N/As for dates
df_policy = df_policy.fillna(pd.Timestamp("2021-01-01"))

# convert to dummies
for policy in policy_set:
    df_policy.loc[:, (policy, "")] = (
        df_policy.loc[:, ("date", "")] >= df_policy.loc[:, ("date_start", policy)]
    ) & (df_policy.loc[:, ("date", "")] <= df_policy.loc[:, ("date_end", policy)])
# discard intermediate variables
df_policy = df_policy[["date"] + policy_set]
# flatten the column index
df_policy.columns = df_policy.columns.get_level_values(0)
# convert data type
df_policy.loc[:, policy_set] = df_policy.loc[:, policy_set].astype(int)

df = pd.merge(
    df, df_policy, how="inner", on=["adm0_name", "adm1_name", "adm2_name", "date"]
)

## Merge with testing policies

# merge with testing policies
# source:
# https://english.kyodonews.net/news/2020/02/6982cc1e130f-china-records-2-straight-days-of-fewer-than-1000-new-covid-19-cases.html
# https://www.worldometers.info/coronavirus/how-to-interpret-feb-12-case-surge/
# https://www.medrxiv.org/content/10.1101/2020.03.23.20041319v1.full.pdf
df.loc[:, "testing_regime"] = (
    (df["date"] > pd.Timestamp("2020-01-17")).astype(int)
    + (df["date"] > pd.Timestamp("2020-01-27")).astype(int)
    + (df["date"] > pd.Timestamp("2020-02-05")).astype(int)
    + (df["date"] > pd.Timestamp("2020-02-12")).astype(int)
    + (df["date"] > pd.Timestamp("2020-02-19")).astype(int)
    + (df["date"] > pd.Timestamp("2020-03-04")).astype(int)
)

# df.describe(include='all')  # looks fine

## Multiple sanity checks, Save

# drop/impute non monotonic observations
for col in ["cum_confirmed_cases", "cum_deaths", "cum_recoveries"]:
    for _, row in adm.iterrows():
        df.loc[tuple(row), col] = convert_non_monotonic_to_nan(
            df.loc[tuple(row), col].values
        )
        df.loc[tuple(row), col + "_imputed"] = log_interpolate(
            df.loc[tuple(row), col].values
        )

# add city id
df = pd.merge(
    df,
    adm.assign(adm2_id=range(adm.shape[0])),
    how="left",
    on=["adm0_name", "adm1_name", "adm2_name"],
)

## merge on populations

chnpop = pd.read_csv(pop_file, usecols=[1, 2, 3, 4], index_col=[0, 1, 2])

# adjust b/c in units of 10,000's
chnpop = chnpop * 10000
chnpop.columns = ["population"]

old_n = df.shape[0]
df = df.set_index(["adm0_name", "adm1_name", "adm2_name", "date"]).join(
    chnpop, how="left"
)
assert df.shape[0] == old_n

# add estimate for 'other' cities
TOTAL_CHN_POP = 1.34e9
other_pop = TOTAL_CHN_POP - chnpop["population"].sum()
n_other = df[df.population.isnull()].groupby(level=[0, 1, 2]).max().shape[0]
pop_per_city = int(other_pop / n_other)
df["pop_is_imputed"] = 0
df.loc[df.population.isnull(), "pop_is_imputed"] = 1
df.loc[df.pop_is_imputed == 1, "population"] = pop_per_city
# type conversion
df = df.astype(
    {
        "population": "int64",
        "cum_confirmed_cases_imputed": "int64",
        "cum_deaths_imputed": "int64",
        "cum_recoveries_imputed": "int64",
    }
)
# add active cases
df.loc[:, "active_cases"] = (
    df.loc[:, "cum_confirmed_cases"].values
    - df.loc[:, "cum_deaths"].values
    - df.loc[:, "cum_recoveries"].values
)
df.loc[:, "active_cases_imputed"] = (
    df.loc[:, "cum_confirmed_cases_imputed"].values
    - df.loc[:, "cum_deaths_imputed"].values
    - df.loc[:, "cum_recoveries_imputed"].values
)

# merge with lon lat
df_shp = gpd.read_file(shp_file)
df_match = pd.read_csv(match_file)

df_shp = df_shp.loc[df_shp["adm0_name"] == "CHN", :]

df_shp = pd.merge(
    df_shp,
    df_match,
    left_on=["adm1_name", "adm2_name"],
    right_on=["shp_adm1", "shp_adm2"],
    how="left",
)

df_shp.loc[:, "adm1_name"] = df_shp.apply(
    lambda x: x["epi_adm1"] if pd.notnull(x["epi_adm1"]) else x["adm1_name"], axis=1
)

df_shp.loc[:, "adm2_name"] = df_shp.apply(
    lambda x: x["epi_adm2"] if pd.notnull(x["epi_adm2"]) else x["adm2_name"], axis=1
)

df_shp = df_shp.loc[:, ["adm1_name", "adm2_name", "latitude", "longitude"]]

df_shp.columns = ["adm1_name", "adm2_name", "lat", "lon"]

df = pd.merge(df.reset_index(), df_shp, how="left", on=["adm1_name", "adm2_name"])

output_file.parent.mkdir(parents=True, exist_ok=True)
df.to_csv(output_file, index=False)

print("Data Description: ", df.describe(include="all").T)
print("Data Types: ", df.dtypes)
print("Variables: ", df.columns)
