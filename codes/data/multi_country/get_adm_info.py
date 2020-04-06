#!/usr/bin/env python
# coding: utf-8

from pathlib import Path
import pandas as pd
import geopandas as gpd
from census import Census
import requests
import numpy as np
from bs4 import BeautifulSoup
from fuzzywuzzy import fuzz
from fuzzywuzzy import process
from codes import utils as cutil

idx = pd.IndexSlice

if cutil.API_KEYS["census"] == "YOUR_API_KEY":
    raise ValueError(
        """To run this script, you will need a U.S. Census API key, which can be obtained"""
        """here: https://api.census.gov/data/key_signup.html. You will need to save this """
        """key to `api_keys.json` in the root directory of this repo with the following format:"""
        """
        
        {
            "census": "API_KEY_STRING"
        }
        """
    )
datestamp = "20200320"

adm1_shp_path = (
    cutil.DATA_RAW
    / "multi_country"
    / f"ne_10m_admin_1_states_provinces_{datestamp}.zip"
)
adm_url_fmt = (
    "https://biogeo.ucdavis.edu/data/gadm3.6/{ftype}/gadm36_{iso3}_{ftype}.zip"
)


def process_gadm(in_gdf):
    cols_to_load = ["GID_0", "NAME_1", "NAME_2", "geometry"]
    col_map = {"GID_0": "adm0_name", "NAME_1": "adm1_name", "NAME_2": "adm2_name"}
    if "NAME_3" in in_gdf.columns:
        cols_to_load.append("NAME_3")
        col_map["NAME_3"] = "adm3_name"

    in_gdf = in_gdf[cols_to_load]
    in_gdf = in_gdf.rename(columns=col_map)

    cent = in_gdf["geometry"].centroid
    in_gdf["latitude"] = cent.y
    in_gdf["longitude"] = cent.x

    in_gdf = in_gdf.set_index(["adm0_name", "adm1_name", "adm2_name"])
    if "adm3_name" in in_gdf.columns:
        in_gdf = in_gdf.set_index("adm3_name", append=True)

    return in_gdf

def main():
    # ## Global adm1

    # get file
    print("Downloading and processing global adm1 data...")
    adm1_url = "https://www.naturalearthdata.com/http//www.naturalearthdata.com/download/10m/cultural/ne_10m_admin_1_states_provinces.zip"
    cutil.download_zip(adm1_url, adm1_shp_path, overwrite=False)

    # process
    in_gdf = gpd.read_file(cutil.zipify_path(adm1_shp_path))
    adm_gdf = in_gdf[
        [
            "adm0_a3",
            "name",
            "geometry",
            "latitude",
            "longitude",
            "gadm_level",
            "name_alt",
        ]
    ]
    adm_gdf = adm_gdf.rename(
        columns={"adm0_a3": "adm0_name", "name": "adm1_name"}
    ).set_index(["adm0_name", "adm1_name", "gadm_level"])

    # for now, when there are duplicates, just drop the second one without any better information
    # could not find a data dictionary for the shapefile
    adm_gdf = adm_gdf[~adm_gdf.index.duplicated(keep="first")].reset_index(
        drop=False, level="gadm_level"
    )

    # we know france and italy are actually admin 2
    adm_gdf.loc[idx[["FRA", "ITA"], :], "gadm_level"] = 2

    # separate into levels
    adm1_gdf = adm_gdf[adm_gdf.gadm_level == 1].drop(columns="gadm_level")
    adm2_gdf = adm_gdf[adm_gdf.gadm_level == 2].drop(columns="gadm_level")
    adm2_gdf.index = adm2_gdf.index.set_names("adm2_name", level="adm1_name")

    # Set up an adm3 dataset that is currently empty
    adm3_gdf = gpd.GeoDataFrame(
        columns=adm2_gdf.reset_index(drop=False).columns, crs=adm_gdf.crs
    )
    adm3_gdf["adm3_name"] = []
    adm3_gdf["adm1_name"] = []
    adm3_gdf = adm3_gdf.set_index(["adm0_name", "adm1_name", "adm2_name", "adm3_name"])

    # ## adm2+

    # ### FRA
    print("Downloading and processing FRA population data...")
    # First, download population data and make adm2 to adm1 mapping

    xwalk_fra_url = (
        "https://www.insee.fr/fr/statistiques/fichier/3720946/departement2019-csv.zip"
    )
    xwalk_fra = pd.read_csv(
        xwalk_fra_url,
        usecols=[0, 1],
        index_col=0,
        names=["num", "region_id"],
        header=None,
        skiprows=1,
    )

    pop_fra_url = "https://www.insee.fr/fr/statistiques/fichier/2012713/TCRD_004.xls"
    pop_fra = pd.read_excel(
        pop_fra_url,
        sheet_name="DEP",
        skiprows=3,
        index_col=[0, 1],
        usecols=[0, 1, 2],
        skipfooter=2,
    )
    pop_fra.index.names = ["num", "nom"]
    pop_fra.columns = ["population"]
    pop_fra = pop_fra.drop(index="M", level="num")

    region_xwalk = pd.read_excel(
        pop_fra_url,
        sheet_name="REG",
        skiprows=3,
        index_col=[0],
        usecols=[0, 1],
        skipfooter=2,
    ).iloc[:, 0]
    region_xwalk.name = "region"
    region_xwalk.index.name = "region_id"
    region_xwalk = region_xwalk.drop(index="M")
    region_xwalk.index = region_xwalk.index.astype(int)

    pop_fra = (
        pop_fra.join(xwalk_fra, how="outer")
        .join(region_xwalk, on="region_id", how="outer")
        .sort_index()
    )

    out_dir = cutil.DATA_INTERIM / "france"
    out_dir.mkdir(parents=True, exist_ok=True)

    # save b/c will be used by other France code
    pop_fra.to_csv(cutil.DATA_INTERIM / "france" / "adm2_to_adm1.csv")

    # Next merge this into adm info

    adm2_fr = (
        pop_fra.reset_index(drop=False)
        .drop(columns=["region_id", "num"])
        .rename(columns={"region": "adm1_name", "nom": "adm2_name"})
        .set_index(["adm1_name", "adm2_name"])
    )

    # manually correct some differences in naming btwn 2 datasets
    name_map = {
        "Guyane française": "Guyane",
        "Haute-Rhin": "Haut-Rhin",
        "Seien-et-Marne": "Seine-et-Marne",
    }
    adm2_gdf = adm2_gdf.rename(index=name_map, level="adm2_name")

    # merge back in
    adm2_gdf = (
        adm2_gdf.join(
            adm2_fr.reset_index("adm1_name", drop=False), on="adm2_name", how="outer"
        )
        .reset_index(drop=False)
        .set_index(["adm0_name", "adm1_name", "adm2_name"])
    )

    # collapse to adm1 level and add that onto list
    adm1_fr = adm2_gdf.loc[["FRA"], ["geometry", "population"]].dissolve(
        by=["adm0_name", "adm1_name"], aggfunc="sum"
    )
    adm1_fr["latitude"] = adm1_fr.geometry.centroid.y
    adm1_fr["longitude"] = adm1_fr.geometry.centroid.x
    adm1_gdf = adm1_gdf.append(adm1_fr)

    # ### Others

    # All of these are from the same source but:
    # - some work with the gpkg file others with the shapefile
    # - some are adm3 some are adm2

    isos = ["ITA", "USA", "CHN", "KOR", "IRN"]
    adm2_name_maps = {
        "ITA": {
            "Firenze": "Florence",
            "Reggio Emilia": "Reggio Nell'Emilia",
            "Reggio Calabria": "Reggio Di Calabria",
            "Pesaro e Urbino": "Pesaro E Urbino",
            "Barletta-Andria Trani": "Barletta-Andria-Trani",
            "Crotene": "Crotone",
            "Aoste": "Aosta",
            "Bozen": "Bolzano",
            "Turin": "Torino",
            "Padova": "Padua",
            "Forlì-Cesena": "Forli' - Cesena",
            "Siracusa": "Syracuse",
            "Oristrano": "Oristano",
            "Mantova": "Mantua",
            "Monza e Brianza": "Monza and Brianza",
            "Massa-Carrara": "Massa Carrara",
        }
    }
    for iso3 in isos:
        print(f"Downloading and processing {iso3} geographical and population data...")
        # download if needed
        if iso3 == "CHN":
            ftype = "shp"
        else:
            ftype = "gpkg"
        zip_path = cutil.get_adm_zip_path(iso3, datestamp)
        if not zip_path.exists():
            cutil.download_zip(adm_url_fmt.format(iso3=iso3, ftype=ftype), zip_path)
        if ftype == "gpkg":
            to_open = zip_path / f"gadm36_{iso3}.gpkg"
        else:
            to_open = zip_path / f"gadm36_{iso3}_3.shp"

        # load gdf
        in_gdf = process_gadm(gpd.read_file(cutil.zipify_path(to_open)))

        if "adm3_name" in in_gdf.index.names:
            adm3_gdf = adm3_gdf.append(in_gdf)

            # now aggregate to level 2 to insert into that level
            in_gdf = in_gdf.dissolve(by=["adm0_name", "adm1_name", "adm2_name"])
            in_gdf["latitude"] = in_gdf.geometry.centroid.y
            in_gdf["longitude"] = in_gdf.geometry.centroid.x

        # insert into level 2 dataset
        if iso3 in adm2_gdf.index.get_level_values("adm0_name").unique():
            adm2_gdf = adm2_gdf.rename(index=adm2_name_maps[iso3], level="adm2_name")
            res = pd.merge(
                adm2_gdf.loc[idx[iso3, :, :]],
                in_gdf.reset_index(drop=False),
                on="adm2_name",
                how="outer",
                indicator=True,
            ).set_index(["adm0_name", "adm1_name", "adm2_name"])
            assert (res._merge == "both").all()
            del res["_merge"]
            for i in ["geometry", "latitude", "longitude"]:
                res[i] = res[i + "_y"].fillna(res[i + "_x"])
                res = res.drop(columns=[i + "_x", i + "_y"])
            adm2_gdf = adm2_gdf.loc[
                adm2_gdf.index.get_level_values("adm0_name") != iso3
            ].append(res)
        else:
            adm2_gdf = adm2_gdf.append(in_gdf)

        # now aggregate to level 1 to replace that level with better/more consistent data
        in_gdf = in_gdf.dissolve(by=["adm0_name", "adm1_name"])
        in_gdf["latitude"] = in_gdf.geometry.centroid.y
        in_gdf["longitude"] = in_gdf.geometry.centroid.x
        adm1_gdf = adm1_gdf[adm1_gdf.index.get_level_values("adm0_name") != iso3]
        adm1_gdf = adm1_gdf.append(in_gdf)

    # ## Manual name adjustments

    # Some manual adjustments to make this match with the naming of the data produced by country teams

    # ### ITA

    ## get new regions/provinces
    region_dict = {
        "Emilia-Romagna": "Emilia Romagna",
        "Friuli-Venezia Giulia": "Friuli Venezia Giulia",
        "Apulia": "Puglia",
        "Sicily": "Sicilia",
    }
    add_regions = ["P.A. Bolzano", "P.A. Trento"]
    drop_regions = ["Trentino-Alto Adige"]
    province_dict = {
        "Forli' - Cesena": "Forlì-Cesena",
        "Reggio Nell'Emilia": "Reggio nell'Emilia",
        "Padua": "Padova",
        "Reggio Di Calabria": "Reggio di Calabria",
        "Pesaro E Urbino": "Pesaro e Urbino",
        "Syracuse": "Siracusa",
        "Florence": "Firenze",
        "Mantua": "Mantova",
        "Monza and Brianza": "Monza e della Brianza",
    }
    add_provinces = ["Sud Sardegna"]
    add_provinces_reg = ["Sardegna"]
    n_reg = len(add_regions)
    new_reg = pd.DataFrame(
        dict(adm0_name=["ITA"] * n_reg, adm1_name=add_regions)
    ).set_index(["adm0_name", "adm1_name"])
    n_prov = len(add_provinces)
    new_prov = pd.DataFrame(
        dict(
            adm0_name=["ITA"] * n_prov,
            adm2_name=add_provinces,
            adm1_name=add_provinces_reg,
        )
    ).set_index(["adm0_name", "adm1_name", "adm2_name"])

    ## update regions for 2 provinces that are treated as
    ## autonomous regions in the italy repo used for ITA_processed
    tmp = adm2_gdf.reset_index(level="adm1_name", drop=False)
    for i in ["Bolzano", "Trento"]:
        tmp.loc[idx["ITA", i], "adm1_name"] = f"P.A. {i}"
    adm2_gdf = tmp.reset_index(drop=False).set_index(
        ["adm0_name", "adm1_name", "adm2_name"]
    )

    ## fix names
    adm1_gdf = adm1_gdf.rename(index=region_dict, level="adm1_name")
    adm2_gdf = adm2_gdf.rename(index=region_dict, level="adm1_name")
    adm3_gdf = adm3_gdf.rename(index=region_dict, level="adm1_name")
    adm2_gdf = adm2_gdf.rename(index=province_dict, level="adm2_name")
    adm3_gdf = adm3_gdf.rename(index=province_dict, level="adm2_name")

    ## split Trentino- into two provinces
    adm1_gdf = adm1_gdf.append(new_reg)
    adm1_gdf = adm1_gdf.drop(index=drop_regions, level="adm1_name")

    ## add additional province of sardegna
    adm2_gdf = adm2_gdf.append(new_prov)

    # ## Pop

    # ### US
    print("Downloading USA population data from US Census...")
    c = Census(cutil.API_KEYS["census"])
    pop_city = pd.DataFrame(
        c.acs5.state_place(("NAME", "B01003_001E"), Census.ALL, Census.ALL)
    )
    pop_cty = pd.DataFrame(
        c.acs5.state_county(("NAME", "B01003_001E"), Census.ALL, Census.ALL)
    )

    # #### Place-level

    # save the place-level populations
    pop_city[["adm3_name", "adm_1_name"]] = pd.DataFrame(
        pop_city.NAME.str.split(", ").values.tolist(), index=pop_city.index
    )
    pop_city = pop_city.rename(columns={"B01003_001E": "pop"}).drop(columns="NAME")
    pop_city = pop_city.set_index(["adm3_name", "adm_1_name"])

    out_dir = cutil.DATA / "interim" / "usa"
    out_dir.mkdir(parents=True, exist_ok=True)
    pop_city.to_csv(out_dir / "adm3_pop.csv", index=True)

    # #### County-level

    ## get county-level populations
    hasc_fips_url = "http://www.statoids.com/yus.html"
    data = requests.get(hasc_fips_url).text
    text = BeautifulSoup(data, "lxml").pre.text
    row_list = text.split("\r\n")[1:-1]
    headers = row_list[0].split()
    valid_rows = [r for r in row_list if r != "" and r[:4] not in ["Name", "----"]]
    name = [r[:23].rstrip() for r in valid_rows]
    t = [r[23] for r in valid_rows]
    hasc = [r[25:33] for r in valid_rows]
    fips = [r[34:39] for r in valid_rows]
    pop = [int(r[40:49].lstrip().replace(",", "")) for r in valid_rows]
    area_km2 = [int(r[50:57].lstrip().replace(",", "")) for r in valid_rows]
    area_mi2 = [int(r[58:65].lstrip().replace(",", "")) for r in valid_rows]
    z = [r[66] for r in valid_rows]
    capital = [r[68:] for r in valid_rows]

    # turn into dataframe
    us_county_df = pd.DataFrame(
        {
            "name": name,
            "type": t,
            "hasc": hasc,
            "fips": fips,
            "population": pop,
            "area_km2": area_km2,
            "capital": capital,
        }
    ).set_index("hasc")

    # ##### Merge in us adm2 dataset

    us_gdf = in_gdf = gpd.read_file(
        cutil.zipify_path(cutil.get_adm_zip_path("USA", datestamp) / "gadm36_USA.gpkg")
    )
    us_gdf = us_gdf[us_gdf.HASC_2.notnull()]

    us_pops = us_gdf.join(us_county_df, on="HASC_2", how="outer")
    us_pops = us_pops[["NAME_1", "NAME_2", "fips", "population", "area_km2", "capital"]]
    us_pops = us_pops.rename(columns={"NAME_1": "adm1_name", "NAME_2": "adm2_name"})
    us_pops["adm0_name"] = "USA"

    # Manual addition of names that are in the statoids dataset but not the gadm shapes
    manual_names = {
        "24005": ("Maryland", "Baltimore County"),
        "02130": ("Alaska", "Ketchikan Gateway Borough"),
        "29510": ("Missouri", "City of St. Louis"),
        "51019": ("Virginia", "Bedford County"),
        "51059": ("Virginia", "Fairfax County"),
        "51161": ("Virginia", "Roanoke County"),
        "51620": ("Virginia", "Franklin City"),
        "02105": ("Alaska", "Hoonah-Angoon Census Area"),
        "02195": ("Alaska", "Petersburg Borough"),
        "02198": ("Alaska", "Prince of Wales-Hyder Census Area"),
        "51159": ("Virginia", "Richmond County"),
        "02230": ("Alaska", "Skagway Municipality"),
        "02275": ("Alaska", "Wrangell City and Borough"),
        "02282": ("Alaska", "Yakutat City and Borough")
    }

    for k,v in manual_names.items():
        us_pops.loc[us_pops.fips==k,['adm1_name','adm2_name']] = v
    us_pops = us_pops.set_index(["adm0_name", "adm1_name", "adm2_name"])

    # save fips xwalk
    us_pops.reset_index(level="adm0_name", drop=True).to_csv(
        cutil.DATA_INTERIM / "usa" / "adm2_pop_fips.csv", index=True
    )


    # ##### Merge back into global adm datasets
    ## adm2
    adm2_gdf = adm2_gdf.join(us_pops.population, rsuffix='_r', how="outer")
    adm2_gdf['population'] = adm2_gdf.population.fillna(adm2_gdf.population_r)
    adm2_gdf = adm2_gdf.drop(columns='population_r')

    ## adm1
    pop_st = pd.DataFrame(
        c.acs5.state(("NAME", "B01003_001E"), Census.ALL)
    )
    pop_st = pop_st.rename(columns={"NAME": "adm1_name", "B01003_001E":"population_census"}).drop(columns="state")
    pop_st["adm0_name"] = "USA"
    pop_st = pop_st.set_index(["adm0_name", "adm1_name"], drop=True)

    # add territories
    terr_url = "https://worldpopulationreview.com/countries/united-states-territories/"
    data = requests.get(terr_url).text
    text = BeautifulSoup(data, "lxml")
    table = text.table

    elements = [i.find_all("td") for i in table.tbody.find_all("tr")]
    country, pop = [], []
    for e in elements:
        country.append(e[0].text)
        pop.append(int(e[1].text.replace(",","")))
    pop_terr = pd.DataFrame({"adm1_name": country, "population_terr": pop, "adm0_name": "USA"}).set_index(["adm0_name", "adm1_name"])

    # included US Virgin Islands in territories
    terr_url = "https://worldpopulationreview.com/countries/united-states-virgin-islands-population/"
    data = requests.get(terr_url).text
    text = BeautifulSoup(data, "lxml")
    pop_usvg = pd.Series(
        [int(text.find(attrs={"class": "popNumber"}).text.replace(",", ""))],
        index=pd.MultiIndex.from_tuples(
            (("USA", "US Virgin Islands"),), names=["adm0_name", "adm1_name"]
        ),
        name="population_terr",
    )
    pop_terr = pop_terr.append(pd.DataFrame(pop_usvg))

    pop_st = pop_st.join(pop_terr, how="outer")
    # taking population terr b/c more recent than ACS for puerto rico
    pop_st.population_terr = pop_st.population_terr.fillna(pop_st.population_census)
    pop_st = pop_st.drop(columns="population_census")

    # merge back into global adm1 dataset
    adm1_gdf = adm1_gdf.join(pop_st, how="outer")
    adm1_gdf.loc[idx["USA",:],"population"] = adm1_gdf.loc[idx["USA",:], "population_terr"]
    adm1_gdf = adm1_gdf.drop(columns="population_terr")

    # ### ITA

    print("Downloading and processing ITA population data...")
    url_fmt = "http://demo.istat.it/pop2019/dati/{lvl}.zip"
    ita_pop_dir = cutil.DATA_RAW / "italy" / "population"
    for u in ["province", "regioni", "comuni"]:
        if not (ita_pop_dir / f"{u}.csv").exists():
            cutil.download_zip(
                url_fmt.format(lvl=u), ita_pop_dir / (u + ".zip"), overwrite=False
            )

    replace_provinces = {
        "Bolzano/Bozen": "Bolzano",
        "Massa-Carrara": "Massa Carrara",
        "Valle d'Aosta/Vallée d'Aoste": "Aosta",
    }
    replace_regions = {
        "Emilia-Romagna": "Emilia Romagna",
        "Friuli-Venezia Giulia": "Friuli Venezia Giulia",
        "Valle d'Aosta/Vallée d'Aoste": "Valle d'Aosta",
        "Bolzano": "P.A. Bolzano",
        "Trento": "P.A. Trento",
    }
    replace_munis = {"Vo'": "Vò"}

    # #### adm1 and 2

    df = pd.read_csv(
        ita_pop_dir / "province.zip",
        skiprows=1,
        usecols=["Provincia", "Totale Maschi", "Totale Femmine", "Età"],
    )
    df["adm0_name"] = "ITA"
    df = df.rename(columns={"Provincia": "adm2_name"}).set_index(
        ["adm0_name", "adm2_name"]
    )
    pop2 = df.loc[df["Età"] == "Totale", ["Totale Maschi", "Totale Femmine"]].sum(
        axis=1
    )
    pop2 = pop2.rename(index=replace_provinces)
    pop2.name = "population"

    provinces_as_regions = pop2.loc[idx[:, ["Bolzano", "Trento"]]]
    provinces_as_regions.index = provinces_as_regions.index.set_names(
        "adm1_name", level="adm2_name"
    )
    provinces_as_regions = provinces_as_regions.rename(
        index=replace_regions, level="adm1_name"
    )
    adm2_gdf.population = (
        adm2_gdf.reset_index(level="adm1_name").population.fillna(pop2).values
    )

    df = pd.read_csv(
        ita_pop_dir / "regioni.zip",
        skiprows=1,
        usecols=["Regione", "Totale Maschi", "Totale Femmine", "Età"],
    )
    df["adm0_name"] = "ITA"
    df = df.rename(columns={"Regione": "adm1_name"}).set_index(
        ["adm0_name", "adm1_name"]
    )
    pop1 = df.loc[df["Età"] == "Totale", ["Totale Maschi", "Totale Femmine"]].sum(
        axis=1
    )
    pop1 = pop1.rename(index=replace_regions)
    pop1.name = "population"

    pop1 = pop1.append(provinces_as_regions)
    adm1_gdf.population = adm1_gdf.population.fillna(pop1)

    # #### adm3

    df = pd.read_csv(
        ita_pop_dir / "comuni.zip",
        skiprows=1,
        usecols=["Denominazione", "Totale Maschi", "Totale Femmine", "Età"],
    )
    df["adm0_name"] = "ITA"
    df = df.rename(columns={"Denominazione": "adm3_name"}).set_index(
        ["adm0_name", "adm3_name"]
    )
    pop3 = df.loc[df["Età"] == 999, ["Totale Maschi", "Totale Femmine"]].sum(axis=1)
    pop3.name = "population"
    pop3 = pop3.rename(index=replace_munis)

    ## making sure we match the important cities (ones that are used in pop weighting)
    adm3_gdf = adm3_gdf.rename(
        lambda x: x.replace("d' Adda", "d'Adda").replace(
            "Terranova Dei Passerini", "Terranova dei Passerini"
        ),
        level="adm3_name",
    )

    # these two municipalities merged
    castel = gpd.GeoDataFrame(
        adm3_gdf.loc[idx[:, :, :, ["Cavacurta", "Camairago"]], ["geometry"]]
    ).dissolve(by=["adm0_name", "adm1_name", "adm2_name"])
    castel["adm3_name"] = ["Castelgerundo"]
    castel["latitude"] = castel.geometry.centroid.y
    castel["longitude"] = castel.geometry.centroid.x
    castel = castel.set_index("adm3_name", append=True)
    adm3_gdf = adm3_gdf[
        ~adm3_gdf.index.get_level_values("adm3_name").isin(["Cavacurta", "Camairago"])
    ].append(castel)

    ## don't know what to do with same-named cities so we'll just keep those pops as missing
    pop3 = pop3[~pop3.index.duplicated(keep=False)]

    ## merge
    adm3_gdf = (
        adm3_gdf.reset_index(level=["adm1_name", "adm2_name"], drop=False)
        .join(pop3, how="left")
        .reset_index(drop=False)
        .set_index(["adm0_name", "adm1_name", "adm2_name", "adm3_name"])
    )

    # ### IRN

    print("Downloading and processing IRN population data...")
    irn_url = r"https://www.citypopulation.de/en/iran/admin/"
    r = requests.get(irn_url)
    data = r.text
    soup = BeautifulSoup(data, "lxml")
    table = soup.table

    adm1s = table.find_all("tbody", {"class": "admin1"})
    adm2s = table.find_all("tbody", {"class": "admin2"})

    # just want name and latest census pop
    adm1_rows = []
    for a in adm1s:
        rows = a.find_all("tr")
        for r in rows:
            td = r.find_all("td")
            row = [i.text for i in td]
            adm1_rows.append([row[0], int(row[-2].replace(",", ""))])
    adm1_irn = pd.DataFrame(adm1_rows, columns=["adm1_name", "population"]).set_index(
        "adm1_name"
    )

    adm2_rows = []
    for a in adm2s:
        # complicated way to get province from previous admin1 level
        prov = "".join(list(a.previous_sibling.previous_sibling.strings)[1:-6])
        rows = a.find_all("tr")
        for r in rows:
            td = r.find_all("td")
            row = [i.text for i in td]
            adm2_rows.append([prov, row[0], int(row[-2].replace(",", ""))])
    adm2_irn = pd.DataFrame(
        adm2_rows, columns=["adm1_name", "adm2_name", "population"]
    ).set_index(["adm1_name", "adm2_name"])

    def checker(wrong_options, correct_options):
        """Fuzzy matching for names"""
        names_array = []
        ratio_array = []
        for wrong_option in wrong_options:
            if wrong_option in correct_options:
                names_array.append(wrong_option)
                ratio_array.append("100")
            else:
                x = process.extractOne(
                    wrong_option, correct_options, scorer=fuzz.token_set_ratio
                )
                names_array.append(x[0])
                ratio_array.append(x[1])
        return names_array, ratio_array

    # #### adm1

    adm1_orig = adm1_irn.index.values
    cleaned_names = checker(
        adm1_orig, adm1_gdf.loc[idx["IRN"]].index.get_level_values("adm1_name")
    )[0]

    # I know that the 3rd one is mapping to East rather than West :(
    cleaned_names[2] = "West Azarbaijan"

    adm1_irn["adm1_name"] = cleaned_names
    adm1_irn["adm0_name"] = "IRN"
    adm1_irn = adm1_irn.set_index(["adm0_name", "adm1_name"], drop=True)

    # merge in pops
    adm1_gdf.population = adm1_gdf.population.fillna(adm1_irn.population)

    # #### adm2

    # There's going to be some challenges in fuzzy merging adm2 level populations, but we're not running analyses on adm2 yet, so I'm holding off on this part.

    # ## Area

    print("Formatting and saving administrative unit info datasets...")

    def finishing_touches(df):
        # area
        area_km2_mercator = (
            df[df.geometry.notna()].to_crs("EPSG:3395").geometry.area / 1e6
        )
        if "area_km2" in df.columns:
            df["area_km2"] = df.area_km2.fillna(area_km2_mercator)
        else:
            df["area_km2"] = area_km2_mercator

        # pop density
        if "pop_density_km2" in df.columns:
            df.pop_density_km2 = df.pop_density_km2.fillna(
                df.population.astype(float) / df.area_km2
            )
        else:
            df["pop_density_km2"] = df.population.astype(float) / df.area_km2

        # lat/lon
        df.longitude = df.longitude.fillna(df.geometry.centroid.x)
        df.latitude = df.latitude.fillna(df.geometry.centroid.y)

        df = df.sort_index()
        return df

    adm1_gdf = finishing_touches(adm1_gdf)
    adm2_gdf = finishing_touches(adm2_gdf)
    adm3_gdf = finishing_touches(adm3_gdf)

    # ## Save

    for ix, i in enumerate([adm1_gdf, adm2_gdf, adm3_gdf]):
        fname = f"adm{ix+1}"
        out_dir = cutil.DATA_INTERIM / "adm" / fname
        out_dir.mkdir(parents=True, exist_ok=True)
        i.to_file(out_dir / f"{fname}.shp", index=True)
        i.drop(columns="geometry").to_csv(out_dir / f"{fname}.csv", index=True, float_format="%.3f")


if __name__ == "__main__":
    main()
