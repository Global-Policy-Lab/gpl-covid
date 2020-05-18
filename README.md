![build](https://github.com/bolliger32/gpl-covid/workflows/CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# The Effect of Large-Scale Anti-Contagion Policies on the COVID-19 Pandemic

This repository contains code and data necessary to replicate the findings of [our paper](https://www.medrxiv.org/content/10.1101/2020.03.22.20040642v3).

## Setup
Scripts in this repository are written in R, Python, and Stata. Note that you will need a Stata license to fully replicate the analysis (provided in the CodeOcean capsule). Throughout this Readme, when indicating paths to code and data, it is assumed that you’ll execute scripts from the repo root directory.

### CodeOcean Capsule
The easiest way to interact with our code and data is via our CodeOcean capsule, because all of the relevant setup described below has been done for you. You may replicate the full analysis through the "Reproducible Run" feature or interact directly with our code through Jupyter Notebooks that run Python, R, and Stata. You may also utilize RStudio. If you wish to use the command line on a cloud workstation, you will want to activate our conda environment with `conda activate gpl-covid`.

### Github Repository
You may also view and download source code from our [Github Repository](https://github.com/bolliger32/gpl-covid). "v0.4.5" is the tag that is associated with the current version of the manuscript (as of 05/18/2020), but you may also view the latest codebase and datasets on the master branch. To run this code, you will first want to create and activate our [conda](https://docs.conda.io/projects/conda/en/latest/index.html) environment.

```bash
conda env create -f environment/environment.yml
conda activate gpl-covid
```

Once you have activated this environment, to run some of the Python scripts, you’ll need to install the small package (1 module) that is included in this repo.

```bash
pip install -e code
```

To execute the full `run.sh` script, which runs the analysis from start to finish, you will also need to add this conda environment to the kernels that Jupyter is able to use (this is only needed to run simulations used to create Extended Data Figures 8 and 9). You do this with the following command (from inside the `gpl-covid` conda environment):

```bash
python -m ipykernel install --user --name gpl-covid
```

Finally, to estimate the regression models, you will need several package installed in Stata. To add them, launch Stata and run:

```
ssc install reghdfe, replace
ssc install ftools, replace # the latest version of reghdfe would also require the installation of ftools
ssc install coefplot, replace
ssc install filelist, replace
ssc install outreg2, replace
ssc install carryforward, replace
```

## Code Structure
```text
code
├── LICENSE
├── data
│   ├── china
│   │   ├── collate_data.py
│   │   └── download_and_clean_JHU_china.R
│   ├── cutoff_dates.csv
│   ├── france
│   │   ├── download_and_clean_JHU_france.R
│   │   ├── format_infected.do
│   │   └── format_policy.do
│   ├── iran
│   │   ├── download_and_clean_JHU_iran.R
│   │   ├── iran-split-interim-into-processed.py
│   │   └── iran_cleaning.R
│   ├── italy
│   │   ├── download_and_clean_JHU_italy.R
│   │   └── italy-download-cases-merge-policies.py
│   ├── korea
│   │   ├── download_and_clean_JHU_korea.R
│   │   ├── generate_KOR_processed.R
│   │   └── make_JHU_comparison_data.R
│   ├── multi_country
│   │   ├── convert-policies-raw-to-interim.py
│   │   ├── download_6_countries_JHU.R
│   │   ├── get_JHU_country_data.R
│   │   ├── get_adm_info.py
│   │   └── quality-check-processed-datasets.py
│   └── usa
│       ├── add_testing_regimes_to_covidtrackingdotcom_data.ipynb
│       ├── add_testing_regimes_to_covidtrackingdotcom_data.py
│       ├── check_health_data.R
│       ├── download_and_clean_JHU_usa.R
│       ├── download_and_clean_usafacts.R
│       ├── download_latest_covidtrackingdotcom_data.py
│       ├── gen_state_name_abbrev_xwalk.R
│       ├── get_usafacts_data.R
│       └── merge_policy_and_cases.py
├── models
│   ├── CHN_create_CBs.R
│   ├── CHN_generate_data_and_model_projection.R
│   ├── FRA_create_CBs.R
│   ├── FRA_generate_data_and_model_projection.R
│   ├── IRN_create_CBs.R
│   ├── IRN_generate_data_and_model_projection.R
│   ├── ITA_create_CBs.R
│   ├── ITA_generate_data_and_model_projection.R
│   ├── KOR_create_CBs.R
│   ├── KOR_generate_data_and_model_projection.R
│   ├── USA_create_CBs.R
│   ├── USA_generate_data_and_model_projection.R
│   ├── alt_growth_rates
│   │   ├── CHN_adm2.do
│   │   ├── FRA_adm1.do
│   │   ├── IRN_adm1.do
│   │   ├── ITA_adm2.do
│   │   ├── KOR_adm1.do
│   │   ├── MASTER_run_all_reg.do
│   │   ├── USA_adm1.do
│   │   └── disaggregated_policies
│   │       ├── FRA_adm1_disag.do
│   │       ├── IRN_adm1_disag.do
│   │       ├── ITA_adm2_disag.do
│   │       ├── KOR_adm1_disag.do
│   │       ├── MASTER_run_all_reg_disag.do
│   │       └── USA_adm1_disag.do
│   ├── get_gamma.py
│   ├── output_underlying_projection_output.R
│   ├── predict_felm.R
│   ├── projection_helper_functions.R
│   ├── run_all_CB_simulations.R
│   ├── run_projection_sensitivity.R
│   └── test_that_r_coefs_match_stata.R
├── notebooks
│   ├── archived
│   │   ├── addl-sim-plots.ipynb
│   │   └── resimulate-outbreaks.ipynb
│   └── simulate-and-regress.ipynb
├── plotting
│   ├── aggregate_fig1_source_data.py
│   ├── count-policies.py
│   ├── distribution_of_policies_by_dow.R
│   ├── examine_lagged_relationship_between_new_deaths_recoveries_and_older_cases.R
│   ├── extended_data_fig3_4.do
│   ├── extended_data_fig5.do
│   ├── fig1.R
│   ├── fig2.R
│   ├── fig4_analysis.py
│   ├── figED1.py
│   ├── figED2.R
│   ├── gen_fig4.py
│   ├── pre_policy_growth.do
│   └── sims.py
├── run.sh
├── setup.py
├── src
│   ├── impute.py
│   ├── merge.py
│   ├── models
│   │   └── epi.py
│   ├── pop.py
│   └── utils.py
└── statab.sh
```

## Data Documentation
A detailed description of the epidemiological and policy data obtained and processed for this analysis can be found in the Supplementary Information associated with the article linked at the top of this README. A description of the variables appearing in `data/processed/[adm]/[country]_processed.csv` is available in [data/raw/multi_country/data_dictionary.xlsx](data/raw/multi_country/data_dictionary.xlsx). The epidemiological and policy data sources for all countries are listed in [data/raw/multi_country/data_sources.xlsx](data/raw/multi_country/data_sources.xlsx).

## Replication Steps

There are four stages to our analysis:
1. Data collection and processing
2. Regression model estimation
3. SIR model projections
4. Figure creation

The end dates of the data analyzed, and of the "cases averted" projections, are controlled by `code/data/cutoff_dates.csv`.

### Run full pipeline
The entire pipeline can be run by calling `bash code/run.sh`. If you would rather do it step by step, see the description of each stage below. There are four flags that can be passed to that script to change the default behavior, described below:

- `-s|--no-stata`: Don't run the Stata scripts (must include this flag if you do not have Stata). In this case, the regression steps will be skipped and you will rely on previously computed regression results.
- `p|--num-proj`: Integer that controls both (a) the number of bootstrap samples when calculating projection uncertainty bounds in Fig. 4 and (b) the number of Monte Carlo samples used to create synthetic outbreaks (Extended Data Figures 8 and 9). Default 1000.
- `d|--download`: Download new raw data, rather than using that which has already been downloaded. This may affect results slightly if, e.g. a country retroactively adjusts their reported cases.

### Data collection and processing
The steps to obtain all data in <data/raw>, and then process this data into datasets that can be ingested into a regression, are described below. Note that some of the data collection was performed through manual downloading and/or processing of datasets and is described in as much detail as possible. The sections should be run in the order listed, as some files from later sections will depend on those from earlier sections (e.g. the geographical and population data).

#### Geographical and population data
1. `python code/data/multi_country/get_adm_info.py`: Generates shapefiles and csvs with administrative unit names, geographies, and populations (most countries).
2. For Chinese city-level population data, the dataset is extracted from a compiled dataset of the 2010 Chinese City Statistical Yearbooks. We manually matched the city level population dataset to the city level COVID-19 epidemiology dataset. The resulting file is in [data/raw/china/china_city_pop.csv](data/raw/china/china_city_pop.csv).
3. For Korean population data, download from [Statistics Korea](http://kosis.kr/statHtml/statHtml.do?orgId=101&tblId=DT_1B040A3&vw_cd=MT_ZTITLE&list_id=A6&seqNo=&lang_mode=ko&language=kor&obj_var_id=&itm_id=&conn_path=MT_ZTITLE) (a similar page in English is available [here](http://kosis.kr/statHtml/statHtml.do?orgId=101&tblId=DT_1B04005N&language=en))

    a. Click the `ITEM` tab and check the `Population` box only.

    b. Click the `By Administrative District` tab and check `1 Level Select all`.

    c. Click the `By Age Group` tab and check the `Total` box only.

    d. Click the `Time` tab and check `Monthly` and `2020.02`.

    e. Click the green `Search` button on the upper right of the window.

    f. Click the blue `Download` button under the `Search` button.

    g. Select `CSV` as `File format` and download.

    h. Open this file, remove the top two rows and the second column. Then change the header (the top row to `adm1_name, population`). Save to [data/interim/korea/KOR_population.csv](data/interim/korea/KOR_population.csv).

#### Policy and testing data
Most policy and testing data was manually collected from a variety of sources. A mapping was developed from each policy to one of the variables we encode for our regression. These sources and mappings are listed in a csv for each country following the pattern `data/raw/[country_name]/[country_code]_policy_data_sources.csv`.

In the U.S., testing regime data is obtained programmatically, via these steps:
1. `python code/data/usa/download_latest_covidtrackingdotcom_data.py`: Downloads testing regime data. **Note**: It seems this site has been getting high traffic and frequently fails to process requests. If this script throws an error due to that issue, try again later.
2. `python code/data/usa/add_testing_regimes_to_covidtrackingdotcom_data.py`: Check that detected testing regime changes make sense and discard any false detections. Because this can be an interactive step, there is also a corresponding [Notebook](code/data/usa/add_testing_regimes_to_covidtrackingdotcom_data.ipynb) that you may run.

#### Epidemiological data

##### Multi-country
1. `Rscript code/data/multi_country/download_6_countries_JHU.R`: Downloads 6 countries' data from the Johns Hopkins University Data underlying [their dashboard](https://coronavirus.jhu.edu/map.html). **Note:** The JHU dataset format has been changing frequently, so it is possible that this script will need to be modified.

##### China
1. For data from January 24, 2020 onwards, we relied on [an open source GitHub project](https://github.com/BlankerL/DXY-COVID-19-Data). Download the data and save it to [data/raw/china/DXYArea.csv](data/raw/china/DXYArea.csv).
2. For data before January 24, 2020, we manually collected data, the file is in [data/raw/china/china_city_health_jan.xlsx](data/raw/china/china_city_health_jan.xlsx).

##### France
1. Download the March 12 file update for the number of confirmed cases per région from the [French government’s website](https://www.data.gouv.fr/en/datasets/fr-sars-cov-2/) and save it to [data/raw/france/fr-sars-cov-2-20200312.xlsx](data/raw/france/fr-sars-cov-2-YYYYMMDD.xlsx). This file only gets updated every 1-5 days, so we augment it with data scraped daily from a live website through March 25, 2020. At this point, the live website stopped reporting daily infections, and we're currently working to figure out if this periodically updated site will continue to produce updates.
2. `stata -b do code/data/france/format_infected.do`: Run in Stata to clean and format the French regional epidemiological dataset, set at the beginning the last sample date. Default is March 18th.

##### Iran
1. Copy all of the date lines from the "New COVID-19 cases in Iran by province" table on the [Wikipedia page tracking this outbreak in Iran](https://en.wikipedia.org/wiki/2020_coronavirus_pandemic_in_Iran).
2. Open the excel file [data/raw/iran/covid_iran.xlsx](data/raw/iran/covid_iran.xlsx). This file contains the first step cleaning template for the cases data. The tabs in this file are:

    a. `200314_cases_raw` :  A template into which raw data from the Wikipedia table -- see (1) -- should be pasted.

    b. `cases_cleaned--to_csv` :  A cleaned column format for the intermediate cases data. Simply extend the formulas (by copy/paste) in each row so that each row of the raw data is included. Do not change the column headings. Once all raw data has been included, save this tab to a csv file and save in [data/interim/iran/covid_iran_cases.csv](data/interim/iran/covid_iran_cases.csv).

##### Italy
Epi data is downloaded and merged with policy data in one step, described in [the following section](####Merge-policy-and-epidemiological-data)

##### South Korea
1. Korean epi data were manually collected from various Korean provincial websites. Note that these provinces often report the data in different formats (e.g. pdf attachments, interactive dashboards) and usually do not have English translations. This data is saved in [data/interim/korea/KOR_health.csv](data/interim/korea/KOR_health.csv).

##### USA
1. `Rscript code/data/usa/download_and_clean_usafacts.R`: Downloads county- and state-level data from [usafacts.org](https://usafacts.org/visualizations/coronavirus-covid-19-spread-map/)

#### Merge all data for each country
Run the following scripts to merge epi, policy, testing, and population data for each country. After completion, you may run [code/data/multi_country/quality-check-processed-datasets.py](code/data/multi_country/quality-check-processed-datasets.py), to make sure all of the fully processed datasets are correctly and consistently formatted.

##### Include policies implied by other policies
`python code/data/multi_country/convert-policies-raw-to-interim.py`

##### China
`python code/data/china/collate_data.py`

##### France
`stata -b do code/data/france/format_policy.do`

##### Iran
1. `Rscript code/data/iran/iran_cleaning.R`
2. `python code/data/iran/iran-split-interim-into-processed.py`

##### Italy
`python code/data/italy/italy-download-cases-merge-policies.py`

##### South Korea
`Rscript code/data/korea/generate_KOR_processed.R`

##### United States
`python code/data/usa/merge_policy_and_cases.py`: Merge all US data. This outputs [data/processed/adm1/USA_processed.csv](data/processed/adm1/USA_processed.csv).

### Regression model estimation
Once data is obtained and processed, you can estimate regression models for each country using the following command:

`stata -b do code/models/alt_growth_rates/MASTER_run_all_reg.do`

You can optionally pass an integer command line argument if you would like to include bootstrapped estimates of the r2 vs. fixed lag length analysis (ED Fig 5b).

Each of the individual country regressions are also available to be run within [code/models/alt_growth_rates](code/models/alt_growth_rates).

### SIR model projections
Once the regression coefficients have been estimated in the above models, run the following code to generate projections of active and cumulative infections using an SIR model:

1. `python code/models/get_gamma.py`: Estimate removal rate to use in projections from data that contains both cumulative cases and active cases.
2. `Rscript code/models/run_all_CB_simulations.R`: Generate the csv inputs for Figure 4.
3. `Rscript code/models/output_underlying_projection_output.R`: Output the raw projection output if you wish to examine the underlying output.

### Figure creation
To generate the four figures in the paper, run the following scripts. Figure 1 only requires the data collection steps to be complete. Figures 2 and 3 require the regression step to be complete, and Figure 4 requires the projection step to be complete and to have previously run the code for Figure 1. Each of the Extended Data Figures and Supplementary Information Tables may require different steps of the analysis to be finalized.

#### Figure 1

1. `Rscript code/plotting/fig1.R`: Generate 12 outputs that constitute Figure 1 (`*_timeseries.pdf`, and `*_map.pdf` for each of the 6 countries). **Note:** This script requires [data/raw/china/match_china_city_name_w_adm2.csv](data/raw/china/match_china_city_name_w_adm2.csv), a manually generated crosswalk of Chinese city names.
2. `python code/plotting/aggregate_fig1_source_data.py`: Combine csv's into the "source_data" excel file.

#### Figure 2

`Rscript code/plotting/fig2.R`: Generate 3 outputs that constitute Figure 2, in `results/figures/fig2`:
- *Panel A*: `Fig2A_nopolicy.pdf`
- *Panel B*: `Fig2B_comb.pdf`
- *Panel C*: `Fig2C_ind.pdf`

#### Figure 3

Figure 3 is generated by the regression estimation step (`code/models/alt_growth_rates/MASTER_run_all_reg.do`).

#### Figure 4

Note that the outputs of [code/plotting/fig1.R](code/plotting/fig1.R) are required for Fig 4 as well.
1. (if not already generated) `Rscript code/plotting/fig1.R`: Generate the cases data
2. `python code/plotting/gen_fig4.py`: Generate Figure 4.
3. `python code/plotting/fig4_analysis.py`: Generate a printout of numerical results from the projections for each country.

#### Extended Data Figure 1

1. `Rscript code/data/korea/make_JHU_comparison_data.R`: Create [data/interim/korea/KOR_JHU_data_comparison.csv](data/interim/korea/KOR_JHU_data_comparison.csv)
2. `python code/plotting/figED1.py`: Generate 2 outputs that constitute ED Figure 1 (`results/figures/appendix/EDFigure1-2.pdf` and `results/figures/appendix/EDFigure1-2.pdf`)

#### Extended Data Figure 2

`Rscript code/plotting/figED2.R`: Generate ED Figure 2 (`results/figures/appendix/figED2.pdf`).

#### Extended Data Figures 3-4

`stata -b do code/plotting/extended_data_fig3_4.do`: Generate a csv with point estimate and standard errors used to plot a mock PDF version of ED Figures 3 and 4. The final version in printed document are designed using Adobe Illustrator.

#### Extended Data Figure 5

1. Panel a is part of the regression estimation step (`code/models/alt_growth_rates/MASTER_run_all_reg.do`).
2. Panels b and c are directly generated by `stata -b do code/plotting/extended_data_fig5.do` using result of the regression estimation step (`code/models/alt_growth_rates/MASTER_run_all_reg.do`)

#### Extended Data Figure 6

`stata -b do code/models/alt_growth_rates/disaggregated_policies/MASTER_run_all_reg_disag.do`

#### Extended Data Figure 7

`Rscript code/models/run_projection_sensitivity.R`

#### Extended Data Figures 8 and 9

1. `papermill code/notebooks/simulate-and-regress.ipynb code/notebooks/simulate-and-regress-log.ipynb -k gpl-covid`: Run Monte Carlo simulations of synthetic outbreaks
2. `python code/plotting/sims.py results/other/sims/measNoise_0.05_betaNoise_Exp_gammaNoise_0.01_sigmaNoise_0.03 results/figures/appendix/sims --source-dir "results/source_data/ExtendedDataFigure89.csv"`: Create figures

#### Extended Data Figure 10

ED Figure 10 is generated by the regression estimation step (`code/models/alt_growth_rates/MASTER_run_all_reg.do`). The final output file is `figures/appendix/ALL_conf_cases_e.png`

### Table Creation

#### Supplementary Information Table 1

`python code/plotting/count-policies.py`

#### Supplementary Information Table 2

This table is not generated programatically.

#### Supplementary Information Table 3

This table is generated by the regression estimation step (`code/models/alt_growth_rates/MASTER_run_all_reg.do`).

#### Supplementary Information Table 4

This table is generated by the regression estimation step using disaggregated policy variables (`code/models/alt_growth_rates/disaggregated_policies/MASTER_run_all_reg_disag.do`).

#### Supplementary Information Table 5

This table is generated by the regression estimation step (`code/models/alt_growth_rates/MASTER_run_all_reg.do`).
