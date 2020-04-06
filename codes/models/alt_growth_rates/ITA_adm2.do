// ITA | adm2

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm2/ITA_processed.csv, clear

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)


// clean up
drop if adm2_name == "Unknown"
drop adm1_id adm2_id
encode adm1_name, gen(adm1_id)
encode adm2_name, gen(adm2_id)
duplicates report adm2_id t

// set up panel
tsset adm2_id t, daily

// quality control
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 
drop if t < mdy(2,26,2020) // start Feb 26
keep if t <= date("`end_sample'","YMD") // to match other country end dates

// flag which admin unit has longest series
tab adm2_name if cum_confirmed_cases!=., sort 
bysort adm1_name adm2_name: egen adm2_obs_ct = count(cum_confirmed_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name adm2_name: egen adm2_max_cases = max(cum_confirmed_cases)
egen max_obs_ct = max(adm2_obs_ct)
bysort adm2_obs_ct: egen max_obs_ct_max_cases = max(adm2_max_cases) 

gen longest_series = adm2_obs_ct==max_obs_ct & adm2_max_cases==max_obs_ct_max_cases
drop adm2_obs_ct adm2_max_cases max_obs_ct max_obs_ct_max_cases

sort adm2_id t
tab adm2_name if longest_series==1 & cum_confirmed_cases!=.

// construct dep vars
lab var cum_confirmed_cases "cumulative confirmed cases"

gen l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_cum_confirmed_cases "log(cum_confirmed_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases 
lab var D_l_cum_confirmed_cases "change in log(cum_confirmed_cases)"

// quality control: cannot have negative changes in cumulative values
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 


//--------------testing regime changes

// testing regime change on Feb 26, which is the start of sample so now changes to account for
// // grab each date of any testing regime change
// preserve
// 	collapse (min) t, by(testing_regime)
// 	sort t //should already be sorted but just in case
// 	drop if _n==1 //dropping 1st testing regime of sample (no change to control for)
// 	levelsof t, local(testing_change_dates)
// restore
//
// // create a dummy for each testing regime change date
// foreach t_chg of local testing_change_dates{
// 	local t_str = string(`t_chg', "%td")
// 	gen testing_regime_change_`t_str' = t==`t_chg'
// }

//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons] if longest_series==1


reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1
lab var day_avg "Observed avg. change in log cases"

tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

// capture: drop p_*
// gen p_1 = (work_from_home_opt_popwt + social_distance_opt_popwt  + home_isolation_popwt + no_gathering_popwt + business_closure_popwt)/5
// gen p_2 = travel_ban_local_popwt
// gen p_3 = pos_cases_quarantine_popwt   
// gen p_4 = school_closure_popwt  
//
// lab var p_1 "social distancing, stay home"
// lab var p_2 "local travel ban"
// lab var p_3 "quarantine positive cases"
// lab var p_4 "school closure"

// popwt vars = policy intensity * population weight of respective admin 2 unit or sub admin 2 unit

// combine optional policies with respective mandatory policies
// weighing optional policies by 1/2
gen social_distance_comb_popwt = social_distance_popwt + social_distance_opt_popwt * 0.5 
gen work_from_home_comb_popwt = work_from_home_popwt + work_from_home_opt_popwt * 0.5


gen p_1 = (no_gathering_popwt + social_distance_comb_popwt + work_from_home_comb_popwt)/3
gen p_2 = business_closure_popwt
gen p_3 = school_closure_popwt  
gen p_4 = (travel_ban_local_popwt + transit_suspension_popwt)/2 //transit_suspensions all happen on 2/23 with travel_ban_local in respective admin units
gen p_5 = home_isolation_popwt   
gen p_6 = pos_cases_quarantine_popwt 

lab var p_1 "social distancing, stay home"
lab var p_4 "business closure"
lab var p_3 "school closure"
lab var p_4 "local travel ban, transit suspension"
lab var p_5 "home isolation"
lab var p_6 "quarantine positive cases"

 
//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/ITA_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_*, absorb(i.adm2_id i.dow, savefe) cluster(t) resid

outreg2 using "results/tables/ITA_estimates_table", word replace label ///
 addtext(Province FE, "YES", Day-of-Week FE, "YES") title("Regression output: Italy")
cap erase "results/tables/ITA_estimates_table.txt"


// looking at different policies (similar to Fig2)
coefplot, keep(p_*)

tempfile results_file
postfile results str18 adm0 str18 policy beta se using `results_file', replace
foreach var in "p_1" "p_2" "p_3" "p_4" "p_5" "p_6"{
	post results ("ITA") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}
// effect of package of policies (FOR FIG2)
lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6
post results ("ITA") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 


//------------- checking error structure (appendix)

predict e if e(sample), resid

hist e, bin(30) tit(Italy) lcolor(white) fcolor(navy) xsize(5) name(hist_ita, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_ita, replace)

graph combine hist_ita qn_ita, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_ita.gph, replace)
graph drop hist_ita qn_ita


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1 * _b[p_1] + ///
p_2 * _b[p_2] + ///
p_3 * _b[p_3] + /// 
p_4 * _b[p_4] + /// 
p_5 * _b[p_5] + /// 
p_6 * _b[p_6] /// 
if e(sample)

// predicting counterfactual growth for each obs
predictnl y_counter = _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// compute ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases  p_* 
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] + p_3*_b[p_3] + p_4*_b[p_4] + p_5*_b[p_5] + p_6*_b[p_6], ci(LB UB) se(sd) p(pval)
	g adm0 = "ITA"
	outsheet * using "models/ITA_ATE.csv", comma replace 
restore

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix lb_y_actual so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}
	
// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("ITA") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

//export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "ITA"
	outsheet * using "models/ITA_preds.csv", comma replace
restore

// the mean average growth rate suppression delivered by existing policy (FOR TEXT)
sum treatment

// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual i.t
predict m_y_actual if longest_series==1

reg y_counter i.t
predict m_y_counter if longest_series==1


postclose results

preserve
	use `results_file', clear
	outsheet * using "models/ITA_coefs.csv", comma replace
restore

// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10

// Graph of predicted growth rates (FOR FIG3)

// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(Italy, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22007)) xlabel(21930(10)22007, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/ITA_adm2_conf_cases_growth_rates_fixedx.gph, replace)


//-------------------------------Running the model for Lombardy only 

reghdfe D_l_cum_confirmed_cases p_* if adm1_name == "Lombardia", absorb(i.adm2_id i.dow, savefe) cluster(t) resid

// predicted "actual" outcomes with real policies
predictnl y_actual_lom = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual_lom ub_y_actual_lom)

// predicting counterfactual growth for each obs
predictnl y_counter_lom = _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter_lom ub_counter_lom)

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual_lom y_counter_lom lb_y_actual_lom ub_y_actual_lom lb_counter_lom ub_counter_lom {
	replace `var' = 0 if `var'<0 & `var'!=.
}

// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual_lom i.t if adm1_name == "Lombardia"
predict m_y_actual_lom if adm2_name=="Bergamo"

reg y_counter_lom i.t if adm1_name == "Lombardia"
predict m_y_counter_lom if adm2_name=="Bergamo"

// Observed avg change in log cases
reg D_l_cum_confirmed_cases i.t if adm1_name == "Lombardia"
predict day_avg_lom if adm2_name=="Bergamo" & e(sample) == 1

// Graph of predicted growth rates
// fixed x-axis across countries
tw (rspike ub_y_actual_lom lb_y_actual_lom t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter_lom lb_counter_lom t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual_lom t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter_lom t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual_lom t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter_lom t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg_lom t, color(black)) ///
if e(sample), ///
title("Lombardy, Italy", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") xtit("") ///
xscale(range(21930(10)22007)) xlabel(21930(10)22007, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/sub_natl_growth_rates/Lombardy_conf_cases_growth_rates_fixedx.gph, replace)


//-------------------------------Running the model for certain provinces

gen cases_to_pop = cum_confirmed_cases / population
egen cases_to_pop_max = max(cases_to_pop)
tab adm2_name if cases_to_pop==cases_to_pop_max //Cremona

foreach province in "Cremona" "Bergamo" "Lodi" {

	reghdfe D_l_cum_confirmed_cases p_* if adm2_name=="`province'", noabsorb

	// predicted "actual" outcomes with real policies
	predictnl y_actual_`province' = xb() if e(sample), ci(lb_y_actual_`province' ub_y_actual_`province')
		
	// predicting counterfactual growth for each obs
	predictnl y_counter_`province' = _b[_cons] if e(sample), ci(lb_counter_`province' ub_counter_`province')

	// quality control: don't want to be forecasting negative growth (not modeling recoveries)
	// fix so there are no negative growth rates in error bars
	foreach var of varlist y_actual_`province' y_counter_`province' lb_y_actual_`province' ub_y_actual_`province' lb_counter_`province' ub_counter_`province' {
		replace `var' = 0 if `var'<0 & `var'!=.
	}

	// Observed avg change in log cases
	reg D_l_cum_confirmed_cases i.t if adm2_name=="`province'"
	predict day_avg_`province' if adm2_name=="`province'" & e(sample) == 1
	
	// Graph of predicted growth rates
	// fixed x-axis across countries
	local title = "`province'" + ", Italy"
	
	tw (rspike ub_y_actual_`province' lb_y_actual_`province' t,  lwidth(vthin) color(blue*.5)) ///
	(rspike ub_counter_`province' lb_counter_`province' t, lwidth(vthin) color(red*.5)) ///
	|| (scatter y_actual_`province' t,  msize(tiny) color(blue*.5) ) ///
	(scatter y_counter_`province' t, msize(tiny) color(red*.5)) ///
	(connect y_actual_`province' t, color(blue) m(square) lpattern(solid)) ///
	(connect y_counter_`province' t, color(red) lpattern(dash) m(Oh)) ///
	(sc day_avg_`province' t, color(black)) ///
	if e(sample), ///
	title("`title'", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") xtit("") ///
	xscale(range(21930(10)21999)) xlabel(21930(10)21999, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
	yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
	saving(results/figures/appendix/sub_natl_growth_rates/`province'_conf_cases_growth_rates_fixedx.gph, replace)
}
