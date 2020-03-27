// CHN | ADM2

clear all
//-----------------------setup

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
drop if t > 21979 // cutoff date at end of sample to ensure we are not looking at effects of lifting policy
replace cum_confirmed_cases = . if t < 21930 	//data quality cutoff date (jan 16)
replace active_cases = . if t < 21930 			//data quality cutoff date (jan 16)
replace active_cases_imputed = . if t < 21930	//data quality cutoff date (jan 16)

capture: drop adm2_id
encode adm2_name, gen(adm2_id)
encode adm1_name, gen(adm1_id)
gen adm12_id = adm1_id*1000+adm2_id
lab var adm12_id "Unique city identifier"	// use this to identify cities, some have same names but different provinces
duplicates report adm12_id t

// set up panel
tsset adm12_id t, daily

// quality control
replace active_cases = . if cum_confirmed_cases < 10 
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 

// droping cities if they never reports when policies are implemented (e.g. could not find due to news censorship)
bysort adm12_id : egen ever_policy1 = max(home_isolation) 
bysort adm12_id : egen ever_policy2 = max(travel_ban_local) 
gen ever_policy = ever_policy1 + ever_policy2
keep if ever_policy > 0

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


//--------------testing regime changes

gen testing_regime_change_feb13 = (t== 21958)
gen testing_regime_change_feb20 = (t== 21965)


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_active_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if adm2_name ~= "Wuhan" & e(sample) == 1

reg D_l_active_cases i.t
predict day_avg if adm2_name  == "Wuhan" & e(sample) == 1
lab var day_avg "Observed avg change in log cases"

tw (sc D_l_active_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//--------------------gen treatment for home isolation with lags

gen home_isolation_L0_to_L7 = 0

forvalues i = 0/7 {
	replace home_isolation_L0_to_L7 = 1 if L`i'.D.home_isolation == 1
}

gen home_isolation_L8_to_L14 = 0
forvalues i = 8/14 {
	replace home_isolation_L8_to_L14 = 1 if L`i'.D.home_isolation == 1
}

gen home_isolation_L15_to_L21 = 0
forvalues i = 15/21 {
	replace home_isolation_L15_to_L21 = 1 if L`i'.D.home_isolation == 1
}

gen home_isolation_L22_to_L28 = 0
forvalues i = 22/28 {
	replace home_isolation_L22_to_L28 = 1 if L`i'.D.home_isolation == 1
}

gen home_isolation_L29_to_L70 = 0
forvalues i = 29/70 {
	replace home_isolation_L29_to_L70 = 1 if L`i'.D.home_isolation == 1
}

//--------------------gen treatment for travel ban with lags

gen travel_ban_local_L0_to_L7 = 0
forvalues i = 0/7 {
	replace travel_ban_local_L0_to_L7 = 1 if L`i'.D.travel_ban_local == 1
}

gen travel_ban_local_L8_to_L14 = 0
forvalues i = 8/14 {
	replace travel_ban_local_L8_to_L14 = 1 if L`i'.D.travel_ban_local == 1
}

gen travel_ban_local_L15_to_L21 = 0
forvalues i = 15/21 {
	replace travel_ban_local_L15_to_L21 = 1 if L`i'.D.travel_ban_local == 1
}

gen travel_ban_local_L22_to_L28 = 0
forvalues i = 22/28 {
	replace travel_ban_local_L22_to_L28 = 1 if L`i'.D.travel_ban_local == 1
}

gen travel_ban_local_L29_to_L70 = 0
forvalues i = 29/70 {
	replace travel_ban_local_L29_to_L70 = 1 if L`i'.D.travel_ban_local == 1
}


// -----------diagnostic: should be non-overlapping lags

gen x1 = home_isolation_L0_to_L7+ home_isolation_L8_to_L14 +home_isolation_L15_to_L21+ home_isolation_L22_to_L28+ home_isolation_L29_to_L70
gen x2 = travel_ban_local_L0_to_L7+ travel_ban_local_L8_to_L14 +travel_ban_local_L15_to_L21+ travel_ban_local_L22_to_L28+ travel_ban_local_L29_to_L70
tab t x1
tab t x2

//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/CHN_reg_data.csv", comma replace

// main regression model
reghdfe D_l_active_cases testing_regime_change_feb13 testing_regime_change_feb20 ///
home_isolation_*  travel_ban_local_*, absorb(i.adm12_id, savefe) cluster(t) resid

// export coef
tempfile results_file
postfile results str18 adm0 str50 policy str18 suffix beta se using `results_file', replace
foreach var in "home_isolation_L0_to_L7" "travel_ban_local_L0_to_L7" "home_isolation_L8_to_L14" ///
"travel_ban_local_L8_to_L14" "home_isolation_L15_to_L21" "travel_ban_local_L15_to_L21" ///
"home_isolation_L22_to_L28" "travel_ban_local_L22_to_L28" "home_isolation_L29_to_L70" ///
"travel_ban_local_L29_to_L70" {
	post results ("CHN") ("`var'") ("`suffix'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}


// effect of package of policies (FOR FIG2)
lincom home_isolation_L0_to_L7 + travel_ban_local_L0_to_L7 + home_isolation_L8_to_L14 ///
+ travel_ban_local_L8_to_L14 + home_isolation_L15_to_L21 + travel_ban_local_L15_to_L21 ///
+ home_isolation_L22_to_L28 + travel_ban_local_L22_to_L28 + home_isolation_L29_to_L70 ///
+ travel_ban_local_L29_to_L70
post results ("CHN") ("comb. policy") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

lincom home_isolation_L0_to_L7 + travel_ban_local_L0_to_L7 		// first week
post results ("CHN") ("first week (home+travel)") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L8_to_L14 + travel_ban_local_L8_to_L14 	// second week
post results ("CHN") ("second week (home+travel)") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L15_to_L21 + travel_ban_local_L15_to_L21 	// third week
post results ("CHN") ("third week (home+travel)") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L22_to_L28 + travel_ban_local_L22_to_L28 	// fourth week
post results ("CHN") ("fourth week (home+travel)") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom home_isolation_L29_to_L70 + travel_ban_local_L29_to_L70 	// fifth week and after
post results ("CHN") ("fifth week (home+travel)") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 


// looking at different policies (similar to Fig2)
coefplot, keep(home_isolation_* travel_ban_local_*)


//------------- checking error structure (make fig for appendix)

predict e if e(sample), resid

hist e, bin(30) tit(China) lcolor(white) fcolor(navy) xsize(5) name(hist_chn, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_chn, replace)

graph combine hist_chn qn_chn, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_chn.gph, replace)
graph drop hist_chn qn_chn


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = ///
home_isolation_L0_to_L7 *_b[home_isolation_L0_to_L7] + ///
travel_ban_local_L0_to_L7*_b[travel_ban_local_L0_to_L7] + ///
home_isolation_L8_to_L14*_b[home_isolation_L8_to_L14] +  ///
travel_ban_local_L8_to_L14*_b[travel_ban_local_L8_to_L14] + ///
home_isolation_L15_to_L21*_b[home_isolation_L15_to_L21] + ///
travel_ban_local_L15_to_L21*_b[travel_ban_local_L15_to_L21] + /// 
home_isolation_L22_to_L28*_b[home_isolation_L22_to_L28] + /// 
travel_ban_local_L22_to_L28*_b[travel_ban_local_L22_to_L28] + ///
home_isolation_L29_to_L70*_b[home_isolation_L29_to_L70] + ///
travel_ban_local_L29_to_L70*_b[travel_ban_local_L29_to_L70] ///
+ _b[_cons] + __hdfe1__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
home_isolation_L0_to_L7 *_b[home_isolation_L0_to_L7] + ///
travel_ban_local_L0_to_L7*_b[travel_ban_local_L0_to_L7] + ///
home_isolation_L8_to_L14*_b[home_isolation_L8_to_L14] +  ///
travel_ban_local_L8_to_L14*_b[travel_ban_local_L8_to_L14] + ///
home_isolation_L15_to_L21*_b[home_isolation_L15_to_L21] + ///
travel_ban_local_L15_to_L21*_b[travel_ban_local_L15_to_L21] + /// 
home_isolation_L22_to_L28*_b[home_isolation_L22_to_L28] + /// 
travel_ban_local_L22_to_L28*_b[travel_ban_local_L22_to_L28] + ///
home_isolation_L29_to_L70*_b[home_isolation_L29_to_L70] + ///
travel_ban_local_L29_to_L70*_b[travel_ban_local_L29_to_L70] ///
if e(sample)

// predicting counterfactual growth for each obs
predictnl y_counter =  _b[_cons] + __hdfe1__ if e(sample), ci(lb_counter ub_counter)

// compute ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_active_cases home_isolation_*  travel_ban_local_*
	predictnl ATE = home_isolation_L0_to_L7 *_b[home_isolation_L0_to_L7] + ///
	travel_ban_local_L0_to_L7*_b[travel_ban_local_L0_to_L7] + ///
	home_isolation_L8_to_L14*_b[home_isolation_L8_to_L14] +  ///
	travel_ban_local_L8_to_L14*_b[travel_ban_local_L8_to_L14] + ///
	home_isolation_L15_to_L21*_b[home_isolation_L15_to_L21] + ///
	travel_ban_local_L15_to_L21*_b[travel_ban_local_L15_to_L21] + /// 
	home_isolation_L22_to_L28*_b[home_isolation_L22_to_L28] + /// 
	travel_ban_local_L22_to_L28*_b[travel_ban_local_L22_to_L28] + ///
	home_isolation_L29_to_L70*_b[home_isolation_L29_to_L70] + ///
	travel_ban_local_L29_to_L70*_b[travel_ban_local_L29_to_L70], ci(LB UB) se(sd) p(pval)
	g adm0 = "CHN"
	outsheet * using "models/CHN_ATE.csv", comma replace 
restore


// quality control: don't want to be forecasting negative growth (not modeling recoveries)
replace y_actual = 0 if y_actual < 0
replace y_counter = 0 if y_counter < 0

// fix so there are no negative growth rates in error bars
foreach var of varlist lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("CHN") ("no_policy rate") ("`suffix'") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

// export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "CHN"
	outsheet * using "models/CHN_preds.csv", comma replace 
restore

// the mean average growth rate suppression delivered by existing policy (FOR TEXT)
sum treatment


// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual i.t
predict m_y_actual if adm2_name=="Wuhan"

reg y_counter i.t
predict m_y_counter if adm2_name=="Wuhan"

// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10


// Graph of predicted growth rates
// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(China, ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
xscale(range(21930(10)21993)) xlabel(21930(10)21993, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/CHN_adm2_active_cases_growth_rates_fixedx.gph, replace)

// for legend
tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, msize(tiny) lwidth(vthin) color(blue*.5)) ///
(connect m_y_counter t, msize(tiny) lwidth(vthin) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
tit(China) ytit(Growth rate of active confirmed cases) ///
legend(order(6 8 5 7 9) cols(1) ///
lab(6 "No policy (admin unit)") lab(8 "No policy (national avg)") ///
lab(5 "Actual with policies (admin unit)") lab(7 "Actual with policies (national avg)")  ///
region(lcolor(none))) scheme(s1color) ///
xscale(range(21930(6)21980)) xlabel(21930(6)21980, format(%tdMon_DD)) tmtick(##6) ///
yline(0, lcolor(black)) yscale(r(0(.2).8)) ylabel(0(.2).8)

graph export results/figures/fig3/raw/legend_fig3.pdf, replace


//-------------------------------Running the model for Wuhan only 

reghdfe D_l_active_cases testing_regime_change_* home_isolation_*  travel_ban_local_*  if adm2_name == "Wuhan", noabsorb

post results ("CHN_Wuhan") ("no_policy rate") ("`suffix'") (round(_b[_cons], 0.001)) (round(_se[_cons], 0.001)) 
postclose results

preserve
	use `results_file', clear
	outsheet * using "models/CHN_coefs`suffix'.csv", comma replace // for display (figure 2)
restore

// predicted "actual" outcomes with real policies
predictnl y_actual_wh = ///
home_isolation_L0_to_L7*_b[home_isolation_L0_to_L7] + ///
home_isolation_L8_to_L14*_b[home_isolation_L8_to_L14] +  ///
home_isolation_L15_to_L21*_b[home_isolation_L15_to_L21] + ///
home_isolation_L22_to_L28*_b[home_isolation_L22_to_L28] + /// 
home_isolation_L29_to_L70*_b[home_isolation_L29_to_L70] + ///
_b[_cons] if e(sample), ci(lb_y_actual_wh ub_y_actual_wh)

// predicting counterfactual growth for each obs
predictnl y_counter_wh =  _b[_cons] if e(sample), ci(lb_counter_wh ub_counter_wh)

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
tw (rspike ub_y_actual_wh lb_y_actual_wh t,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter_wh lb_counter_wh t, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual_wh t,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter_wh t, msize(tiny) color(red*.5)) ///
(connect y_actual_wh t, color(blue) m(square) lpattern(solid)) ///
(connect y_counter_wh t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg_wh t, color(black)) ///
if e(sample), ///
title("Wuhan, China", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") xtit("") ///
xscale(range(21930(10)21993)) xlabel(21930(10)21993, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/sub_natl_growth_rates/Wuhan_adm2_active_cases_growth_rates_fixedx.gph, replace)

