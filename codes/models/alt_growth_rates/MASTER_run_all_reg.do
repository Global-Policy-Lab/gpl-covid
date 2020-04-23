// Master do file that runs all regression scripts

clear all

// optional scheme for graphs
capture set scheme covid19_fig3 

// create folders for figure output 
capture mkdir "results/"
capture mkdir "results/figures/"
capture mkdir "results/figures/fig3/" 
capture mkdir "results/figures/fig3/raw" 
capture mkdir "results/figures/appendix/" 
capture mkdir "results/figures/appendix/error_dist" 
capture mkdir "results/figures/appendix/subnatl_growth_rates" 
capture mkdir "results/figures/appendix/cross_valid" 
capture mkdir "results/figures/appendix/fixed_lag" 
capture mkdir "results/tables/" 
capture mkdir "results/tables/reg_results" 
capture mkdir "results/tables/ATE_fixed_lag" 
capture mkdir "results/source_data" 
capture mkdir "results/source_data/indiv" 

global BS = 0 // set to 1 to run bootstrap CI on fig A3-b (add 2-3 hours)

// run .do files
do "codes/models/alt_growth_rates/CHN_adm2.do"
do "codes/models/alt_growth_rates/KOR_adm1.do"
do "codes/models/alt_growth_rates/ITA_adm2.do"
do "codes/models/alt_growth_rates/IRN_adm1.do"
do "codes/models/alt_growth_rates/FRA_adm1.do"
do "codes/models/alt_growth_rates/USA_adm1.do"


// combine all case growth rate graphs for fig 3
filelist, dir("results/figures/fig3/raw") pattern("*_fixedx.gph")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/figures/fig3/raw/" + "`fn'"
	local graphname = regexr("`fn'", "cases_growth_rates_fixedx\.gph", "fix")
	*display "`filepath'"
	display "`graphname'"
	graph use "`filepath'", name("`graphname'", replace)
}

graph combine CHN_adm2_active_fix KOR_adm1_active_fix ITA_adm2_conf_fix ///
IRN_adm1_conf_fix FRA_adm1_conf_fix USA_adm1_conf_fix, cols(1) imargin(tiny) ysize(18) xsize(10)
graph export results/figures/fig3/raw/ALL_cases_growth_rates_fixedx_long.pdf, replace

// combine all error dist graphs for ED fig 10
filelist, dir("results/figures/appendix/error_dist") pattern("*.gph")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/figures/appendix/error_dist/" + "`fn'"
	local graphname = regexr("`fn'", "\.gph", "")
	*display "`filepath'"
	display "`graphname'"
	graph use "`filepath'", name("`graphname'", replace)
}

graph combine error_chn error_irn error_kor error_fra error_ita error_usa, rows(3)
graph export results/figures/appendix/error_dist/ALL_conf_cases_e.png, replace


// make table comparing ATE models with different fixed lags by country
filelist, dir("models") pattern("*_ATE.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "models/" + "`fn'"
	local tempname = regexr("`fn'", "\.csv", "")
	insheet using `filepath', clear
	
	tempfile `tempname'
	save ``tempname'', replace
}

use `CHN_ATE', clear
drop if lag==0 & adm0=="CHN"
foreach c in KOR ITA IRN FRA USA {
	append using ``c'_ATE'
}

foreach var of varlist ate lb ub r2 {
	replace `var' = round(`var', .001)
	gen value_`var' = string(`var')
}

replace lag = 0 if lag==.
gen value_ci = "(" + value_lb + ", " + value_ub + ")"

keep adm0 lag value_ate value_ci value_r2
order adm0 lag value_ate value_ci value_r2

reshape long value_, i(adm0 lag) j(stat, str)
reshape wide value_, i(adm0 stat) j(lag)
rename value_* lag*

replace stat = strupper(stat)
replace stat = "95% CI" if stat=="CI"
rename (adm0 stat) (Country Statistic)
outsheet using "results/tables/ATE_fixed_lag/ATE_comparison_fixed_lag.csv", comma replace


// combine all source data for fig 2
filelist, dir("results/source_data/indiv") pattern("Figure2_*.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/source_data/indiv/" + "`fn'"
	local tempname = regexr("`fn'", "\.csv", "")
	insheet using `filepath', clear
	display "`tempname'"
	tempfile `tempname'
	save ``tempname'', replace
}
use `Figure2_CHN_coefs', clear
foreach c in KOR ITA IRN FRA USA {
	append using `Figure2_`c'_coefs'
}
outsheet using "results/source_data/Figure2_data.csv", comma replace

// combine all source data for fig 3
filelist, dir("results/source_data/indiv") pattern("Figure3_*.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/source_data/indiv/" + "`fn'"
	local tempname = regexr("`fn'", "\.csv", "")
	insheet using `filepath', clear	
	tempfile `tempname'
	save ``tempname'', replace
}
use `Figure3_FRA_data', clear
replace adm0_name = "FRA" if adm0_name=="France"
rename t date

foreach c in CHN KOR ITA IRN USA {
	append using `Figure3_`c'_data'
}
replace t = string(date, "%td") if adm0_name=="FRA"
drop date
order adm0_name t
outsheet using "results/source_data/Figure3_data.csv", comma replace

// combine all source data for ED fig 10
filelist, dir("results/source_data/indiv") pattern("ExtendedDataFigure10_*_e.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/source_data/indiv/" + "`fn'"
	local tempname = regexr("`fn'", "\.csv", "")
	insheet using `filepath', clear
	display "`tempname'"
	tempfile `tempname'
	save ``tempname'', replace
}
use `ExtendedDataFigure10_CHN_e', clear
foreach c in KOR ITA IRN FRA USA {
	append using `ExtendedDataFigure10_`c'_e'
}
replace adm0_name = "FRA" if adm0_name=="France"
outsheet using "results/source_data/ExtendedDataFigure10_e.csv", comma replace

