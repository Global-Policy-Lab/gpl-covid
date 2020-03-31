// IRN | adm1 

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/IRN_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

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
drop if t <= mdy(2,26,2020) // DATA QUALITY CUTOFF DATE
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

replace D_l_cum_confirmed_cases = . if t == 21976 | t == 21977 // dropping obs when no obs were reported
replace l_cum_confirmed_cases = . if t == 21976 | t == 21977 
replace cum_confirmed_cases = . if t == 21976 | t == 21977 


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
}

// high_screening_regime in Qom, which transitioned on Mar 6
// assume rollout completed on Mar 13
drop testing_regime_change_06mar2020
gen testing_regime_13mar2020 = t==mdy(3,13,2020)

//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if longest_series==0 & e(sample) == 1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1 & e(sample) == 1
lab var day_avg "Observed avg. change in log cases"

tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

// NOTE: no_gathering has no variation

// Merging March 2-4 policies, since they all happened at the same time during 
// the break in the health data (only diff is Qom, which had school closures the whole time)

gen p_1 = (L3.school_closure + L3.travel_ban_local_opt + L3.work_from_home)/3
replace p_1 = 0 if p_1 == . & D_l_cum_confirmed_cases~=.
lab var p_1 "school_closure, travel_ban_optional, work_from_home"


// home isolation started March 13
gen p_2 = home_isolation
lab var p_2 "home_isolation"


// Creating Tehran-specific treatments because policies have very different effect in Tehran than rest of country 
//(primarily an issue of timing, Tehran had a bigger effect for the earlier raft of policies compared to the rest of the country)
gen p_1_x_Tehran = p_1*(adm1_name== "Tehran")
gen p_2_x_Tehran = p_2*(adm1_name== "Tehran")


//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/IRN_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_1 p_2 p_1_x_Tehran p_2_x_Tehran testing_regime_*, ///
absorb(i.adm1_id i.dow, savefe) cluster(date) resid

outreg2 using "results/tables/IRN_estimates_table", word replace label ///
 addtext(Province FE, "YES", Day-of-Week FE, "YES") title("Regression output: Iran")
cap erase "results/tables/IRN_estimates_table.txt"


// saving coefs
tempfile results_file
postfile results str18 adm0 str50 policy beta se using `results_file', replace
foreach var in "p_1" "p_2"{
	post results ("IRN") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2 //rest of country
post results ("IRN") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom p_1 + p_2 + p_1_x_Tehran + p_2_x_Tehran //in Tehran
post results ("IRN") ("comb. policy Tehran") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

// looking at different policies (FOR FIG2)
coefplot, keep(p_1 p_2)


//------------- checking error structure (FOR APPENDIX FIGURE)

predict e if e(sample), resid

hist e, bin(30) tit(Iran) lcolor(white) fcolor(navy) xsize(5) name(hist_irn, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_irn, replace)

graph combine hist_irn qn_irn, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_irn.gph, replace)
graph drop hist_irn qn_irn


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = p_1*_b[p_1] + p_2* _b[p_2] + p_1_x_Tehran*_b[p_1_x_Tehran] + p_2_x_Tehran*_b[p_2_x_Tehran] ///
+ _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1*_b[p_1] + ///
p_2* _b[p_2] + ///
p_1_x_Tehran*_b[p_1_x_Tehran] + ///
p_2_x_Tehran* _b[p_2_x_Tehran] ///
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter =  _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)
// ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases p_1 p_2 p_1_x_Tehran p_2_x_Tehran
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] + p_1_x_Tehran*_b[p_1_x_Tehran] ///
	+ p_2_x_Tehran*_b[p_2_x_Tehran], ci(LB UB) se(sd) p(pval)
	g adm0 = "IRN"
	outsheet * using "models/IRN_ATE.csv", comma replace 
restore

// quality control: cannot have negative growth in cumulative cases
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("IRN") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

// export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "IRN"
	outsheet * using "models/IRN_preds.csv", comma replace
restore

// the mean average growth rate suppression delivered by existing policy (FOR TEXT)
sum treatment

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
title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)21999)) xlabel(21930(10)21999, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/IRN_adm1_conf_cases_growth_rates_fixedx.gph, replace)


//-------------------------------Running the model for Tehran only 

reg D_l_cum_confirmed_cases p_1 p_2 testing_regime_* if adm1_name=="Tehran"
post results ("IRN_Tehran") ("no_policy rate") (round(_b[_cons], 0.001)) (round(_se[_cons], 0.001)) 

postclose results

preserve
	use `results_file', clear
	outsheet * using "models/IRN_coefs.csv", comma replace // for display (figure 2)
restore


// predicted "actual" outcomes with real policies
predictnl y_actual_thr = p_1*_b[p_1] + p_2* _b[p_2] + ///
_b[_cons] if e(sample), ci(lb_y_actual_thr ub_y_actual_thr)

// predicting counterfactual growth for each obs
predictnl y_counter_thr =  _b[_cons] if e(sample), ci(lb_counter_thr ub_counter_thr)

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual_thr y_counter_thr lb_y_actual_thr ub_y_actual_thr lb_counter_thr ub_counter_thr {
	replace `var' = 0 if `var'<0 & `var'!=.
}

// Observed avg change in log cases
reg D_l_cum_confirmed_cases i.t if adm1_name  == "Tehran"
predict day_avg_thr if adm1_name  == "Tehran" & e(sample) == 1

// Graph of predicted growth rates
// fixed x-axis across countries
tw (rspike ub_y_actual_thr lb_y_actual_thr t, lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter_thr lb_counter_thr t, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual_thr t, msize(tiny) color(blue*.5) ) ///
(scatter y_counter_thr t, msize(tiny) color(red*.5)) ///
(connect y_actual_thr t, color(blue) m(square) lpattern(solid)) ///
(connect y_counter_thr t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg_thr t, color(black)) ///
if e(sample), ///
title("Tehran, Iran", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") xtit("") ///
xscale(range(21930(10)21999)) xlabel(21930(10)21999, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/sub_natl_growth_rates/Tehran_conf_cases_growth_rates_fixedx.gph, replace)

