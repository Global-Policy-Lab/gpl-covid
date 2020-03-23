// USA | adm1

clear all
//-----------------------setup

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

//clean up
drop if t <=21976 // begin sample on March 3, 2020

encode adm1, gen(adm1_id)
duplicates report adm1_id t

//set up panel
tsset adm1_id t, daily

//quality control
drop if cum_confirmed_cases < 10 

// very short panel of data
bysort adm1_id: egen total_obs = total((adm1_id~=.))
drop if total_obs < 4 // drop state if less than 4 obs

//construct dep vars
lab var cum_confirmed_cases "cumulative confirmed cases"

gen l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_cum_confirmed_cases "log(cum_confirmed_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases 
lab var D_l_cum_confirmed_cases "change in log(cum_confirmed_cases)"

//quality control
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 // cannot have negative changes in cumulative values

//--------------testing regime changes

gen testing_regime_change_mar13 = (t==21987) * D.testing_regime // only implmented in some states
gen testing_regime_change_mar20 = (t==21990) * D.testing_regime // only implemented in some states

//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if adm1_name ~= "Washington" & e(sample) == 1

reg D_l_cum_confirmed_cases i.t
predict day_avg if adm1_name  == "Washington" & e(sample) == 1

lab var day_avg "Observed avg. change in log cases"

tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

//paid_sick_leave_popw // not enough follow up data
//work_from_home_popw // not enough follow up data

capture: drop p_*
gen p_1 = (home_isolation_popw+ no_gathering_popw + social_distance_popw +.5*social_distance_opt_popwt) /3.5
gen p_2 = (school_closure_popw + .5*school_closure_opt_popwt)/1.5
gen p_3 = (travel_ban_local_popw + business_closure_popw )/2

//gen p_3 = (work_from_home_opt_popwt + social_distance_opt_popwt + school_closure_opt_popwt + business_closure_opt_popwt + home_isolation_opt_popwt + paid_sick_leave_opt_popwt)/6

lab var p_1 "social distancing"
lab var p_2 "close schools"
lab var p_3 "close business + travel ban"


//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/USA_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_* testing_regime_change_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

// export coef
tempfile results_file
postfile results str18 adm0 str18 policy str18 suffix beta se using `results_file', replace
foreach var in "p_1" "p_2" "p_3" {
	post results ("USA") ("`var'") ("`suffix'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2 + p_3 
post results ("USA") ("comb. policy") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 


//looking at different policies (similar to Fig2)
coefplot, keep(p_*)


//------------- checking error structure (merge these graphs for APPENDIX FIGURE)

predict e if e(sample), resid

hist e, bin(30) tit("United States") lcolor(white) fcolor(navy) xsize(5) name(hist_usa, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_usa, replace)

*graph combine hist_usa qn_usa, rows(1) xsize(10) saving(figures/appendix/error_dist/error_usa.gph, replace)
graph drop hist_usa qn_usa


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = ///
p_1*_b[p_1] + ///
p_2* _b[p_2] + ///
p_3* _b[p_3] /// 
+ _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)

lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1*_b[p_1] + ///
p_2* _b[p_2] + ///
p_3* _b[p_3] /// 
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter =  _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// compute ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases p_* 
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] + p_3*_b[p_3], ci(LB UB) se(sd) p(pval)
	g adm0 = "USA"
	outsheet * using "models/USA_ATE.csv", comma replace 
restore

//quality control: cannot have negative growth in cumulative cases
replace y_actual = 0 if y_actual < 0
replace y_counter = 0 if y_counter < 0

// fix so there are no negative growth rates in error bars
gen lb_y_actual_pos = lb_y_actual 
replace lb_y_actual_pos = 0 if lb_y_actual<0 & lb_y_actual!=.
gen lb_counter_pos = lb_counter 
replace lb_counter_pos = 0 if lb_counter<0 & lb_counter!=.


// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("USA") ("no_policy rate") ("`suffix'") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

//export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "USA"
	*outsheet * using "models/USA_preds.csv", comma replace
restore

// the mean average growth rate suppression delivered by existing policy (FOR TEXT)
sum treatment


// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual i.t
predict m_y_actual if adm1_name=="Washington"

reg y_counter i.t
predict m_y_counter if adm1_name=="Washington"

postclose results

preserve
	use `results_file', clear
	outsheet * using "models/USA_coefs`suffix'.csv", comma replace
restore

// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10

// Graph of predicted growth rates (FOR FIG3)
// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual_pos t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter_pos t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title("United States", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)21993)) xlabel(21930(10)21993, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(figures/fig3/raw/USA_adm1_conf_cases_growth_rates_fixedx.gph, replace)
