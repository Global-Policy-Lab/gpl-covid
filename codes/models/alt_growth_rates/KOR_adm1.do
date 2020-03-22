// KOR | ADM1

clear all
//-----------------------setup

//load data
insheet using data/processed/adm1/KOR_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

//clean up
drop if t <= 21961 // start 2/17/2020
capture: drop adm2_id
encode adm1_name, gen(adm1_id)
duplicates report adm1_id t

//set up panel
tsset adm1_id t, daily

//quality control
replace active_cases = . if cum_confirmed_cases < 10 
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 

//construct dep vars
lab var active_cases "active cases"

gen l_active_cases = log(active_cases)
lab var l_active_cases "log(active_cases)"

g l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_active_cases "log(cum_confirmed_cases)"

gen D_l_active_cases = D.l_active_cases 
lab var D_l_active_cases "change in log(active_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases
lab var D_l_active_cases "change in log(cum_confirmed_cases)"

//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT

// this causes a smooth transition to avoid having negative transmissions, corrects for recoveries and deaths when the log approximation is not very good
gen transmissionrate = D.cum_confirmed_cases/L.active_cases 
gen D_l_active_cases_raw = D_l_active_cases 
lab var D_l_active_cases_raw "change in log active cases (no recovery adjustment)"
replace D_l_active_cases = transmissionrate if D_l_active_cases_raw < 0.04

//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT: END

//quality control
replace D_l_active_cases = . if D_l_active_cases < 0 // trying to not model recoveries
gen testing_regime_change_feb29 = (t==21974) // change in testing regime

//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_active_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if adm1_name ~= "Seoul" & e(sample) == 1

reg D_l_active_cases i.t
predict day_avg if adm1_name  == "Seoul" & e(sample) == 1
lab var day_avg "Observed avg. change in log cases"

tw (sc D_l_active_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

gen p_1 = (business_closure + work_from_home_opt)/2
gen p_2 = (no_demonstration + religious_closure )/2
gen p_3 = social_distance_opt
gen p_4 = emergency_declaration 

lab var p_1 "closure, stay home"
lab var p_2 "no groups"
lab var p_3 "social distance"
lab var p_4 "emergency declaration"


//------------------main estimates

// output data used for reg
*outsheet using "models/reg_data/KOR_reg_data.csv", comma replace

// main regression model
reghdfe D_l_active_cases`suffix' testing_regime_change_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

// export coef
tempfile results_file
postfile results str18 adm0 str18 policy str18 suffix beta se using `results_file', replace
foreach var in "p_1" "p_2" "p_3" "p_4" {
	post results ("KOR") ("`var'") ("`suffix'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2 + p_3 // without emergency declaration, which was only in one prov
lincom p_1 + p_2 + p_3 + p_4
post results ("KOR") ("comb. policy") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

//looking at different policies (similar to Fig2)
coefplot, keep(p_*)


//------------- checking error structure (make fig for appendix)

predict e if e(sample), resid

hist e, bin(30) tit(South Korea) lcolor(white) fcolor(navy) xsize(5) name(hist_kor, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_kor, replace)

graph combine hist_kor qn_kor, rows(1) xsize(10) saving(figures/appendix/error_dist/error_kor.gph, replace)
graph drop hist_kor qn_kor


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = ///
p_1*_b[p_1] + ///
p_2* _b[p_2] + ///
p_3* _b[p_3] + /// 
p_4* _b[p_4] /// 
 + _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1*_b[p_1] + ///
p_2* _b[p_2] + ///
p_3* _b[p_3] + /// 
p_4* _b[p_4] /// 
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter =  _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// compute ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_active_cases`suffix' p_* 
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] + p_3*_b[p_3] + p_4*_b[p_4], ci(LB UB) se(sd) p(pval)
	g adm0 = "KOR"
	outsheet * using "models/KOR_ATE.csv", comma replace 
restore


//quality control: don't want to be forecasting negative growth (not modeling recoveries)
replace y_actual = 0 if y_actual < 0
replace y_counter = 0 if y_counter < 0

// fix so there are no negative growth rates in error bars
gen lb_y_actual_pos = lb_y_actual 
replace lb_y_actual_pos = 0 if lb_y_actual<0 & lb_y_actual!=.
gen ub_y_actual_pos = ub_y_actual 
replace ub_y_actual_pos = 0 if ub_y_actual<0 & ub_y_actual!=.


// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("KOR") ("no_policy rate") ("`suffix'") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

//export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "KOR"
	outsheet * using "models/KOR_preds.csv", comma replace
restore

// the mean average growth rate suppression delivered by existing policy (FOR TEXT)
sum treatment

// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual i.t
predict m_y_actual if adm1_name=="Seoul"

reg y_counter i.t
predict m_y_counter if adm1_name=="Seoul"


postclose results
preserve
	use `results_file', clear
	outsheet * using "models/KOR_coefs`suffix'.csv", comma replace //coefficients for display (fig2)
restore

// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10

// Graph of predicted growth rates (FOR FIG3)

// fixed x-axis across countries
tw (rspike ub_y_actual_pos lb_y_actual_pos t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title("South Korea", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
xscale(range(21930(10)21993)) xlabel(21930(10)21993, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(figures/fig3/raw/KOR_adm1_active_cases_growth_rates_fixedx.gph, replace)
