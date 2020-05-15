// Master do file that runs all disaggregated policy regression scripts

clear all

// create folders for output 
capture mkdir "results/"
capture mkdir "results/figures/"
capture mkdir "results/figures/appendix/" 
capture mkdir "results/figures/appendix/disaggregated_policies" 
capture mkdir "results/tables/" 
capture mkdir "results/tables/ATE_disag" 
capture mkdir "results/source_data" 
capture copy "results/source_data/indiv/Figure3_CHN_data.csv" "results/source_data/indiv/ExtendedDataFigure6a_CHN_data.csv" 

// run .do files
do "code/models/alt_growth_rates/CHN_adm2.do"
do "code/models/alt_growth_rates/disaggregated_policies/KOR_adm1_disag.do"
do "code/models/alt_growth_rates/disaggregated_policies/ITA_adm2_disag.do"
do "code/models/alt_growth_rates/disaggregated_policies/IRN_adm1_disag.do"
do "code/models/alt_growth_rates/disaggregated_policies/FRA_adm1_disag.do"
do "code/models/alt_growth_rates/disaggregated_policies/USA_adm1_disag.do"

// combine all case growth rate graphs for ED fig 6
graph use "results/figures/fig3/raw/CHN_adm2_active_cases_growth_rates_fixedx.gph", name(CHN_adm2_active_fix, replace)

filelist, dir("results/figures/appendix/disaggregated_policies") pattern("*.gph")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/figures/appendix/disaggregated_policies/" + "`fn'"
	local graphname = regexr("`fn'", "\.gph", "")
	
	display "`graphname'"
	graph use "`filepath'", name("`graphname'", replace)
}

graph combine CHN_adm2_active_fix KOR_disag ITA_disag ///
IRN_disag FRA_disag USA_disag, cols(1) imargin(tiny) ysize(18) xsize(10) name(ALL_disag, replace)
graph export results/figures/appendix/disaggregated_policies/ALL_disag.pdf, replace


graph use "results/figures/appendix/subnatl_growth_rates/Wuhan_active_cases_growth_rates_fixedx.gph", name(Wuhan_active_fix, replace)
graph use "results/figures/appendix/FRA_adm1_hosp_growth_rates_fixedx.gph", name(FRA_hosp, replace)

graph combine Wuhan_active_fix Wuhan_active_fix Wuhan_active_fix ///
FRA_hosp FRA_hosp FRA_hosp, cols(1) imargin(tiny) ysize(18.5) xsize(10)
graph export results/figures/appendix/subnatl_growth_rates/Wuhan_FRA_hosp_comb.pdf, replace


// make table comparing ATE between disaggregated model and grouped model by country
filelist, dir("models") pattern("*_ATE.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "models/" + "`fn'"
	local tempname = regexr("`fn'", "\.csv", "")
		
	insheet using `filepath', clear
	rename adm0 adm0_name
	display "`fn'"
	if "`fn'"=="CHN_ATE.csv"{
		keep if lag==.
	}
	else if "`fn'"!="CHN_ATE.csv"{
		keep if lag==0
	}
	gen model_type = "_grouped"
	
	tempfile `tempname'
	save ``tempname'', replace
}

filelist, dir("results/tables/ATE_disag") pattern("*ATE_disag.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/tables/ATE_disag/" + "`fn'"
	local tempname = regexr("`fn'", "\.csv", "")
	
	insheet using `filepath', clear
	gen model_type = "_disaggregated"
	
	tempfile `tempname'
	save ``tempname'', replace
}

use `CHN_ATE', clear
foreach c in KOR ITA IRN FRA USA {
	append using ``c'_ATE'
	append using ``c'_ATE_disag'
}

keep adm0_name model_type ate lb ub
order adm0_name model_type ate lb ub

replace adm0_name = "FRA" if adm0_name=="France"
expand 2 if adm0_name=="CHN", gen(dup)
replace model_type = "_disaggregated" if dup==1
drop dup

foreach var of varlist ate lb ub {
	replace `var' = round(`var', .001)
}

reshape wide ate lb ub, i(adm0_name) j(model_type, str)
gen ci_disaggregated = "(" + string(lb_disaggregated) + ", " + string(ub_disaggregated) + ")"
gen ci_grouped = "(" + string(lb_grouped) + ", " + string(ub_grouped) + ")"

keep adm0_name ate_grouped ci_grouped ate_disaggregated ci_disaggregated 
order adm0_name ate_grouped ci_grouped ate_disaggregated ci_disaggregated 

outsheet using "results/tables/ATE_disag/ATE_comparison_disag.csv", comma replace


// combine all source data for ED fig 6
filelist, dir("results/source_data/indiv") pattern("ExtendedDataFigure6*.csv")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "results/source_data/indiv/" + "`fn'"
	local tempname = subinstr(regexr("`fn'", "_data\.csv", ""), "ExtendedDataFigure6", "", .)
	insheet using `filepath', clear
	
	if regexm("`fn'", "FRA|France"){
		replace adm0_name = "FRA" if adm0_name=="France"
		rename t t0
		gen t = string(t0, "%td")
		drop t0
	}	
	tempfile `tempname'
	save ``tempname'', replace
}
use `a_CHN', clear
foreach c in KOR ITA IRN FRA USA {
	append using `a_`c''
}
export excel using "results/source_data/ExtendedDataFigure6.xlsx", sheet("panel_a") firstrow(var) sheetreplace

use `b_Wuhan', clear
export excel adm* t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter day_avg ///
using "results/source_data/ExtendedDataFigure6.xlsx", sheet("panel_b") firstrow(var) sheetreplace

use `c_FRA_hosp', clear
order adm0_name t
export excel using "results/source_data/ExtendedDataFigure6.xlsx", sheet("panel_c") firstrow(var) sheetreplace
