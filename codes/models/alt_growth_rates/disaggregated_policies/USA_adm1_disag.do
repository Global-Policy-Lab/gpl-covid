// USA | adm1

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// import state name to abbreviations crosswalk
insheet using data/raw/usa/state_name_abbrev_xwalk.csv, names clear
tempfile state_abb
save `state_abb'

// load data
insheet using data/processed/adm1/USA_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD",2020)
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

// clean up
keep if t >= mdy(3,3,2020) // start date
keep if t <= date("`end_sample'","YMD") // to match other country end dates

encode adm1, gen(adm1_id)
duplicates report adm1_id t

// set up panel
tsset adm1_id t, daily

// add state abbreviations
merge m:1 adm1_name using `state_abb', nogen

// quality control
drop if cum_confirmed_cases < 10 

// flag which admin unit has longest series
tab adm1_name if cum_confirmed_cases!=., sort 
bysort adm1_name: egen adm1_obs_ct = count(cum_confirmed_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name: egen adm1_max_cases = max(cum_confirmed_cases)
egen max_obs_ct = max(adm1_obs_ct)
bysort adm1_obs_ct: egen max_obs_ct_max_cases = max(adm1_max_cases) 

gen longest_series = adm1_obs_ct==max_obs_ct & adm1_max_cases==max_obs_ct_max_cases
drop adm1_obs_ct adm1_max_cases max_obs_ct max_obs_ct_max_cases

sort adm1_id t
tab adm1_name if longest_series==1 & cum_confirmed_cases!=.

// construct dep vars
lab var cum_confirmed_cases "cumulative confirmed cases"

gen l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_cum_confirmed_cases "log(cum_confirmed_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases 
lab var D_l_cum_confirmed_cases "change in log(cum_confirmed_cases)"

// quality control
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 // cannot have negative changes in cumulative values


//--------------testing regime changes

// testing regime changes at the state-level
*tab testing_regime, mi
*tab adm1_name t if testing_regime>0

// grab each date of any testing regime change by state
preserve
	collapse (min) t, by(testing_regime adm1_name adm1_abb)
	sort adm1_name t //should already be sorted but just in case
	by adm1_name: drop if _n==1 //dropping 1st testing regime of state sample (no change to control for)
	
	// create label for testing_regime_change vars
	// that notes the date and states for changes
	bysort t: egen adm1_ct = count(adm1_name)
	gen adm1_lbl = adm1_abb if adm1_ct<=5
	replace adm1_lbl = string(adm1_ct) + " states" if adm1_lbl==""
	
	contract t adm1_lbl
	bysort t: gen n = _n
	reshape wide adm1_lbl, i(t) j(n)
	egen adm1_lbl = concat(adm1_lbl*), punct(", ")
	replace adm1_lbl = regexr(adm1_lbl, ",? ?,? ?,$", "")
	
	gen var_lbl = "Testing regime change on " + string(t, "%tdMon_DD,_YYYY") + " in " + adm1_lbl
	levelsof var_lbl, local(test_var_lbl)
restore

// create a dummy for each testing regime change date w/in state
foreach lbl of local test_var_lbl{
	local t_lbl = substr("`lbl'", 26, 12)
	local t_chg = date("`t_lbl'", "MDY")
	local t_str = string(`t_chg', "%td")
	
	gen testing_regime_change_`t_str' = t==`t_chg' * D.testing_regime
	lab var testing_regime_change_`t_str' "`lbl'"
}
*order testing_regime_change_*mar*, before(testing_regime_change_*apr*)


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if longest_series==0 & e(sample) == 1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1 & e(sample) == 1

lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)

//------------------disaggregated model

// combine optional policies with respective mandatory policies
// weighing optional policies by 1/2
foreach var of varlist school_closure travel_ban_local business_closure social_distance home_isolation work_from_home pos_cases_quarantine no_gathering paid_sick_leave transit_suspension religious_closure{
	gen `var'_comb_popwt = `var'_popwt + `var'_opt_popwt * 0.5
}

reghdfe D_l_cum_confirmed_cases testing_regime_change_* ///
event_cancel_popwt no_gathering_comb_popwt social_distance_comb_popwt religious_closure_comb_popwt ///
pos_cases_quarantine_comb_popwt paid_sick_leave_comb_popwt work_from_home_comb_popwt ///
school_closure_comb_popwt travel_ban_local_comb_popwt transit_suspension_comb_popwt business_closure_comb_popwt home_isolation_comb_popwt, ///
absorb(i.adm1_id i.dow, savefe) cluster(t) resid

// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// predicting counterfactual growth for each obs
predictnl y_counter = ///
testing_regime_change_13mar2020 * _b[testing_regime_change_13mar2020] + ///
testing_regime_change_16mar2020 * _b[testing_regime_change_16mar2020] + ///
testing_regime_change_18mar2020 * _b[testing_regime_change_18mar2020] + /// 
testing_regime_change_19mar2020 * _b[testing_regime_change_19mar2020] + /// 
testing_regime_change_20mar2020 * _b[testing_regime_change_20mar2020] + /// 
testing_regime_change_21mar2020 * _b[testing_regime_change_21mar2020] + /// 
testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
testing_regime_change_23mar2020 * _b[testing_regime_change_23mar2020] + /// 
testing_regime_change_24mar2020 * _b[testing_regime_change_24mar2020] + /// 
testing_regime_change_25mar2020 * _b[testing_regime_change_25mar2020] + /// 
testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
testing_regime_change_28mar2020 * _b[testing_regime_change_28mar2020] + /// 
testing_regime_change_30mar2020 * _b[testing_regime_change_30mar2020] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of all policies combined (FOR FIG2)
lincom school_closure_comb_popwt + travel_ban_local_comb_popwt + business_closure_comb_popwt + ///
social_distance_comb_popwt + home_isolation_comb_popwt + work_from_home_comb_popwt + ///
pos_cases_quarantine_comb_popwt + no_gathering_comb_popwt + paid_sick_leave_comb_popwt + ///
religious_closure_comb_popwt + event_cancel_popwt + transit_suspension_comb_popwt

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

//quality control: cannot have negative growth in cumulative cases
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to FIG2)
coefplot, keep(*_popwt) ///
tit("USA: indiv policies") subtitle("`subtitle2'") graphregion(margin(0 5 0 5)) ///
caption("var_comb_popwt = var_popwt + var_opt_popwt*.5", span) ///
xline(0) name(USA_disag, replace)


// compute ATE
preserve
	collapse (first) adm0_name (mean) D_l_cum_confirmed_cases ///
	event_cancel_popwt no_gathering_comb_popwt social_distance_comb_popwt religious_closure_comb_popwt ///
	pos_cases_quarantine_comb_popwt paid_sick_leave_comb_popwt work_from_home_comb_popwt ///
	school_closure_comb_popwt travel_ban_local_comb_popwt transit_suspension_comb_popwt ///
	business_closure_comb_popwt home_isolation_comb_popwt if e(sample) == 1
	
	predictnl ATE = school_closure_comb_popwt * _b[school_closure_comb_popwt] + ///
	travel_ban_local_comb_popwt * _b[travel_ban_local_comb_popwt] + ///
	business_closure_comb_popwt * _b[business_closure_comb_popwt] + ///
	social_distance_comb_popwt * _b[social_distance_comb_popwt] + ///
	home_isolation_comb_popwt * _b[home_isolation_comb_popwt] + ///
	work_from_home_comb_popwt * _b[work_from_home_comb_popwt] + ///
	pos_cases_quarantine_comb_popwt * _b[pos_cases_quarantine_comb_popwt] + ///
	no_gathering_comb_popwt * _b[no_gathering_comb_popwt] + ///
	paid_sick_leave_comb_popwt * _b[paid_sick_leave_comb_popwt] + ///
	religious_closure_comb_popwt * _b[religious_closure_comb_popwt] + ///
	event_cancel_popwt * _b[event_cancel_popwt] + ///
	transit_suspension_comb_popwt * _b[transit_suspension_comb_popwt] ///
	if e(sample), ci(LB UB) se(sd) p(pval)
	
	outsheet * using "results/tables/ATE_disag/USA_ATE_disag.csv", comma replace 
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
tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title("United States", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/disaggregated_policies/USA_disag.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/ExtendedDataFigure9a_USA_data.csv" if miss_ct<9 & e(sample), comma replace

// tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title("United States", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21977(10)22011)) xlabel(21977(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0))
