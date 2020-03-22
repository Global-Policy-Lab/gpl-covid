// Master do file that runs all regression scripts

clear all

// optional scheme for graphs
capture set scheme covid19_fig3 

// create folders for figure output
capture mkdir "figures/fig3/raw" 
capture mkdir "figures/appendix/error_dist" 

// run .do files
do "codes/models/alt_growth_rates/CHN_adm2.do"
do "codes/models/alt_growth_rates/KOR_adm1.do"
do "codes/models/alt_growth_rates/ITA_adm2.do"
do "codes/models/alt_growth_rates/IRN_adm1.do"
do "codes/models/alt_growth_rates/FRA_adm1.do"
do "codes/models/alt_growth_rates/USA_adm1.do"

// combine all case growth rate graphs for fig 3
filelist, dir("figures/fig3/raw") pattern("*_fixedx.gph")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "figures/fig3/raw/" + "`fn'"
	local graphname = regexr("`fn'", "cases_growth_rates_fixedx\.gph", "fix")
	*display "`filepath'"
	display "`graphname'"
	graph use "`filepath'", name("`graphname'", replace)
}

graph combine CHN_adm2_active_fix KOR_adm1_active_fix ITA_adm2_conf_fix ///
IRN_adm1_conf_fix FRA_adm1_conf_fix USA_adm1_conf_fix, cols(1) imargin(tiny) ysize(18) xsize(10)
graph export figures/fig3/raw/ALL_cases_growth_rates_fixedx_long.pdf, replace

// combine all error dist graphs for appendix fig A1
filelist, dir("figures/appendix/error_dist") pattern("*.gph")
levelsof filename, local(filenames)
foreach fn of local filenames{
	local filepath = "figures/appendix/error_dist/" + "`fn'"
	local graphname = regexr("`fn'", "\.gph", "")
	*display "`filepath'"
	display "`graphname'"
	graph use "`filepath'", name("`graphname'", replace)
}

graph combine error_chn error_irn error_kor error_fra error_ita error_usa, rows(3)
graph export figures/appendix/ALL_conf_cases_e.png, replace
