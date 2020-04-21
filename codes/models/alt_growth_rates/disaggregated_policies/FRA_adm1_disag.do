// FRA | ADM1 

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/FRA_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs
 
// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

// set up panel
xtset adm1_id t

// quality control
drop if cum_confirmed_cases < 10  
keep if t >= date("20200229","YMD") // Non stable growth before that point & missing data, only one region with +10 but no growth
keep if t <= date("`end_sample'","YMD") // to match other country end dates


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
lab var D_l_cum_confirmed_cases "change in log(cum. confirmed cases)"

gen l_cum_hospitalized = log(cum_hospitalized)
lab var l_cum_hospitalized "log(cum_hospitalized)"

gen D_l_cum_hospitalized = D.l_cum_hospitalized
lab var D_l_cum_hospitalized "change in log(cum_hospitalized)"


// quality control: cannot have negative changes in cumulative values
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 //0 negative changes for France


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons] if e(sample)
replace sample_avg = . if longest_series==1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1 & e(sample)
lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------testing regime changes

g testing_regime_15mar2020 = t == mdy(3,15,2020) // start of stade 3, none systematic testing
lab var testing_regime_15mar2020 "Testing regime change on Mar 15, 2020"


//------------------disaggregated model

// combine all no_gathering policies, which are just diff intensities
gen no_gathering_1000 = no_gathering_size <= 1000
gen no_gathering_100 = no_gathering_size <= 100
gen no_gathering_comb = (no_gathering_100 + no_gathering_1000 + no_gathering_inside) / 3

reghdfe D_l_cum_confirmed_cases event_cancel social_distance no_gathering_comb ///
school_closure business_closure home_isolation testing_regime_15mar2020, absorb(i.adm1_id i.dow, savefe) cluster(t) resid 


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// predicting counterfactual growth for each obs
predictnl y_counter =  testing_regime_15mar2020 * _b[testing_regime_15mar2020] + ///
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of all policies combined (FOR FIG2)
lincom event_cancel + social_distance + no_gathering_comb + school_closure + business_closure + home_isolation

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// quality control: cannot have negative growth in cumulative cases
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to FIG2)
coefplot, keep(event_cancel social_distance no_gathering_comb school_closure ///
business_closure home_isolation) ///
tit("FRA: disaggregated policies") subtitle("`subtitle2'") ///
xline(0) name(FRA_policy, replace) 


// compute ATE
preserve
	collapse (first) adm0_name (mean) D_l_cum_confirmed_cases ///
	event_cancel social_distance ///
	no_gathering_comb school_closure ///
	business_closure home_isolation if e(sample) == 1
	
	predictnl ATE = event_cancel * _b[event_cancel] + ///
	social_distance * _b[social_distance] + ///
	no_gathering_comb * _b[no_gathering_comb] + ///
	school_closure * _b[school_closure] + ///
	business_closure * _b[business_closure] + ///
	home_isolation * _b[home_isolation] ///
	if e(sample), ci(LB UB) se(sd) p(pval)
	
	outsheet * using "results/tables/ATE_disag/FRA_ATE_disag.csv", comma replace 
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
title(France, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/disaggregated_policies/FRA_disag.gph, replace)

// tw (rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title(France, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21970(10)22000)) xlabel(21970(10)22000, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0))


egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/ExtendedDataFigure6a_FRA_data.csv" if miss_ct<9 & e(sample), comma replace
