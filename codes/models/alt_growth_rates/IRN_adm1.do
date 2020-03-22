// IRN | adm1 

clear all
//-----------------------setup

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


//clean up
encode adm1_name, gen(adm1_id)

//set up panel
tsset adm1_id t, daily

//quality control
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 
drop if month == 2 & day <= 26 // DATA QUALITY CUTOFF DATE

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

// high_screening_regime in Qom, which transitioned on Mar 6
// assume rollout completed on Mar 13
gen testing_regime_mar13 = t==mdy(3,13,2020)


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons]
replace sample_avg = . if adm1_name ~= "Qom" & e(sample) == 1

reg D_l_cum_confirmed_cases i.t
predict day_avg if adm1_name  == "Qom" & e(sample) == 1
lab var day_avg "Observed avg. change in log cases"

tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

// NOTE: no_gathering has no variation

// Merging March 2-4 policies, since they all happend at the same time during 
// the break in the health data (only diff is Qom, which had school closures the whole time)

gen p_1 = (L3.school_closure + L3.travel_ban_local_opt + L3.work_from_home)/3
replace p_1 = 0 if p_1 == . & D_l_cum_confirmed_cases~=.
lab var p_1 "school_closure, travel_ban_optional, work_from_home"


// Merging March 13-14 policies, since the all happened at the same time except 
gen p_2 = home_isolation
lab var p_2 "home_isolation"


//Creating Tehran-specific treatments because policies have very different effect in Tehran than rest of country 
//(primarily an issue of timing, Tehran had a bigger effect for the earlier raft of policies compared to the rest of the country)
gen p_1_x_Tehran = p_1*(adm1_name== "Tehran")
gen p_2_x_Tehran = p_2*(adm1_name== "Tehran")


//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/IRN_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_1 p_2 p_1_x_Tehran p_2_x_Tehran testing_regime_mar13, absorb(i.adm1_id i.dow, savefe) cluster(date) resid

//saving coefs
tempfile results_file
postfile results str18 adm0 str50 policy str18 suffix beta se using `results_file', replace
foreach var in "p_1" "p_2"{
	post results ("IRN") ("`var'") ("`suffix'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2 //rest of country
post results ("IRN") ("comb. policy") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
lincom p_1 + p_2 + p_1_x_Tehran + p_2_x_Tehran //in Tehran
post results ("IRN") ("comb. policy Teheran") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

//looking at different policies (FOR FIG2)
coefplot, keep(p_1 p_2)


//------------- checking error structure (FOR APPENDIX FIGURE)

predict e if e(sample), resid

hist e, bin(30) tit(Iran) lcolor(white) fcolor(navy) xsize(5) name(hist_irn, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_irn, replace)

graph combine hist_irn qn_irn, rows(1) xsize(10) saving(figures/appendix/error_dist/error_irn.gph, replace)
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

//quality control: cannot have negative growth in cumulative cases
replace y_actual = 0 if y_actual < 0
replace y_counter = 0 if y_counter < 0

// fix lb_y_actual so there are no negative growth rates in error bars
gen lb_y_actual_pos = lb_y_actual 
replace lb_y_actual_pos = 0 if lb_y_actual<0 & lb_y_actual!=.

// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("IRN") ("no_policy rate") ("`suffix'") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

//export predicted counterfactual growth rate
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
predict m_y_actual if adm1_name=="Qom"

reg y_counter i.t
predict m_y_counter if adm1_name=="Qom"

postclose results

preserve
	use `results_file', clear
	outsheet * using "models/IRN_coefs`suffix'.csv", comma replace
restore

// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10


// Graph of predicted growth rates (FOR FIG3)

// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual_pos t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)21993)) xlabel(21930(10)21993, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(figures/fig3/raw/IRN_adm1_conf_cases_growth_rates_fixedx.gph, replace)
