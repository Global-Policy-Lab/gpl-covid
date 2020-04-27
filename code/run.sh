#!/usr/bin/env bash
set -e

# set working directory to root of gpl-covid as assumed by some scripts
cd "$(dirname "$0")/.."

source $CONDA_PREFIX_1/etc/profile.d/conda.sh
conda activate gpl-covid

# install our utilities
pip install -e code

## parse flags to not run certain things
STATA=true
CENSUS=false
NUMPROJ=1000
DOWNLOAD=false
for arg in "$@"
do
    case $arg in
        -s|--nostata)
            STATA=false
            shift
        ;;
        -c|--census)
            CENSUS=true
            shift
        ;;
        -p|--num-proj)
            NUMPROJ="$2"
            shift
            shift
        ;;
      	-d|--download)
      	    DOWNLOAD=true
      	    shift
      	;;
    esac

done


## data scraping and processing


### Geography/population
if $CENSUS && $DOWNLOAD
then
    printf "***Downloading shape and population info for all countries***\n"
    python code/data/multi_country/get_adm_info.py
fi

### Policy
if $DOWNLOAD
then
    printf "***Downloading USA testing data***\n"
    python code/data/usa/download_latest_covidtrackingdotcom_data.py
    python code/data/usa/add_testing_regimes_to_covidtrackingdotcom_data.py
fi

### Epi
#### Multi-country
if $DOWNLOAD
then
    printf "***Downloading Johns Hopkins U data for all countries***\n"
    Rscript code/data/multi_country/download_6_countries_JHU.R
fi

#### FRA
if $STATA
then
    printf "***Processing FRA epi data***\n"
    code/statab.sh code/data/france/format_infected.do
fi

#### USA
if $DOWNLOAD
then
    printf "***Processing USA epi data***\n"
    Rscript code/data/usa/download_and_clean_usafacts.R
fi

### Dataset merging
#### CHN
printf "***Processing and merging CHN data***\n"
python code/data/china/collate_data.py

#### FRA
if $STATA
then
    printf "***Merging FRA data***\n"
    code/statab.sh code/data/france/format_policy.do
fi

# IRN
printf "***Processing  and merging IRN data***\n"
Rscript code/data/iran/iran_cleaning.R
python code/data/iran/iran-split-interim-into-processed.py

# ITA
printf "***Processing  and merging ITA data***\n"
if $DOWNLOAD
then
    python code/data/italy/italy-download-cases-merge-policies.py
else
    python code/data/italy/italy-download-cases-merge-policies.py --nr
fi

# KOR
printf "***Processing  and merging KOR data***\n"
Rscript code/data/korea/generate_KOR_processed.R

# USA
printf "***Merging USA data***\n"
python code/data/usa/merge_policy_and_cases.py

# quality-check processed datasets
printf "***Checking processed data***\n"
python code/data/multi_country/quality-check-processed-datasets.py

## regression model estimation
if $STATA
then
    printf "***Estimating regression model and creating Figure 3, SI Table 3, SI Table 5, ED Figure 10***\n"
    code/statab.sh code/models/alt_growth_rates/MASTER_run_all_reg.do $NUMPROJ
fi


## SIR model projection
printf "***Projecting infections***\n"
python code/models/get_gamma.py
Rscript code/models/run_all_CB_simulations.R $NUMPROJ

# This one outputs all the raw projection output for diagnostic purposes.
Rscript code/models/output_underlying_projection_output.R

## Figures and tables

# Fig 1
printf "***Creating Fig 1***\n"
Rscript code/plotting/fig1.R
python code/plotting/aggregate_fig1_source_data.py

# Fig 2
printf "***Creating Fig 2***\n"
Rscript code/plotting/fig2.R

# Fig 3
# created by regression model estimation

# Fig 4
printf "***Creating Fig 4***\n"
python code/plotting/gen_fig4.py
python code/plotting/fig4_analysis.py

# ED Figure 1
printf "***Creating ED Fig 1***\n"
if $DOWNLOAD
then
    python code/plotting/figED1.py
else
    python code/plotting/figED1.py --nd
fi

# ED Figure 2
if $DOWNLOAD
then
    printf "***Creating ED Fig 2***\n"
    Rscript code/plotting/figED2.R
else
    Rscript code/plotting/figED2.R --nd
fi

# ED Figure 3-4
if $STATA
then
    printf "***Creating ED Fig 3 and 4***\n"
    code/statab.sh code/plotting/extended_data_fig3_4.do
fi

# ED Figure 5
if $STATA
then
    printf "***Creating ED Fig 5***\n"
    if [ $NUMPROJ == 1000 ]; then
        code/statab.sh code/plotting/extended_data_fig5.do
    else
        code/statab.sh code/plotting/extended_data_fig5.do nosave
    fi
fi

# ED Figure 6
if $STATA
then
    printf "***Estimating regression model with disaggregated policy variables and creating ED Figure 6 and SI Table 4***\n"
    code/statab.sh code/models/alt_growth_rates/disaggregated_policies/MASTER_run_all_reg_disag.do
fi

# ED Figure 7 (Projection with multiple gamma plot - replace this text when numbered)
printf "***Creating ED Fig 7***\n"
Rscript code/models/run_projection_with_multiple_gammas.R

# ED Figure 8/9
printf "***Creating ED Fig 8/9***\n"
printf "Running simulations..."
papermill code/notebooks/simulate-and-regress.ipynb code/notebooks/simulate-and-regress-log.ipynb -p n_samples $NUMPROJ -k gpl-covid
printf "Making Figures..."
if [ $NUMPROJ = 1000 ]; then
    python code/plotting/sims.py results/other/sims/measNoise_0.05_betaNoise_Exp_gammaNoise_0.01_sigmaNoise_0.03 results/figures/appendix/sims --source-data "results/source_data/ExtendedDataFigure89.csv"
else
    python code/plotting/sims.py results/other/sims/measNoise_0.05_betaNoise_Exp_gammaNoise_0.01_sigmaNoise_0.03 --LHS I
fi

# ED Figure 10
# created by regression model estimation

# SI Table 1
printf "***Creating SI Table 1***\n"
python code/plotting/count-policies.py

# SI Table 2
# generated manually

# SI Table 3
# created by regression model estimation

# SI Table 4
# created by regression model estimation with disaggregated policy variables for ED Figure 6

# SI Table 5
# created by regression model estimation
