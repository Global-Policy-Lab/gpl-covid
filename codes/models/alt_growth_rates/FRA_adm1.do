// FRA | ADM1 

clear all
//-----------------------setup

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

//clean up
drop adm1
ren  adm1_name adm1
replace adm1 = "AuvergneRhoneAlpes" if adm1 == "AuvergneRhôneAlpes"

encode adm1, gen(adm1_id)

//set up panel
tsset adm1_id t, daily

// quality control
local suffix = "_imputed" // either "_imputed" for imputed time serie or "" for regular time serie 
drop if cum_confirmed_cases`suffix' < 10  

//construct dep vars
lab var cum_confirmed_cases`suffix' "cumulative confirmed cases"

gen l_cum_confirmed_cases`suffix' = log(cum_confirmed_cases`suffix')
lab var l_cum_confirmed_cases`suffix' "log(cum_confirmed_cases`suffix')"

gen D_l_cum_confirmed_cases`suffix' = D.l_cum_confirmed_cases`suffix' 
lab var D_l_cum_confirmed_cases`suffix' "change in log(cum_confirmed_cases`suffix')"

//quality control
replace D_l_cum_confirmed_cases`suffix' = . if D_l_cum_confirmed_cases`suffix' < 0 // cannot have negative changes in cumulative values
//0 negative changes for France

// check which admin unit has longest series
tab adm1 if cum_confirmed_cases!=., sort //use AuvergneRhoneAlpes


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases`suffix'
gen sample_avg = _b[_cons] if e(sample)
replace sample_avg = . if regexm(adm1, "^Auvergne") //issues with accents sometimes

reg D_l_cum_confirmed_cases`suffix' i.t
predict day_avg if regexm(adm1, "^Auvergne") & e(sample)
lab var day_avg "Observed avg. change in log cases"

tw (sc D_l_cum_confirmed_cases`suffix' t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------main estimates

// generate policy packages
g national_lockdown = (school_closure_national + business_closure + home_isolation) / 3 // big national lockdown policy
g national_no_gathering = (no_gathering_national_100 + no_gathering_national_1000) / 2 // national no gathering measure

// output data used for reg
outsheet using "models/reg_data/FRA_reg_data.csv", comma replace

// main regression model

reghdfe D_l_cum_confirmed_cases`suffix' national_lockdown event_cancel school_closure_regional ///
 social_distance national_no_gathering , absorb(i.adm1_id i.dow, savefe) cluster(t) resid

//saving coefs
tempfile results_file
postfile results str18 adm0 str18 policy str18 suffix beta se using `results_file', replace
foreach var in "event_cancel" "school_closure_regional" "social_distance" "national_no_gathering" "national_lockdown" {
	post results ("FRA") ("`var'") ("`suffix'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}


// effect of package of policies
lincom event_cancel + national_lockdown + school_closure_regional + social_distance + national_no_gathering
post results ("FRA") ("comb. policy") ("`suffix'") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

//looking at different policies
coefplot,  keep(national_lockdown national_no_gathering event_cancel school_closure_regional  social_distance) 


//------------- checking error structure (make fig for appendix)

predict e if e(sample), resid

hist e, bin(30) tit(France) lcolor(white) fcolor(navy) xsize(5) name(hist_fra, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_fra, replace)

graph combine hist_fra qn_fra, rows(1) xsize(10) saving(figures/appendix/error_dist/error_fra.gph, replace)
graph drop hist_fra qn_fra


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = event_cancel * _b[event_cancel] + school_closure_regional * _b[school_closure_regional] ///
+ social_distance * _b[social_distance]+ national_no_gathering*_b[national_no_gathering] ///
+ national_lockdown* _b[national_lockdown] + _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = event_cancel * _b[event_cancel] + school_closure_regional * _b[school_closure_regional] ///
+ social_distance * _b[social_distance]+ national_no_gathering*_b[national_no_gathering] ///
+ national_lockdown* _b[national_lockdown] ///
if e(sample)

// predicting counterfactual growth for each obs
predictnl y_counter =  _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// get ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases_imputed   event_cancel school_closure_regional social_distance national_no_gathering national_lockdown
	predictnl ATE = event_cancel * _b[event_cancel] + school_closure_regional * _b[school_closure_regional] ///
	+ social_distance * _b[social_distance]+ national_no_gathering*_b[national_no_gathering] ///
	+ national_lockdown* _b[national_lockdown], ci(LB UB) se(sd) p(pval)
	g adm0 = "FRA"
	outsheet * using "models/FRA_ATE.csv", comma replace 
restore

// quality control: cannot have negative growth in cumulative cases
replace y_actual = 0 if y_actual < 0
replace y_counter = 0 if y_counter < 0

// fix lb_y_actual so there are no negative growth rates in error bars
gen lb_y_actual_pos = lb_y_actual 
replace lb_y_actual_pos = 0 if lb_y_actual<0 & lb_y_actual!=.

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter
post results ("FRA") ("no_policy rate") ("`suffix'") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

//export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "FRA"
	outsheet * using "models/FRA_preds.csv", comma replace
restore

// the mean average growth rate suppression delivered by existing policy (FOR TEXT)
sum treatment

// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual i.t
predict m_y_actual if regexm(adm1, "^Auvergne") //issues with accents sometimes

reg y_counter i.t
predict m_y_counter if regexm(adm1, "^Auvergne") 

postclose results

// export counterfactual growthrate for diagnostic
preserve
	use `results_file', clear
	outsheet * using "models/FRA_coefs.csv", comma replace
restore

// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10

// fixed x-axis across countries
tw (rspike ub_y_actual lb_y_actual_pos t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(France, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)21993)) xlabel(21930(10)21993, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(figures/fig3/raw/FRA_adm1_conf_cases_growth_rates_fixedx.gph, replace)
