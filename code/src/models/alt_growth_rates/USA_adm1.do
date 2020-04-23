// USA | adm1

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using code/src/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// import state name to abbreviations crosswalk
insheet using data/raw/usa/state_name_abbrev_xwalk.csv, names clear
tempfile state_abb
save `state_abb'

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
	bysort t: egen adm1_ct = count(adm1_name!= "")
	gen adm1_lbl = adm1_abb if adm1_ct<=5
	replace adm1_lbl = string(adm1_ct) + " states" if adm1_lbl==""
	
	contract t adm1_lbl
	bysort t: gen n = _n
	reshape wide adm1_lbl, i(t) j(n)
	egen adm1_lbl = concat(adm1_lbl*), punct(", ")
	replace adm1_lbl = regexr(adm1_lbl, ",? ?,? ?,$", "")
	
	gen var_lbl = "Testing regime change on " + string(t, "%tdMon_DD,_YYYY") + " in " + adm1_lbl
	levelsof var_lbl, local(test_var_lbl)
restore

// create a dummy for each testing regime change date w/in state
foreach lbl of local test_var_lbl{
	local t_lbl = substr("`lbl'", 26, 12)
	local t_chg = date("`t_lbl'", "MDY")
	local t_str = string(`t_chg', "%td")
	
	gen testing_regime_change_`t_str' = t==`t_chg' * D.testing_regime
	lab var testing_regime_change_`t_str' "`lbl'"
}
*order testing_regime_change_*mar*, before(testing_regime_change_*apr*)


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

// popwt vars = policy intensity * population weight of respective admin 2 unit or sub admin 2 unit

// emergency_declaration on for entire sample

// combine optional policies with respective mandatory policies
// weighing optional policies by 1/2
foreach var of varlist school_closure travel_ban_local business_closure social_distance home_isolation work_from_home pos_cases_quarantine no_gathering paid_sick_leave transit_suspension religious_closure{
	gen `var'_comb_popwt = `var'_popwt + `var'_opt_popwt * 0.5
}

gen p_1 = (event_cancel_popwt + no_gathering_comb_popwt) / 2
gen p_2 = (social_distance_comb_popwt + religious_closure_comb_popwt) / 2 //the 2 religious_closure policies happen on same day as social_distance policies in respective state
gen p_3 = pos_cases_quarantine_comb_popwt 
gen p_4 = paid_sick_leave_comb_popwt
gen p_5 = work_from_home_comb_popwt
gen p_6 = school_closure_comb_popwt
gen p_7 = (travel_ban_local_comb_popwt + transit_suspension_comb_popwt) / 2 
gen p_8 = business_closure_comb_popwt
gen p_9 = home_isolation_comb_popwt

lab var p_1 "No gathering, event cancel"
lab var p_2 "Social distance"
lab var p_3 "Quarantine positive cases" 
lab var p_4 "Paid sick leave"
lab var p_5 "Work from home"
lab var p_6 "School closure"
lab var p_7 "Travel ban"
lab var p_8 "Business closure"
lab var p_9 "Home isolation" 


//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/USA_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_* testing_regime_change_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

outreg2 using "results/tables/reg_results/USA_estimates_table", sideway noparen nodepvar word replace label ///
 addtext(State FE, "YES", Day-of-Week FE, "YES") title(United States, "Dependent variable: Growth rate of cumulative confirmed cases (\u0916?log per day\'29") ///
 ctitle("Coefficient"; "Robust Std. Error") nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" /// 
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

hist e, bin(30) tit("United States") lcolor(white) fcolor(navy) xsize(5) name(hist_usa, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_usa, replace)

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
p_9 * _b[p_9] /// 
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter = ///
testing_regime_change_13mar2020 * _b[testing_regime_change_13mar2020] + ///
testing_regime_change_16mar2020 * _b[testing_regime_change_16mar2020] + ///
testing_regime_change_18mar2020 * _b[testing_regime_change_18mar2020] + /// 
testing_regime_change_19mar2020 * _b[testing_regime_change_19mar2020] + /// 
testing_regime_change_20mar2020 * _b[testing_regime_change_20mar2020] + /// 
testing_regime_change_21mar2020 * _b[testing_regime_change_21mar2020] + /// 
testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
testing_regime_change_23mar2020 * _b[testing_regime_change_23mar2020] + /// 
testing_regime_change_24mar2020 * _b[testing_regime_change_24mar2020] + /// 
testing_regime_change_25mar2020 * _b[testing_regime_change_25mar2020] + /// 
testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
testing_regime_change_28mar2020 * _b[testing_regime_change_28mar2020] + /// 
testing_regime_change_30mar2020 * _b[testing_regime_change_30mar2020] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of all policies combined (FOR FIG2)
lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6 + p_7 + p_8 + p_9
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
coefplot, keep(p_*) tit("USA: policy packages") subtitle(`subtitle2') ///
graphregion(margin(10 5 0 5)) xline(0) name(USA_policy, replace)


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
tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title("United States", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/USA_adm1_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_USA_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

// tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title("United States", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21977(10)22011)) xlabel(21977(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0))


//-------------------------------Cross-validation
tempvar counter_CV
tempfile results_file_crossV
postfile results str18 adm0 str18 sample str18 policy beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_cum_confirmed_cases testing_regime_change_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

foreach var of varlist p_*{
	post results ("USA") ("full_sample") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}
lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6 + p_7 + p_8 + p_9
post results ("USA") ("full_sample") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

predictnl `counter_CV' =  ///
testing_regime_change_13mar2020 * _b[testing_regime_change_13mar2020] + ///
testing_regime_change_16mar2020 * _b[testing_regime_change_16mar2020] + ///
testing_regime_change_18mar2020 * _b[testing_regime_change_18mar2020] + /// 
testing_regime_change_19mar2020 * _b[testing_regime_change_19mar2020] + /// 
testing_regime_change_20mar2020 * _b[testing_regime_change_20mar2020] + /// 
testing_regime_change_21mar2020 * _b[testing_regime_change_21mar2020] + /// 
testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
testing_regime_change_23mar2020 * _b[testing_regime_change_23mar2020] + /// 
testing_regime_change_24mar2020 * _b[testing_regime_change_24mar2020] + /// 
testing_regime_change_25mar2020 * _b[testing_regime_change_25mar2020] + /// 
testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
testing_regime_change_28mar2020 * _b[testing_regime_change_28mar2020] + /// 
testing_regime_change_30mar2020 * _b[testing_regime_change_30mar2020] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
sum `counter_CV'
post results ("USA") ("full_sample") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
drop `counter_CV'

*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_cum_confirmed_cases testing_regime_change_* p_* if adm1_name != "`adm'", absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	foreach var of varlist p_*{
		post results ("USA") ("`adm'") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	}
	lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6 + p_7 + p_8 + p_9
	post results ("USA") ("`adm'") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	predictnl `counter_CV' =  ///
	testing_regime_change_13mar2020 * _b[testing_regime_change_13mar2020] + ///
	testing_regime_change_16mar2020 * _b[testing_regime_change_16mar2020] + ///
	testing_regime_change_18mar2020 * _b[testing_regime_change_18mar2020] + /// 
	testing_regime_change_19mar2020 * _b[testing_regime_change_19mar2020] + /// 
	testing_regime_change_20mar2020 * _b[testing_regime_change_20mar2020] + /// 
	testing_regime_change_21mar2020 * _b[testing_regime_change_21mar2020] + /// 
	testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
	testing_regime_change_23mar2020 * _b[testing_regime_change_23mar2020] + /// 
	testing_regime_change_24mar2020 * _b[testing_regime_change_24mar2020] + /// 
	testing_regime_change_25mar2020 * _b[testing_regime_change_25mar2020] + /// 
	testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
	testing_regime_change_28mar2020 * _b[testing_regime_change_28mar2020] + /// 
	testing_regime_change_30mar2020 * _b[testing_regime_change_30mar2020] + /// 
	_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
	sum `counter_CV'
	post results ("USA") ("`adm'") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
	drop `counter_CV'	
}
postclose results

preserve
	set scheme s1color
	use `results_file_crossV', clear
	egen i = group(policy)
	tw scatter i beta if sample != "New York", xline(0,lc(black) lp(dash)) mc(black*.5)   ///
	|| scatter i beta if sample == "full_sample", mc(red)  ///
	|| scatter i beta if sample == "New York", mc(green) m(Oh) ///
	yscale(range(0.5(0.5)3.5)) ylabel( ///
	1 "combined effect" ///
	2 "No gathering, event cancel" ///
	3 "Social distance" ///
	4 "Quarantine positive cases"  ///
	5 "Paid sick leave" ///
	6 "Work from home" ///
	7 "School closure" ///
	8 "Travel ban" ///
	9 "Business closure" ///
	10 "Home isolation",  angle(0)) ///
	xtitle("Estimated effect on daily growth rate", height(5)) ///
	legend(order(2 1 3) lab(2 "Full sample") lab(1 "Leaving one region out") ///
	lab(3 "w/o NY") region(lstyle(none))) ///
	ytitle("") xscale(range(-0.6(0.2)0.2)) xlabel(#5) xsize(7)
	graph export results/figures/appendix/cross_valid/USA.pdf, replace
	graph export results/figures/appendix/cross_valid/USA.png, replace	
	outsheet * using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_USA.csv", comma replace
restore

//------------------------------------FIXED LAG 

tempfile base_data
save `base_data'

reghdfe D_l_cum_confirmed_cases testing_regime_change_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid  
coefplot, keep(p_*) gen(L0_) title(main model) xline(0)
local r2 = e(r2)

preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases  p_* 
	predictnl ATE = p_1*_b[p_1] + p_2*_b[p_2] + p_3*_b[p_3] + p_4*_b[p_4] + ///
	p_5*_b[p_5] + p_6*_b[p_6] + p_7*_b[p_7] + p_8*_b[p_8] + p_9*_b[p_9], ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g lag = 0
	g r2 = `r2'
	tempfile f0
	save `f0'
restore	 


foreach lags of num 1 2 3 4 5{ 
	quietly {
	foreach var in p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 {
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == . 
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag 
	
	
	reghdfe D_l_cum_confirmed_cases testing_regime_change_* p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	coefplot, keep(p_*) gen(L`lags'_) title (with fixed lag (4 days)) xline(0)
	local r2 = e(r2)
	
	preserve
		keep if e(sample) == 1
		collapse  D_l_cum_confirmed_cases  p_* 
		predictnl ATE = p_1*_b[p_1] + p_2*_b[p_2] + p_3*_b[p_3] + p_4*_b[p_4] + ///
		p_5*_b[p_5] + p_6*_b[p_6] + p_7*_b[p_7] + p_8*_b[p_8] + p_9*_b[p_9], ci(LB UB) se(sd) p(pval)
		keep ATE LB UB sd pval 
		g lag = `lags'
		g r2 = `r2'
		tempfile f`lags'
		save `f`lags''
	restore		
	
	replace L`lags'_at = L`lags'_at - 0.1 *`lags'
	
	foreach var in p_1 p_2 p_3 p_4 p_5 p_6 p_7 p_8 p_9 {
		replace `var' = `var'_copy
		drop `var'_copy
	}
	
	}
}

set scheme s1color
tw rspike L0_ll1 L0_ul1 L0_at , hor xline(0) lc(black) lw(thin) ///
|| scatter  L0_at L0_b, mc(black) ///
|| rspike L1_ll1 L1_ul1 L1_at , hor xline(0) lc(black*.9) lw(thin) ///
|| scatter  L1_at L1_b, mc(black*.9) ///
|| rspike L2_ll1 L2_ul1 L2_at , hor xline(0) lc(black*.7) lw(thin) ///
|| scatter  L2_at L2_b, mc(black*.7) ///
|| rspike L3_ll1 L3_ul1 L3_at , hor xline(0) lc(black*.5) lw(thin) ///
|| scatter  L3_at L3_b, mc(black*.5) ///
|| rspike L4_ll1 L4_ul1 L4_at , hor xline(0) lc(black*.3) lw(thin) ///
|| scatter  L4_at L4_b, mc(black*.3) ///
|| rspike L5_ll1 L5_ul1 L5_at , hor xline(0) lc(black*.1) lw(thin) ///
|| scatter  L5_at L5_b, mc(black*.1) ///		
ylabel(1 "No gathering, event cancel" ///
2 "Social distance" ///
3 "Quarantine positive cases"  ///
4 "Paid sick leave" ///
5 "Work from home" ///
6 "School closure" ///
7 "Travel ban" ///
8 "Business closure"  ///
9 "Home isolation", angle(0)) ///
ytitle("") title("USA comparing Fixed Lags models") ///
legend(order(2 4 6 8 10 12) lab(2 "L0") lab(4 "L1") lab(6 "L2") lab(8 "L3") ///
lab(10 "L4") lab(12 "L5") rows(1) region(lstyle(none)))
graph export results/figures/appendix/fixed_lag/USA.pdf, replace
graph export results/figures/appendix/fixed_lag/USA.png, replace
drop if L0_b == .
keep *_at *_ll1 *_ul1 *_b
egen policy = seq()
reshape long L0_ L1_ L2_ L3_ L4_ L5_, i(policy) j(temp) string
rename *_ *
reshape long L, i(temp policy) j(val)
tostring policy, replace
replace policy = "No gathering, event cancel" if policy == "1"
replace policy = "Social distance" if policy == "2"
replace policy = "Quarantine positive cases"  if policy == "3"
replace policy = "Paid sick leave" if policy == "4"
replace policy = "Work from home" if policy == "5"
replace policy = "School closure" if policy == "6"
replace policy = "Travel ban" if policy == "7"
replace policy = "Business closure" if policy == "8"
replace policy = "Home isolation" if policy == "9"
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
