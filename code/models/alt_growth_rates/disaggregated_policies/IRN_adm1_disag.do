// IRN | adm1 

clear all
set scheme s1color
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/IRN_processed.csv, clear 

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

// clean up
encode adm1_name, gen(adm1_id)

// set up panel
tsset adm1_id t, daily

// quality control
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 
keep if t >= mdy(2,27,2020) // start date
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

//construct dep vars
lab var cum_confirmed_cases "cumulative confirmed cases"

gen l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_cum_confirmed_cases "log(cum_confirmed_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases 
lab var D_l_cum_confirmed_cases "change in log(cum_confirmed_cases)"


//quality control
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 // cannot have negative changes in cumulative values

// note: missing case data on 3/2/2020 and 3/3/2020
replace D_l_cum_confirmed_cases = . if t == 21976 | t == 21977 // dropping obs when no obs were reported
replace l_cum_confirmed_cases = . if t == 21976 | t == 21977 
replace cum_confirmed_cases = . if t == 21976 | t == 21977 


//------------------testing regime changes

// high_screening_regime in Qom/Gilan/Isfahan, which transitioned on Mar 6
// assume rollout completed on Mar 13 w rest of nation
gen testing_regime_13mar2020 = t==mdy(3,13,2020)
lab var testing_regime_13mar2020 "Testing regime change on Mar 13, 2020"


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

// create national opt travel ban var for all provinces except for Qom
// since Qom institutes opt travel ban on 2/20 before sample period
// and national opt travel ban enacted on 3/1
gen travel_ban_local_opt_natl = travel_ban_local_opt
	replace travel_ban_local_opt_natl = 0 if adm1_name=="Qom"

// create national school_closure var for provinces that close schools on 3/5
by adm1_id: egen school_closure_natl0 = min(school_closure) 
gen school_closure_natl = school_closure if school_closure_natl0==0
	replace school_closure_natl = 0 if school_closure_natl==.
drop school_closure_natl0


reghdfe D_l_cum_confirmed_cases testing_regime_* ///
travel_ban_local_opt_natl work_from_home school_closure_natl home_isolation ///
, absorb(i.adm1_id i.dow, savefe) cluster(date) resid


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// predicting counterfactual growth for each obs
predictnl y_counter = testing_regime_13mar2020 * _b[testing_regime_13mar2020] + ///
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of package of policies (FOR FIG2)
lincom travel_ban_local_opt_natl + work_from_home + school_closure_natl + home_isolation

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

// looking at different policies (FOR FIG2)
coefplot, keep(travel_ban_local_opt_natl work_from_home school_closure_natl home_isolation) ///
tit("IRN: indiv policies") subtitle("`subtitle2'") ///
xline(0) name(IRN_disag, replace)


// compute ATE
preserve
	collapse (first) adm0_name (mean) D_l_cum_confirmed_cases ///
	travel_ban_local_opt_natl work_from_home school_closure_natl home_isolation if e(sample) == 1
	
	predictnl ATE = travel_ban_local_opt_natl * _b[travel_ban_local_opt_natl] + ///
	work_from_home * _b[work_from_home] + ///
	school_closure_natl * _b[school_closure_natl] + ///
	home_isolation * _b[home_isolation] ///
	if e(sample), ci(LB UB) se(sd) p(pval)
	
	outsheet * using "results/tables/ATE_disag/IRN_ATE_disag.csv", comma replace 
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
tw (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
(rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) ///
saving(results/figures/appendix/disaggregated_policies/IRN_disag.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/ExtendedDataFigure6a_IRN_data.csv" if miss_ct<9 & e(sample), comma replace

// tw (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// (rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21970(10)22011)) xlabel(21970(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) 
