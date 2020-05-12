// KOR | ADM1

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/KOR_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

// clean up
capture: drop adm2_id
encode adm1_name, gen(adm1_id)
duplicates report adm1_id t

// set up panel
tsset adm1_id t, daily

// quality control
replace active_cases = . if cum_confirmed_cases < 10 
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 

keep if t >= mdy(2,17,2020) // start date
keep if t <= date("`end_sample'","YMD") // to match other country end dates

// flag which admin unit has longest series
tab adm1_name if active_cases!=., sort 
bysort adm1_name: egen adm1_obs_ct = count(active_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name: egen adm1_max_cases = max(active_cases)
egen max_obs_ct = max(adm1_obs_ct)
bysort adm1_obs_ct: egen max_obs_ct_max_cases = max(adm1_max_cases) 

gen longest_series = adm1_obs_ct==max_obs_ct & adm1_max_cases==max_obs_ct_max_cases
drop adm1_obs_ct adm1_max_cases max_obs_ct max_obs_ct_max_cases

sort adm1_id t
tab adm1_name if longest_series==1 & active_cases!=.


// construct dep vars
lab var active_cases "active cases"

gen l_active_cases = log(active_cases)
lab var l_active_cases "log(active_cases)"

g l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_active_cases "log(cum_confirmed_cases)"

gen D_l_active_cases = D.l_active_cases 
*lab var D_l_active_cases "change in log(active_cases)"
lab var D_l_active_cases "Growth rate of active cases (\u0916?log per day)"


//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT

// this causes a smooth transition to avoid having negative transmissions, corrects for recoveries and deaths when the log approximation is not very good
gen transmissionrate = D.cum_confirmed_cases/L.active_cases 
gen D_l_active_cases_raw = D_l_active_cases 
lab var D_l_active_cases_raw "change in log active cases (no recovery adjustment)"
replace D_l_active_cases = transmissionrate if D_l_active_cases_raw < 0.04

//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT: END


// quality control
replace D_l_active_cases = . if D_l_active_cases < 0 // trying to not model recoveries


//------------------testing regime changes

// grab each date of any testing regime change
preserve
	collapse (min) t, by(testing_regime)
	sort t //should already be sorted but just in case
	drop if _n==1 //dropping 1st testing regime of sample (no change to control for)
	levelsof t, local(testing_change_dates)
restore

// create a dummy for each testing regime change date
foreach t_chg of local testing_change_dates{
	local t_str = string(`t_chg', "%td")
	gen testing_regime_change_`t_str' = t==`t_chg'
	
	local t_lbl = string(`t_chg', "%tdMon_DD,_YYYY")
	lab var testing_regime_change_`t_str' "Testing regime change on `t_lbl'"
}

//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_active_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if longest_series==0 & e(sample) == 1

reg D_l_active_cases i.t
predict day_avg if longest_series==1 & e(sample) == 1
lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_active_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------disaggregated model

// note all schools are closed for the entire sample period
// event_cancel policies are enacted for entire sample as well

tab adm1_name t if D.no_demonstration==1
tab active_cases adm1_name if D.no_demonstration==1
*br if inlist(adm1_name, "Seoul", "Incheon")
// no_demonstration happened in Seoul on 2/21 (only 15 active cases)
// and Incheon on 2/24 (<10 cumulative confirmed cases so not in sample)


reghdfe D_l_active_cases testing_regime_change_* ///
religious_closure no_demonstration social_distance_opt welfare_services_closure work_from_home_opt ///
business_closure_opt emergency_declaration no_gathering_opt pos_cases_quarantine ///
, absorb(i.adm1_id i.dow, savefe) cluster(t) resid


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// predicting counterfactual growth for each obs
predictnl y_counter = ///
testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
testing_regime_change_29feb2020 * _b[testing_regime_change_29feb2020] + ///
testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of all policies combined (FOR FIG2)
lincom welfare_services_closure + business_closure_opt + work_from_home_opt + ///
no_demonstration + religious_closure + social_distance_opt + emergency_declaration + ///
no_gathering_opt + pos_cases_quarantine

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to FIG2)
coefplot, keep(religious_closure no_demonstration social_distance_opt welfare_services_closure work_from_home_opt ///
business_closure_opt emergency_declaration no_gathering_opt pos_cases_quarantine) ///
tit("KOR: indiv policies") subtitle("`subtitle2'") graphregion(margin(8 5 0 5)) ///
xline(0) name(KOR_disag, replace)


// compute ATE
preserve
	collapse (first) adm0_name (mean) D_l_active_cases ///
	religious_closure no_demonstration social_distance_opt welfare_services_closure work_from_home_opt ///
	business_closure_opt emergency_declaration no_gathering_opt pos_cases_quarantine if e(sample) == 1
	
	predictnl ATE = religious_closure * _b[religious_closure] + ///
	no_demonstration * _b[no_demonstration] + ///
	social_distance_opt * _b[social_distance_opt] + ///
	welfare_services_closure * _b[welfare_services_closure] + ///
	work_from_home_opt * _b[work_from_home_opt] + ///
	business_closure_opt * _b[business_closure_opt] + ///
	emergency_declaration * _b[emergency_declaration] + ///
	no_gathering_opt * _b[no_gathering_opt] + ///
	pos_cases_quarantine * _b[pos_cases_quarantine] ///
	if e(sample), ci(LB UB) se(sd) p(pval)
	
	outsheet * using "results/tables/ATE_disag/KOR_ATE_disag.csv", comma replace 
restore


// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual i.t
predict m_y_actual if longest_series==1

reg y_counter i.t
predict m_y_counter if longest_series==1


// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10

// Graph of predicted growth rates (FOR FIG3)

// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title("South Korea", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving("results/figures/appendix/disaggregated_policies/KOR_disag.gph", replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/ExtendedDataFigure6a_KOR_data.csv" if miss_ct<9 & e(sample), comma replace

// tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title("South Korea", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
// xscale(range(21960(10)22011)) xlabel(21960(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) 

