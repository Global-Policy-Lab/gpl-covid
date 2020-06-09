// USA | adm1
set matsize 5000
clear all
set scheme s1color
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// import state name to abbreviations crosswalk
insheet using data/raw/usa/state_name_abbrev_xwalk.csv, names clear
tempfile state_abb
save `state_abb'

// load data
insheet using data/processed/adm1/USA_processed.csv, clear 

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
	gen var_lbl = "Testing regime change on " + string(t, "%tdMon_DD,_YYYY") + " in " + adm1_abb
	levelsof var_lbl, local(test_var_lbl)
restore

// create a dummy for each testing regime change date w/in state
foreach lbl of local test_var_lbl{
	local t_lbl = substr("`lbl'", 26, 12)
	local t_chg = date("`t_lbl'", "MDY")
	local t_str = string(`t_chg', "%td")
	local adm1 = substr("`lbl'", -2, .)
	
	gen testing_regime_`t_str'_`adm1' = t==`t_chg' * D.testing_regime & adm1_abb=="`adm1'"
	lab var testing_regime_`t_str'_`adm1' "`lbl'"
}
*order testing_regime_*mar*, before(testing_regime_*apr*)


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if longest_series==0 & e(sample) == 1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1 & e(sample) == 1

lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

// popwt vars = policy intensity * population weight of respective admin 1 unit or sub admin 1 unit

gen p_1 = no_gathering_popwt
gen p_2 = social_distance_popwt 
gen p_3 = pos_cases_quarantine_popwt 
gen p_4 = paid_sick_leave_popwt
gen p_5 = work_from_home_popwt
gen p_6 = school_closure_popwt
gen p_7 = (travel_ban_local_popwt + transit_suspension_popwt) / 2 
gen p_8 = business_closure_popwt
gen p_9 = religious_closure_popwt
gen p_10 = home_isolation_popwt
gen p_11 = federal_guidelines

lab var p_1 "No gathering"
lab var p_2 "Social distance"
lab var p_3 "Quarantine positive cases" 
lab var p_4 "Paid sick leave"
lab var p_5 "Work from home"
lab var p_6 "School closure"
lab var p_7 "Travel ban"
lab var p_8 "Business closure"
lab var p_9 "Religious closure" 
lab var p_10 "Home isolation" 
lab var p_11 "Slow the Spread Guidelines" 


//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/USA_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_* testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
est store base

outreg2 using "results/tables/reg_results/USA_estimates_table", sideway noparen nodepvar word replace label ///
 title(United States, "Dependent variable: growth rate of cumulative confirmed cases (\u0916?log per day\'29") ///
 stats(coef se pval) dec(3) ctitle("Coefficient"; "Std Error"; "P-value") nocons nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" ///
 "This regression includes state fixed effects, day-of-week fixed effects, and clustered standard errors at the day level." "" ///
 "\'22Social distance\'22 includes policies such as closing libraries, maintaining 6 feet distance from others in public, and limiting visits to long term care facilities.")
cap erase "results/tables/reg_results/USA_estimates_table.txt"

// saving coef
tempfile results_file
postfile results str18 adm0 str18 policy beta se using `results_file', replace
foreach var of varlist p_*{
	post results ("USA") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

//------------- checking error structure (for APPENDIX FIGURE)

predict e if e(sample), resid

hist e, bin(30) tit("United States") lcolor(white) fcolor(navy) xsize(5) ///
ylabel(, angle(horizontal)) plotregion(lcolor(white)) name(hist_usa, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) ///
ylabel(, angle(horizontal)) plotregion(lcolor(white)) name(qn_usa, replace)

graph combine hist_usa qn_usa, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_usa.gph, replace)
graph drop hist_usa qn_usa

outsheet adm0_name e using "results/source_data/indiv/ExtendedDataFigure10_USA_e.csv" if e(sample), comma replace


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)

lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1 * _b[p_1] + ///
p_2 * _b[p_2] + ///
p_3 * _b[p_3] + /// 
p_4 * _b[p_4] + ///
p_5 * _b[p_5] + ///
p_6 * _b[p_6] + /// 
p_7 * _b[p_7] + ///
p_8 * _b[p_8] + ///
p_9 * _b[p_9] + /// 
p_10 * _b[p_10] + /// 
p_11 * _b[p_11] /// 
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter = ///
testing_regime_13mar2020_NY * _b[testing_regime_13mar2020_NY] + ///
testing_regime_16mar2020_CA * _b[testing_regime_16mar2020_CA] + ///
testing_regime_18mar2020_NC * _b[testing_regime_18mar2020_NC] + /// 
testing_regime_19mar2020_CT * _b[testing_regime_19mar2020_CT] + /// 
testing_regime_19mar2020_NV * _b[testing_regime_19mar2020_NV] + /// 
testing_regime_19mar2020_UT * _b[testing_regime_19mar2020_UT] + /// 
testing_regime_20mar2020_IA * _b[testing_regime_20mar2020_IA] + /// 
testing_regime_21mar2020_TN * _b[testing_regime_21mar2020_TN] + /// 
testing_regime_22mar2020_AL * _b[testing_regime_22mar2020_AL] + /// 
testing_regime_23mar2020_HI * _b[testing_regime_23mar2020_HI] + /// 
testing_regime_24mar2020_KS * _b[testing_regime_24mar2020_KS] + /// 
testing_regime_24mar2020_NJ * _b[testing_regime_24mar2020_NJ] + /// 
testing_regime_25mar2020_OH * _b[testing_regime_25mar2020_OH] + /// 
testing_regime_27mar2020_AZ * _b[testing_regime_27mar2020_AZ] + /// 
testing_regime_28mar2020_MD * _b[testing_regime_28mar2020_MD] + /// 
testing_regime_28mar2020_MO * _b[testing_regime_28mar2020_MO] + /// 
testing_regime_30mar2020_DE * _b[testing_regime_30mar2020_DE] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

 
// effect of package of policies (FOR FIG2)

// home_iso (p_10) implies no_gathering (p_1), work_from_home (p_5), business_closure (p_8)
// USA implies dictionary (gpl-covid/data/raw/usa/intensity_coding_rules.json):
//   "USA": {
//     "home_isolation.mandatory shelter in place":
//       [
//         "no_gathering.no_gathering",
//         "work_from_home.work from home",
//         "business_closure.all non-essentials"
//       ]
//   }
lincom p_10 + p_1 + p_5 + p_8
post results ("USA") ("home_iso_combined") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

nlcom (home_iso_combined: _b[p_10] + _b[p_1] + _b[p_5] + _b[p_8]), post
est store nlcom

// all policies
est restore base
lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6 + p_7 + p_8 + p_9 + p_10 + p_11
post results ("USA") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

//quality control: cannot have negative growth in cumulative cases
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("USA") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to FIG2)
// coefplot, keep(p_*) tit("USA: policy packages") subtitle(`subtitle2') ///
// graphregion(margin(10 5 0 5)) xline(0) name(USA_policy, replace)

coefplot (base, keep(p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9)) ///
(nlcom, keep(home_iso_combined)) (base, keep(p_11)), ///
tit("USA: policy packages") subtitle(`subtitle2') xline(0) legend(off) name(USA_policy, replace)

// export coefficients (FOR FIG2)
postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/indiv/Figure2_USA_coefs.csv", comma replace
restore

// export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "USA"
	outsheet * using "models/USA_preds.csv", comma replace
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
tw (rspike ub_counter lb_counter t_random2, lwidth(vvthin) color(red*.5)) ///
(rspike ub_y_actual lb_y_actual t_random,  lwidth(vvthin) color(blue*.5)) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title("United States", ring(0) position(11)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) ///
saving(results/figures/fig3/raw/USA_adm1_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_USA_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

// tw (rspike ub_counter lb_counter t_random2, lwidth(vvthin) color(red*.5)) ///
// (rspike ub_y_actual lb_y_actual t_random,  lwidth(vvthin) color(blue*.5)) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title("United States", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21977(10)22011)) xlabel(21977(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off)


//-------------------------------Cross-validation

tempvar counter_CV
tempfile results_file_crossV
postfile results str18 adm0 str18 sample str18 policy beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_cum_confirmed_cases testing_regime_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

foreach var of varlist p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_11{
	post results ("USA") ("full_sample") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

lincom  p_10 + p_1 + p_5 + p_8
post results ("USA") ("full_sample") ("p_10*") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6 + p_7 + p_8 + p_9 + p_10 + p_11
post results ("USA") ("full_sample") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

predictnl `counter_CV' =  ///
testing_regime_13mar2020_NY * _b[testing_regime_13mar2020_NY] + ///
testing_regime_16mar2020_CA * _b[testing_regime_16mar2020_CA] + ///
testing_regime_18mar2020_NC * _b[testing_regime_18mar2020_NC] + /// 
testing_regime_19mar2020_CT * _b[testing_regime_19mar2020_CT] + /// 
testing_regime_19mar2020_NV * _b[testing_regime_19mar2020_NV] + /// 
testing_regime_19mar2020_UT * _b[testing_regime_19mar2020_UT] + /// 
testing_regime_20mar2020_IA * _b[testing_regime_20mar2020_IA] + /// 
testing_regime_21mar2020_TN * _b[testing_regime_21mar2020_TN] + /// 
testing_regime_22mar2020_AL * _b[testing_regime_22mar2020_AL] + /// 
testing_regime_23mar2020_HI * _b[testing_regime_23mar2020_HI] + /// 
testing_regime_24mar2020_KS * _b[testing_regime_24mar2020_KS] + /// 
testing_regime_24mar2020_NJ * _b[testing_regime_24mar2020_NJ] + /// 
testing_regime_25mar2020_OH * _b[testing_regime_25mar2020_OH] + /// 
testing_regime_27mar2020_AZ * _b[testing_regime_27mar2020_AZ] + /// 
testing_regime_28mar2020_MD * _b[testing_regime_28mar2020_MD] + /// 
testing_regime_28mar2020_MO * _b[testing_regime_28mar2020_MO] + /// 
testing_regime_30mar2020_DE * _b[testing_regime_30mar2020_DE] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
sum `counter_CV'
post results ("USA") ("full_sample") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
drop `counter_CV'

*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_cum_confirmed_cases testing_regime_* p_* if adm1_name != "`adm'", absorb(i.adm1_id i.dow, savefe) cluster(t) resid


	foreach var of varlist p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_11{
		post results ("USA") ("`adm'") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	}

	lincom  p_10 + p_1 + p_5 + p_8
	post results ("USA") ("`adm'") ("p_10*") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
		
	
	lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6 + p_7 + p_8 + p_9 + p_10 + p_11
	post results ("USA") ("`adm'") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	predictnl `counter_CV' =  ///
	testing_regime_13mar2020_NY * _b[testing_regime_13mar2020_NY] + ///
	testing_regime_16mar2020_CA * _b[testing_regime_16mar2020_CA] + ///
	testing_regime_18mar2020_NC * _b[testing_regime_18mar2020_NC] + /// 
	testing_regime_19mar2020_CT * _b[testing_regime_19mar2020_CT] + /// 
	testing_regime_19mar2020_NV * _b[testing_regime_19mar2020_NV] + /// 
	testing_regime_19mar2020_UT * _b[testing_regime_19mar2020_UT] + /// 
	testing_regime_20mar2020_IA * _b[testing_regime_20mar2020_IA] + /// 
	testing_regime_21mar2020_TN * _b[testing_regime_21mar2020_TN] + /// 
	testing_regime_22mar2020_AL * _b[testing_regime_22mar2020_AL] + /// 
	testing_regime_23mar2020_HI * _b[testing_regime_23mar2020_HI] + /// 
	testing_regime_24mar2020_KS * _b[testing_regime_24mar2020_KS] + /// 
	testing_regime_24mar2020_NJ * _b[testing_regime_24mar2020_NJ] + /// 
	testing_regime_25mar2020_OH * _b[testing_regime_25mar2020_OH] + /// 
	testing_regime_27mar2020_AZ * _b[testing_regime_27mar2020_AZ] + /// 
	testing_regime_28mar2020_MD * _b[testing_regime_28mar2020_MD] + /// 
	testing_regime_28mar2020_MO * _b[testing_regime_28mar2020_MO] + /// 
	testing_regime_30mar2020_DE * _b[testing_regime_30mar2020_DE] + /// 
	_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
	sum `counter_CV'
	post results ("USA") ("`adm'") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
	drop `counter_CV'	
}
postclose results

preserve
	use `results_file_crossV', clear
	egen i = group(policy)
	outsheet * using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_USA.csv", comma replace
restore

//------------------------------------FIXED LAG 
set seed 1234
tempfile base_data
save `base_data'

reghdfe D_l_cum_confirmed_cases testing_regime_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid  
coefplot, keep(p_*) gen(L0_) title(main model) xline(0)
local r2 = e(r2)
lincom  p_10 + p_1 + p_5 + p_8
replace L0_b = r(estimate) if L0_at == 10
replace L0_ll1 = r(estimate) - 1.959964 * r(se) if L0_at == 10
replace L0_ul1 = r(estimate) + 1.959964 * r(se) if L0_at == 10

preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases  p_* 
	predictnl ATE = p_1*_b[p_1] + p_2*_b[p_2] + p_3*_b[p_3] + p_4*_b[p_4] + ///
	p_5*_b[p_5] + p_6*_b[p_6] + p_7*_b[p_7] + p_8*_b[p_8] + p_9*_b[p_9] ///
	+ p_10*_b[p_10] + p_11*_b[p_11], ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g lag = 0
	g r2 = `r2'
	tempfile f0
	save `f0'
restore	 


foreach lags of num 1 2 3 4 5{ 
	quietly {
	foreach var in p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11 {
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == . 
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag 
	
	
	reghdfe D_l_cum_confirmed_cases testing_regime_* p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	coefplot, keep(p_*) gen(L`lags'_) title (with fixed lag (4 days)) xline(0)
	local r2 = e(r2)
	lincom  p_10 + p_1 + p_5 + p_8
	replace L`lags'_b = r(estimate) if L`lags'_at == 10
	replace L`lags'_ll1 = r(estimate) - 1.959964 * r(se) if L`lags'_at == 10
	replace L`lags'_ul1 = r(estimate) + 1.959964 * r(se) if L`lags'_at == 10	
	
	preserve
		keep if e(sample) == 1
		collapse  D_l_cum_confirmed_cases  p_* 
		predictnl ATE = p_1*_b[p_1] + p_2*_b[p_2] + p_3*_b[p_3] + p_4*_b[p_4] + ///
		p_5*_b[p_5] + p_6*_b[p_6] + p_7*_b[p_7] + p_8*_b[p_8] + p_9*_b[p_9] ///
		+ p_10*_b[p_10] + p_11*_b[p_11], ci(LB UB) se(sd) p(pval)
		keep ATE LB UB sd pval 
		g lag = `lags'
		g r2 = `r2'
		tempfile f`lags'
		save `f`lags''
	restore		
	
	replace L`lags'_at = L`lags'_at - 0.1 *`lags'
	
	foreach var in p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11 {
		replace `var' = `var'_copy
		drop `var'_copy
	}
	
	}
}

// get r2
matrix rsq = J(16,3,0)
foreach lags of num 0/15{ 
	quietly {
	foreach var in p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag
	}
	if $BS != 0 {
		mat j = J($BS,1,0)
		forvalues i = 1/$BS {
		preserve
		bsample, cluster(adm1_id)
		qui reghdfe D_l_cum_confirmed_cases testing_regime_* p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11, absorb(i.adm1_id i.dow) 
		matrix j[`i',1] = e(r2)
		restore
		}
		
		preserve
			clear 
			svmat j
			collapse (mean) r2 = j1 (sd) sd = j1
			matrix rsq[`lags'+1,1] = r2[1]
			matrix rsq[`lags'+1,2] = sd[1]
			matrix rsq[`lags'+1,3] = `lags'
		restore
	}
	else {
		qui reghdfe D_l_cum_confirmed_cases testing_regime_* p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11, absorb(i.adm1_id i.dow) 	
		matrix rsq[`lags'+1,1] = e(r2)
		matrix rsq[`lags'+1,2] = .
		matrix rsq[`lags'+1,3] = `lags'	
	}
	
	foreach var in p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 p_10 p_11{
	qui replace `var' = `var'_copy
	qui drop `var'_copy
	}
}

preserve
clear
svmat rsq
rename (rsq1 rsq2 rsq3) (r2 se lag_length)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_r2_USA.csv", replace	
restore

drop if L0_b == .
keep *_at *_ll1 *_ul1 *_b
egen policy = seq()
reshape long L0_ L1_ L2_ L3_ L4_ L5_, i(policy) j(temp) string
rename *_ *
reshape long L, i(temp policy) j(val)
tostring policy, replace
replace policy = "No gathering" if policy == "1"
replace policy = "Social distance" if policy == "2"
replace policy = "Quarantine positive cases"  if policy == "3"
replace policy = "Paid sick leave" if policy == "4"
replace policy = "Work from home" if policy == "5"
replace policy = "School closure" if policy == "6"
replace policy = "Travel ban" if policy == "7"
replace policy = "Business closure" if policy == "8"
replace policy = "Religious closure" if policy == "9"
replace policy = "Home isolation" if policy == "10"
replace policy = "Mar 16 Federal guidelines" if policy == "11"

rename val lag
reshape wide L, i(lag policy) j(temp) string
sort Lat
rename (Lat Lb Lll1 Lul1) (position beta lower_CI upper_CI)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_fixed_lag_USA.csv", replace	

use `f0', clear
foreach L of num 1 2 3 4 5{
	append using `f`L''
}
g adm0 = "USA"
outsheet * using "models/USA_ATE.csv", comma replace 

use `base_data', clear
