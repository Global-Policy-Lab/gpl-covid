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
keep if t >= mdy(2,26,2020) // start date
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


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons] if longest_series==1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1
lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------disaggregated model

// combine optional policies with respective mandatory policies
// weighing optional policies by 1/2
gen social_distance_comb_popwt = social_distance_popwt + social_distance_opt_popwt * 0.5 
gen work_from_home_comb_popwt = work_from_home_popwt + work_from_home_opt_popwt * 0.5

gen travel_ban_local_transit_susp = (travel_ban_local_popwt + transit_suspension_popwt)/2 //need to combine bc collinear in time
gen soc_dist_work_from_home = (social_distance_comb_popwt + work_from_home_comb_popwt)/2 //need to combine bc collinear in time

reghdfe D_l_cum_confirmed_cases no_gathering_popwt soc_dist_work_from_home ///
school_closure_popwt travel_ban_local_transit_susp pos_cases_quarantine_popwt ///
business_closure_popwt home_isolation_popwt, absorb(i.adm2_id i.dow, savefe) cluster(t) resid


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// predicting counterfactual growth for each obs
predictnl y_counter = _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of package of policies (FOR FIG2)
lincom business_closure_popwt + no_gathering_popwt + ///
school_closure_popwt + soc_dist_work_from_home + travel_ban_local_transit_susp + ///
home_isolation_popwt + pos_cases_quarantine_popwt

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix lb_y_actual so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}
	
// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to Fig2)
coefplot, keep(no_gathering_popwt soc_dist_work_from_home ///
school_closure_popwt travel_ban_local_transit_susp pos_cases_quarantine_popwt ///
business_closure_popwt home_isolation_popwt) ///
tit("ITA: disaggregated policies") subtitle(`subtitle2') xline(0) name(ITA_disag, replace)


// compute ATE
preserve
	collapse (first) adm0_name (mean) D_l_cum_confirmed_cases ///
	no_gathering_popwt soc_dist_work_from_home ///
	school_closure_popwt travel_ban_local_transit_susp pos_cases_quarantine_popwt ///
	business_closure_popwt home_isolation_popwt if e(sample) == 1
	
	predictnl ATE = no_gathering_popwt * _b[no_gathering_popwt] + ///
	soc_dist_work_from_home * _b[soc_dist_work_from_home] + ///
	school_closure_popwt * _b[school_closure_popwt] + ///
	travel_ban_local_transit_susp * _b[travel_ban_local_transit_susp] + ///
	pos_cases_quarantine_popwt * _b[pos_cases_quarantine_popwt] + ///
	business_closure_popwt * _b[business_closure_popwt] + ///
	home_isolation_popwt * _b[home_isolation_popwt] ///
	if e(sample), ci(LB UB) se(sd) p(pval)
	
	outsheet * using "results/tables/ATE_disag/ITA_ATE_disag.csv", comma replace 
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
title(Italy, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/disaggregated_policies/ITA_disag.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/ExtendedDataFigure9a_ITA_data.csv" if miss_ct<9 & e(sample), comma replace

// tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title(Italy, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21970(10)22011)) xlabel(21970(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) 
// br if adm2_name=="Isernia"
