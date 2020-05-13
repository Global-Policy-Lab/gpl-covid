// CHN | ADM2

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag=="CHN_analysis"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm2/CHN_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)


// clean up
replace cum_confirmed_cases = . if t < mdy(1,16,2020) 	//data quality cutoff date
replace active_cases = . if t < mdy(1,16,2020) 			//data quality cutoff date
replace active_cases_imputed = . if t < mdy(1,16,2020)	//data quality cutoff date

// cutoff date to ensure we are not looking at effects of lifting policy
keep if t <= date("`end_sample'","YMD")

// use this to identify cities, some have same names but different provinces
capture: drop adm2_id
encode adm2_name, gen(adm2_id)
encode adm1_name, gen(adm1_id)
gen adm12_id = adm1_id*1000+adm2_id
lab var adm12_id "Unique city identifier"
duplicates report adm12_id t

// set up panel
tsset adm12_id t, daily

// drop obs in two cities that lifted local travel ban before 3/5
tab adm2_name t if D.travel_ban_local==-1
bysort adm12_id: egen travel_ban_local_lift = min(t) if D.travel_ban_local==-1
bysort adm12_id: egen travel_ban_local_lift_cut = min(travel_ban_local_lift)

drop if travel_ban_local_lift_cut!=. & t>=travel_ban_local_lift_cut
drop travel_ban_local_lift travel_ban_local_lift_cut

// quality control
replace active_cases = . if cum_confirmed_cases < 10 
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 

// drop cities if they never report when policies are implemented (e.g. could not find due to news censorship)
bysort adm12_id : egen ever_policy1 = max(home_isolation) 
bysort adm12_id : egen ever_policy2 = max(travel_ban_local) 
bysort adm12_id : egen ever_policy3 = max(emergency_declaration) 
// gen ever_policy = ever_policy1 + ever_policy2 + ever_policy3
// br if ever_policy==0 //Macau but no cases
gen ever_policy = ever_policy1 + ever_policy2 // only keeping 116 cities where we find at least one of travel ban or home iso b/c unlikely that the rest of cities did not implement
keep if ever_policy > 0

// flag which admin unit has longest series
gen adm1_adm2_name = adm2_name + ", " + adm1_name
tab adm1_adm2_name if active_cases!=., sort 
bysort adm1_name adm2_name: egen adm2_obs_ct = count(active_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name adm2_name: egen adm2_max_cases = max(active_cases)
egen max_obs_ct = max(adm2_obs_ct)
bysort adm2_obs_ct: egen max_obs_ct_max_cases = max(adm2_max_cases) 

gen longest_series = adm2_obs_ct==max_obs_ct & adm2_max_cases==max_obs_ct_max_cases
drop adm2_obs_ct adm2_max_cases max_obs_ct max_obs_ct_max_cases

sort adm12_id t
tab adm1_adm2_name if longest_series==1 & active_cases!=. //Wuhan


// construct dep vars
lab var active_cases "active cases"

gen l_active_cases = log(active_cases)
lab var l_active_cases "log(active_cases)"

gen D_l_active_cases = D.l_active_cases 
lab var D_l_active_cases "change in log(active_cases)"


//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT

// this causes a smooth transition to avoid having negative transmissions, corrects for recoveries and deaths when the log approximation is very good
gen transmissionrate = D.cum_confirmed_cases/L.active_cases 
gen D_l_active_cases_raw = D_l_active_cases 
lab var D_l_active_cases_raw "change in log active cases (no recovery adjustment)"
replace D_l_active_cases = transmissionrate if D_l_active_cases_raw < 0.04

//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT: END

//quality control
replace D_l_active_cases = . if D_l_active_cases > 1.5  // quality control
replace D_l_active_cases = . if D_l_active_cases < 0  // trying to not model recoveries
replace D_l_active_cases = . if D_l_active_cases == 0 & month == 1 // period of no case growth, not part of this analysis
	// only for January b/c later dates represent end of pandemic in CHN so 0 growth rates is likely true


//--------------testing regime changes

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
lab var day_avg "Observed avg change in log cases"

tw (sc D_l_active_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//--------------------gen treatment with lags

foreach var of varlist home_isolation travel_ban_local emergency_declaration{

	gen `var'_L0_to_L7 = 0
	forvalues i = 0/7 {
		replace `var'_L0_to_L7 = 1 if L`i'.D.`var' == 1
	}

	gen `var'_L8_to_L14 = 0
	forvalues i = 8/14 {
		replace `var'_L8_to_L14 = 1 if L`i'.D.`var' == 1
	}

	gen `var'_L15_to_L21 = 0
	forvalues i = 15/21 {
		replace `var'_L15_to_L21 = 1 if L`i'.D.`var' == 1
	}

	gen `var'_L22_to_L28 = 0
	forvalues i = 22/28 {
		replace `var'_L22_to_L28 = 1 if L`i'.D.`var' == 1
	}

	gen `var'_L29_to_L70 = 0
	forvalues i = 29/70 {
		replace `var'_L29_to_L70 = 1 if L`i'.D.`var' == 1
	}
	display "`var'"
	local var_prop = strupper(substr("`var'", 1, 1)) + substr("`var'", 2, .) //capitalize first letter only
	local lbl0 = subinstr("`var_prop'", "_", " ", .)
	local lbl = regexr("`lbl0'", " local", "")
	
	lab var `var'_L0_to_L7 "`lbl', Week 1"
	lab var `var'_L8_to_L14 "`lbl', Week 2"
	lab var `var'_L15_to_L21 "`lbl', Week 3"
	lab var `var'_L22_to_L28 "`lbl', Week 4"
	lab var `var'_L29_to_L70 "`lbl', Week 5"
}

// check that lags are not overlapping
egen x1 = rowtotal(home_isolation_L*)
egen x2 = rowtotal(travel_ban_local_L*)
egen x3 = rowtotal(emergency_declaration_L*)

tab t x1
tab t x2
tab t x3
drop x1 x2 x3

//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/CHN_reg_data.csv", comma replace

// main regression model
reghdfe D_l_active_cases emergency_declaration_L* travel_ban_local_L* home_isolation_L* testing_regime_change_* , absorb(i.adm12_id, savefe) cluster(t) resid
est store base
local r2 = e(r2)
outreg2 using "results/tables/reg_results/CHN_estimates_table", sideway noparen nodepvar word replace label ///
 title(China, "Dependent variable: growth rate of active cases (\u0916?log cases per day\'29") ///
 stats(coef se pval) dec(3) ctitle("Coefficient"; "Std Error"; "P-value") nocons nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" ///
 "This regression includes city fixed effects and clustered standard errors at the day level.")
cap erase "results/tables/reg_results/CHN_estimates_table.txt"

// saving coef
tempfile results_file
postfile results str18 adm0 str50 policy beta se using `results_file', replace
foreach var of varlist emergency_declaration_L* travel_ban_local_L* home_isolation_L* {
	post results ("CHN") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

//------------- checking error structure (make fig for appendix)

predict e if e(sample), resid

hist e, bin(30) tit(China) lcolor(white) fcolor(navy) xsize(5) name(hist_chn, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_chn, replace)

graph combine hist_chn qn_chn, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_chn.gph, replace)
graph drop hist_chn qn_chn

outsheet adm0_name e using "results/source_data/indiv/ExtendedDataFigure10_CHN_e.csv" if e(sample), comma replace


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = xb() + __hdfe1__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
home_isolation_L0_to_L7          * _b[home_isolation_L0_to_L7] + ///
travel_ban_local_L0_to_L7        * _b[travel_ban_local_L0_to_L7] + ///
emergency_declaration_L0_to_L7   * _b[emergency_declaration_L0_to_L7] + ///
home_isolation_L8_to_L14         * _b[home_isolation_L8_to_L14] +  ///
travel_ban_local_L8_to_L14       * _b[travel_ban_local_L8_to_L14] + ///
emergency_declaration_L8_to_L14  * _b[emergency_declaration_L8_to_L14] + ///
home_isolation_L15_to_L21        * _b[home_isolation_L15_to_L21] + ///
travel_ban_local_L15_to_L21      * _b[travel_ban_local_L15_to_L21] + /// 
emergency_declaration_L15_to_L21 * _b[emergency_declaration_L15_to_L21] + /// 
home_isolation_L22_to_L28        * _b[home_isolation_L22_to_L28] + /// 
travel_ban_local_L22_to_L28 	 * _b[travel_ban_local_L22_to_L28] + ///
emergency_declaration_L22_to_L28 * _b[emergency_declaration_L22_to_L28] + ///
home_isolation_L29_to_L70 		 * _b[home_isolation_L29_to_L70] + ///
travel_ban_local_L29_to_L70 	 * _b[travel_ban_local_L29_to_L70] + ///
emergency_declaration_L29_to_L70 * _b[emergency_declaration_L29_to_L70] ///
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter =  ///
testing_regime_change_18jan2020 * _b[testing_regime_change_18jan2020] + ///
testing_regime_change_28jan2020 * _b[testing_regime_change_28jan2020] + ///
testing_regime_change_06feb2020 * _b[testing_regime_change_06feb2020] + ///
testing_regime_change_13feb2020 * _b[testing_regime_change_13feb2020] + ///
testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
testing_regime_change_05mar2020 * _b[testing_regime_change_05mar2020] + ///
_b[_cons] + __hdfe1__ if e(sample), ci(lb_counter ub_counter)
    
// effect of package of policies (FOR FIG2)

// home_iso implies travel_ban_local
// CHN implies dictionary (gpl-covid/data/raw/multi_country/policy_implication_rules.json):
//  "CHN": [
//     [
//       "home_isolation", "=", 1,
//       [
//         ["travel_ban_local", 1]
//       ]
//     ]
//   ],
foreach lag in L0_to_L7 L8_to_L14 L15_to_L21 L22_to_L28 L29_to_L70{
	lincom home_isolation_`lag' + travel_ban_local_`lag' 
	post results ("CHN") ("home_iso_`lag' + trvl_ban_loc_`lag'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
}

nlcom (home_iso_trvl_ban_1: _b[home_isolation_L0_to_L7] + _b[travel_ban_local_L0_to_L7]) ///
      (home_iso_trvl_ban_2: _b[home_isolation_L8_to_L14] + _b[travel_ban_local_L8_to_L14]) ///
      (home_iso_trvl_ban_3: _b[home_isolation_L15_to_L21] + _b[travel_ban_local_L15_to_L21]) ///
	  (home_iso_trvl_ban_4: _b[home_isolation_L22_to_L28] + _b[travel_ban_local_L22_to_L28]) ///
	  (home_iso_trvl_ban_5: _b[home_isolation_L29_to_L70] + _b[travel_ban_local_L29_to_L70]) ///
      , post
est store nlcom
	
// all policies by week
est restore base
lincom home_isolation_L0_to_L7 + travel_ban_local_L0_to_L7 + emergency_declaration_L0_to_L7		    // first week
post results ("CHN") ("first week") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L8_to_L14 + travel_ban_local_L8_to_L14 + emergency_declaration_L8_to_L14	    // second week
post results ("CHN") ("second week") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L15_to_L21 + travel_ban_local_L15_to_L21 + emergency_declaration_L15_to_L21	// third week
post results ("CHN") ("third week") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L22_to_L28 + travel_ban_local_L22_to_L28 + emergency_declaration_L22_to_L28	// fourth week
post results ("CHN") ("fourth week") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L29_to_L70 + travel_ban_local_L29_to_L70 + emergency_declaration_L29_to_L70	// fifth week and after
post results ("CHN") ("fifth week and after") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Week 5+ = " + string(`comb_policy') // for coefplot

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("CHN") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to Fig2)
// coefplot, keep(emergency_declaration_L* travel_ban_local_L* home_isolation_L*) ///
// tit("CHN: policy packages") subtitle(`subtitle2') ///
// xline(0) name(CHN_policy, replace)

coefplot (base, keep(emergency_declaration_L* travel_ban_local_L*)) ///
(nlcom, keep(home_iso_trvl_ban_*)), tit("CHN: policy packages") ///
subtitle(`subtitle2') xline(0) name(CHN_policy, replace)
	

// export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "CHN"
	outsheet * using "models/CHN_preds.csv", comma replace 
restore

// compute ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_active_cases home_isolation_*  travel_ban_local_* emergency_declaration_*
	predictnl ATE = ///	
	home_isolation_L0_to_L7          * _b[home_isolation_L0_to_L7] + ///
	travel_ban_local_L0_to_L7        * _b[travel_ban_local_L0_to_L7] + ///
	emergency_declaration_L0_to_L7   * _b[emergency_declaration_L0_to_L7] + ///
	home_isolation_L8_to_L14         * _b[home_isolation_L8_to_L14] +  ///
	travel_ban_local_L8_to_L14       * _b[travel_ban_local_L8_to_L14] + ///
	emergency_declaration_L8_to_L14  * _b[emergency_declaration_L8_to_L14] + ///
	home_isolation_L15_to_L21        * _b[home_isolation_L15_to_L21] + ///
	travel_ban_local_L15_to_L21      * _b[travel_ban_local_L15_to_L21] + /// 
	emergency_declaration_L15_to_L21 * _b[emergency_declaration_L15_to_L21] + /// 
	home_isolation_L22_to_L28        * _b[home_isolation_L22_to_L28] + /// 
	travel_ban_local_L22_to_L28 	 * _b[travel_ban_local_L22_to_L28] + ///
	emergency_declaration_L22_to_L28 * _b[emergency_declaration_L22_to_L28] + ///
	home_isolation_L29_to_L70 		 * _b[home_isolation_L29_to_L70] + ///
	travel_ban_local_L29_to_L70 	 * _b[travel_ban_local_L29_to_L70] + ///
	emergency_declaration_L29_to_L70 * _b[emergency_declaration_L29_to_L70] ///
	, ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g r2 = `r2'
	tempfile ATE
	save `ATE'
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

// Graph of predicted growth rates

// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual t_random, lwidth(vvthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vvthin) color(red*.5)) ///
|| (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(China, ring(0) position(11)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/CHN_adm2_active_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_CHN_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

// for legend
set scheme s1color
tw (rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, msize(tiny) lwidth(vthin) color(blue*.5)) ///
(connect m_y_counter t, msize(tiny) lwidth(vthin) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
tit(China) ytit(Growth rate of active confirmed cases) ///
legend(order(6 8 5 7 9) cols(1) ///
lab(6 "No policy scenario admin unit") lab(8 "No policy scenario national avg") ///
lab(5 "Actual policies (predicted) admin unit") lab(7 "Actual policies (predicted) national avg") ///
lab(7 "Observed change in log cases national avg") ///
region(lcolor(none))) scheme(s1color) xlabel(, format(%tdMon_DD)) ///
yline(0, lcolor(black)) yscale(r(0(.2).8)) ylabel(0(.2).8) 
graph export results/figures/fig3/raw/legend_fig3.pdf, replace


//-------------------------------Running the model for Wuhan only 

// gen cases_to_pop = active_cases / population
// collapse (max) cases_to_pop active_cases, by(adm2_name)
// sort active_cases

reghdfe D_l_active_cases testing_regime_change_* emergency_declaration_* home_isolation_* travel_ban_local_* if adm2_name=="Wuhan", noabsorb

// export coefficients (FOR FIG2)
post results ("CHN_Wuhan") ("no_policy rate") (round(_b[_cons], 0.001)) (round(_se[_cons], 0.001)) 

postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/indiv/Figure2_CHN_coefs.csv", comma replace // for display (figure 2)
restore

// predicted "actual" outcomes with real policies
predictnl y_actual_wh = xb() if e(sample), ci(lb_y_actual_wh ub_y_actual_wh)

// predicting counterfactual growth for each obs
predictnl y_counter_wh =  ///
testing_regime_change_18jan2020 * _b[testing_regime_change_18jan2020] + ///
testing_regime_change_28jan2020 * _b[testing_regime_change_28jan2020] + ///
testing_regime_change_06feb2020 * _b[testing_regime_change_06feb2020] + ///
testing_regime_change_13feb2020 * _b[testing_regime_change_13feb2020] + ///
testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
testing_regime_change_05mar2020 * _b[testing_regime_change_05mar2020] + ///
_b[_cons] if e(sample), ci(lb_counter_wh ub_counter_wh)

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual_wh y_counter_wh lb_y_actual_wh ub_y_actual_wh lb_counter_wh ub_counter_wh {
	replace `var' = 0 if `var'<0 & `var'!=.
}

// Observed avg change in log cases
reg D_l_active_cases i.t if adm2_name  == "Wuhan"
predict day_avg_wh if adm2_name  == "Wuhan" & e(sample) == 1

// Graph of predicted growth rates
// fixed x-axis across countries
cap set scheme covid19_fig3 // optional scheme for graphs
tw (rspike ub_y_actual_wh lb_y_actual_wh t_random, lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter_wh lb_counter_wh t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual_wh t, msize(tiny) color(blue*.5) ) ///
(scatter y_counter_wh t, msize(tiny) color(red*.5)) ///
(connect y_actual_wh t, color(blue) m(square) lpattern(solid)) ///
(connect y_counter_wh t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg_wh t, color(black)) ///
if e(sample), ///
title("Wuhan, China", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") xtit("") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2)1.2)) ylabel(0(.2)1.2) plotregion(m(b=0)) ///
saving(results/figures/appendix/subnatl_growth_rates/Wuhan_active_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual_wh lb_y_actual_wh ub_y_actual_wh y_counter_wh lb_counter_wh ub_counter_wh day_avg_wh)
outsheet adm0_name adm1_name adm2_name t y_actual_wh lb_y_actual_wh ub_y_actual_wh y_counter_wh lb_counter_wh ub_counter_wh day_avg_wh ///
using "results/source_data/indiv/ExtendedDataFigure6b_Wuhan_data.csv" if miss_ct<7, comma replace
drop miss_ct


//-------------------------------EVENT STUDY

preserve 

gen D_home_isolation = D.home_isolation

//create a dummy variable if keeping in the event study
gen event_sample_home_isolation = 0

//identify observations that could potentially go into the event study sample (nearby enough to event and not contaminated by travel ban)
replace event_sample_home_isolation = 1 if D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if L1.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if L2.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if L3.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if L4.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0

replace event_sample_home_isolation = 1 if F1.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if F2.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if F3.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if F4.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0
replace event_sample_home_isolation = 1 if F5.D_home_isolation ==1 & D_l_active_cases ~=. & travel_ban_local == 0

//only keep a balanced panel (need 10 consecutive obs) for the event study (drop adm that have spotty coverage)
bysort adm12_id: egen event_count = total(event_sample_home_isolation)
tab event_count
tab date
keep if event_count == 10 & event_sample_home_isolation == 1
duplicates report  adm12_id 
//create dummy vars for the days relative to the event
xtset adm12 t
gen f1 = (F1.D_home_isolation ==1)
gen f2 = (F2.D_home_isolation ==1)
gen f3 = (F3.D_home_isolation ==1)
gen f4 = (F4.D_home_isolation ==1)
gen f5 = (F5.D_home_isolation ==1)

gen l0 = (D_home_isolation ==1)
gen l1 = (L1.D_home_isolation ==1)
gen l2 = (L2.D_home_isolation ==1)
gen l3 = (L3.D_home_isolation ==1)
gen l4 = (L4.D_home_isolation ==1)

//this is just a binary if pre-treatment
gen pre_treat = f5 + f4 + f3 +  f2 + f1

//computing the pre-treatment mean
sum D_l_active_cases if pre_treat == 1
loc pre_treat_val = r(mean)

//event study regression
reg D_l_active_cases f5 f4 f3 f2 f1 l0 l1 l2 l3 l4 testing_regime_change*, cluster(adm12_id) nocons
coefplot, vertical keep(f5 f4 f3 f2 f1 l0 l1 l2 l3 l4) yline(`pre_treat_val') tit(event study for 36 cities with unconfounded home isolation)
graph export results/figures/appendix/CHN_event_study.pdf, replace

//output source_data
tempfile results_file_evnt_stdy
postfile results str3 adm0 str3 lag beta se using `results_file_evnt_stdy', replace
foreach var in f5 f4 f3 f2 f1 l0 l1 l2 l3 l4 {
	post results ("CHN") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}
postclose results
use `results_file_evnt_stdy', clear
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_CHN_event_study.csv", comma replace

restore


//-------------------------------Cross-validation
tempvar counter_CV
tempfile results_file_crossV
postfile results str30 adm0 str30 sample str18 policy ite beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_active_cases testing_regime_change_* home_isolation_* travel_ban_local_*, absorb(i.adm12_id, savefe) cluster(t) resid

*weekly combined effect
lincom home_isolation_L0_to_L7 + travel_ban_local_L0_to_L7 		// first week
post results ("CHN") ("full_sample") ("first week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L8_to_L14 + travel_ban_local_L8_to_L14 	// second week
post results ("CHN") ("full_sample") ("second week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L15_to_L21 + travel_ban_local_L15_to_L21 	// third week
post results ("CHN") ("full_sample") ("third week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L22_to_L28 + travel_ban_local_L22_to_L28 	// fourth week
post results ("CHN") ("full_sample") ("fourth week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L29_to_L70 + travel_ban_local_L29_to_L70 	// fifth week and after
post results ("CHN") ("full_sample") ("fifth week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 


*no-policy growth rate
predictnl `counter_CV' =  ///
testing_regime_change_18jan2020 * _b[testing_regime_change_18jan2020] + ///
testing_regime_change_28jan2020 * _b[testing_regime_change_28jan2020] + ///
testing_regime_change_06feb2020 * _b[testing_regime_change_06feb2020] + ///
testing_regime_change_13feb2020 * _b[testing_regime_change_13feb2020] + ///
testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
testing_regime_change_05mar2020 * _b[testing_regime_change_05mar2020] + ///
_b[_cons] + __hdfe1__ if e(sample)
sum `counter_CV'
post results ("CHN") ("full_sample") ("no_policy rate") (0) (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
drop `counter_CV'

local i = 10
foreach var in "home_isolation_L0_to_L7" "home_isolation_L8_to_L14" ///
"home_isolation_L15_to_L21" "home_isolation_L22_to_L28"  "home_isolation_L29_to_L70" ///
"travel_ban_local_L0_to_L7" "travel_ban_local_L8_to_L14" "travel_ban_local_L15_to_L21" ///
"travel_ban_local_L22_to_L28" "travel_ban_local_L29_to_L70"{
	post results ("CHN") ("full_sample") ("`var'") (`i') (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	local i = `i' - 1
}

*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_active_cases testing_regime_change_* home_isolation_* travel_ban_local_* if adm1_name != "`adm'", absorb(i.adm12_id, savefe) cluster(t) resid
	local i = 10
	foreach var in "home_isolation_L0_to_L7" "home_isolation_L8_to_L14" ///
	"home_isolation_L15_to_L21" "home_isolation_L22_to_L28"  "home_isolation_L29_to_L70" ///
	"travel_ban_local_L0_to_L7" "travel_ban_local_L8_to_L14" "travel_ban_local_L15_to_L21" ///
	"travel_ban_local_L22_to_L28" "travel_ban_local_L29_to_L70"{
		post results ("CHN") ("`adm'") ("`var'") (`i') (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
		local i = `i' - 1
	} 

	lincom home_isolation_L0_to_L7 + travel_ban_local_L0_to_L7 		// first week
	post results ("CHN") ("`adm'") ("first week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	lincom home_isolation_L8_to_L14 + travel_ban_local_L8_to_L14 	// second week
	post results ("CHN") ("`adm'") ("second week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	lincom home_isolation_L15_to_L21 + travel_ban_local_L15_to_L21 	// third week
	post results ("CHN") ("`adm'") ("third week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	lincom home_isolation_L22_to_L28 + travel_ban_local_L22_to_L28 	// fourth week
	post results ("CHN") ("`adm'") ("fourth week (home+travel)") (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	lincom home_isolation_L29_to_L70 + travel_ban_local_L29_to_L70 	// fifth week and after
	post results ("CHN") ("`adm'") ("fifth week (home+travel)")  (0) (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	
	
	predictnl `counter_CV' =  ///
	testing_regime_change_18jan2020 * _b[testing_regime_change_18jan2020] + ///
	testing_regime_change_28jan2020 * _b[testing_regime_change_28jan2020] + ///
	testing_regime_change_06feb2020 * _b[testing_regime_change_06feb2020] + ///
	testing_regime_change_13feb2020 * _b[testing_regime_change_13feb2020] + ///
	testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
	testing_regime_change_05mar2020 * _b[testing_regime_change_05mar2020] + ///
	_b[_cons] + __hdfe1__ if e(sample)
	sum `counter_CV'
	post results ("CHN") ("`adm'") ("no_policy rate") (0) (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
	drop `counter_CV'	
	
}
postclose results

preserve
	set scheme s1color
	use `results_file_crossV', clear
	replace ite = ite + 1 if ite >= 6
	tw scatter ite beta if sample != "Hubei", xline(0,lc(black) lp(dash)) mc(black*.5)   ///
	|| scatter ite beta if sample == "full_sample", mc(red)  ///
	|| scatter ite beta if sample == "Hubei", mc(green) m(Oh) ///
	yscale(range(0.5(0.5)3.5)) ylabel( ///
	11 "Days 0-7" ///
	10 "Days 8-14" ///
	9 "home isolation         Days 15-21" ///
	8 "Days 22-28" ///
	7 "Days 29-70" ///
	5 "Days 0-7" ///
	4 "Days 8-14" ///
	3 "travel ban         Days 15-21" ///
	2 "Days 22-28" ///
	1 "Days 29-70",  angle(0)) ///
	xtitle("Estimated effect on daily growth rate", height(5)) ///
	legend(order(2 1 3) lab(2 "Full sample") lab(1 "Leaving one region out") ///
	lab(3 "w/o Hubei") region(lstyle(none)) rows(1)) ///
	ytitle("") xscale(range(-0.6(0.2)0.2)) xlabel(#5) xsize(7)
	graph export results/figures/appendix/cross_valid/CHN.pdf, replace
	capture graph export results/figures/appendix/cross_valid/CHN.png, replace	
	outsheet * using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_CHN.csv", comma replace
restore


//------------------------------------FIXED LAG 
tempfile base_data
save `base_data'

g p_1 = home_isolation
g p_2 = travel_ban_local

reghdfe D_l_active_cases testing_regime_change_* p_1 p_2, absorb(i.adm12_id, savefe) cluster(t) resid
local r2=e(r2)
preserve
	keep if e(sample) == 1
	collapse  D_l_active_cases  p_* 
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] , ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g lag = 0
	g r2 = `r2'
	tempfile f0
	save `f0'
restore	 
 
foreach lags of num 1 2 3 4 5{ 
	quietly {
	foreach var in p_1 p_2{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag 

	reghdfe D_l_active_cases p_1 p_2 testing_regime_*, absorb(i.adm12_id, savefe) cluster(t) resid
	local r2 = e(r2)
	preserve
		keep if e(sample) == 1
		collapse  D_l_active_cases  p_* 
		predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] , ci(LB UB) se(sd) p(pval)
		keep ATE LB UB sd pval 
		g lag = `lags'
		g r2 = `r2'
		tempfile f`lags'
		save `f`lags''
	restore	 
 	
		
	foreach var in p_1 p_2{
		replace `var' = `var'_copy
		drop `var'_copy
	}
	}
}

use `ATE' , clear
foreach L of num 0 1 2 3 4 5{
	append using `f`L''
}
g adm0 = "CHN"
outsheet * using "models/CHN_ATE.csv", comma replace 

use `base_data', clear
