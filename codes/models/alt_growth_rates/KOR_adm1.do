// KOR | ADM1

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/KOR_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

// clean up
capture: drop adm2_id
encode adm1_name, gen(adm1_id)
duplicates report adm1_id t

// set up panel
tsset adm1_id t, daily

// quality control
replace active_cases = . if cum_confirmed_cases < 10 
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 

keep if t >= mdy(2,17,2020) // start date
keep if t <= date("`end_sample'","YMD") // to match other country end dates

// flag which admin unit has longest series
tab adm1_name if active_cases!=., sort 
bysort adm1_name: egen adm1_obs_ct = count(active_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name: egen adm1_max_cases = max(active_cases)
egen max_obs_ct = max(adm1_obs_ct)
bysort adm1_obs_ct: egen max_obs_ct_max_cases = max(adm1_max_cases) 

gen longest_series = adm1_obs_ct==max_obs_ct & adm1_max_cases==max_obs_ct_max_cases
drop adm1_obs_ct adm1_max_cases max_obs_ct max_obs_ct_max_cases

sort adm1_id t
tab adm1_name if longest_series==1 & active_cases!=.


// construct dep vars
lab var active_cases "active cases"

gen l_active_cases = log(active_cases)
lab var l_active_cases "log(active_cases)"

g l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_active_cases "log(cum_confirmed_cases)"

gen D_l_active_cases = D.l_active_cases 
*lab var D_l_active_cases "change in log(active_cases)"
lab var D_l_active_cases "Growth rate of active cases (\u0916?log per day)"


//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT

// this causes a smooth transition to avoid having negative transmissions, corrects for recoveries and deaths when the log approximation is not very good
gen transmissionrate = D.cum_confirmed_cases/L.active_cases 
gen D_l_active_cases_raw = D_l_active_cases 
lab var D_l_active_cases_raw "change in log active cases (no recovery adjustment)"
replace D_l_active_cases = transmissionrate if D_l_active_cases_raw < 0.04

//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT: END


// quality control
replace D_l_active_cases = . if D_l_active_cases < 0 // trying to not model recoveries


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
lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_active_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

gen p_1 = (business_closure_opt + work_from_home_opt + social_distance_opt + no_gathering_opt) / 4
gen p_2 = (no_demonstration + religious_closure + welfare_services_closure) / 3
gen p_3 = emergency_declaration
gen p_4 = pos_cases_quarantine

lab var p_1 "Social distance (optional)"
lab var p_2 "Social distance (mandatory)"
lab var p_3 "Emergency declaration"
lab var p_4 "Quarantine positive cases"

// note all schools are closed for the entire sample period
// event_cancel policies are enacted for entire sample as well

//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/KOR_reg_data.csv", comma replace

// main regression model
reghdfe D_l_active_cases p_* testing_regime_change_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

outreg2 using "results/tables/reg_results/KOR_estimates_table", sideway noparen nodepvar word replace label ///
 addtext(Province FE, "YES", Day-of-Week FE, "YES") title(South Korea, "Dependent variable: Growth rate of active cases (\u0916?log per day\'29") ///
 ctitle("Coefficient"; "Robust Std. Error") nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" /// 
 "\'22Social distance (optional)\'22 includes recommended policies related to social distancing, e.g. no gathering, work from home, and closing businesses such as karaoke and cyber cafes." "" ///
 "\'22Social distance (mandatory)\'22 includes prohibiting rallies, closing churches, and closing welfare service facilities.")
cap erase "results/tables/reg_results/KOR_estimates_table.txt"

// saving coef
tempfile results_file
postfile results str18 adm0 str18 policy beta se using `results_file', replace
foreach var in "p_1" "p_2" "p_3" "p_4" {
	post results ("KOR") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

//------------- checking residual structure (make appendix fig)

predict e if e(sample), resid

hist e, bin(30) tit(South Korea) lcolor(white) fcolor(navy) xsize(5) name(hist_kor, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_kor, replace)

graph combine hist_kor qn_kor, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_kor.gph, replace)
graph drop hist_kor qn_kor

outsheet adm0_name e using "results/source_data/indiv/ExtendedDataFigure10_KOR_e.csv" if e(sample), comma replace


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
p_4 * _b[p_4] /// 
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter = ///
testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
testing_regime_change_29feb2020 * _b[testing_regime_change_29feb2020] + ///
testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of all policies combined (FOR FIG2)
lincom p_1 + p_2 + p_3 + p_4
post results ("KOR") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter
post results ("KOR") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to FIG2)
coefplot, keep(p_*) tit("KOR: policy packages") subtitle(`subtitle2') ///
xline(0) name(KOR_policy, replace)
 

// export coefficients (FOR FIG2)
postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/indiv/Figure2_KOR_coefs.csv", comma replace 
restore

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
title("South Korea", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/KOR_adm1_active_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_KOR_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

// tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title("South Korea", ring(0)) ytit("Growth rate of" "active cases" "({&Delta}log per day)") ///
// xscale(range(21960(10)22011)) xlabel(21960(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) 


//-------------------------------Cross-validation
tempvar counter_CV
tempfile results_file_crossV
postfile results str18 adm0 str18 sample str18 policy beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_active_cases testing_regime_change_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid

foreach var in "p_1" "p_2" "p_3" "p_4"{
	post results ("KOR") ("full_sample") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}
lincom p_1 + p_2 + p_3 + p_4
post results ("KOR") ("full_sample") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
predictnl `counter_CV' = ///
testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
testing_regime_change_29feb2020 * _b[testing_regime_change_29feb2020] + ///
testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
sum `counter_CV'
post results ("KOR") ("full_sample") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
drop `counter_CV'
*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_active_cases testing_regime_change_* p_* if adm1_name != "`adm'", absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	foreach var in "p_1" "p_2" "p_3" "p_4"{
		post results ("KOR") ("`adm'") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	}
	lincom p_1 + p_2 + p_3 + p_4 
	post results ("KOR") ("`adm'") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	predictnl `counter_CV' = ///
	testing_regime_change_20feb2020 * _b[testing_regime_change_20feb2020] + ///
	testing_regime_change_29feb2020 * _b[testing_regime_change_29feb2020] + ///
	testing_regime_change_22mar2020 * _b[testing_regime_change_22mar2020] + /// 
	testing_regime_change_27mar2020 * _b[testing_regime_change_27mar2020] + /// 
	_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
	sum `counter_CV'
	post results ("KOR") ("`adm'") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
	drop `counter_CV'	
}
postclose results

preserve
	set scheme s1color
	use `results_file_crossV', clear
	egen i = group(policy)
	g minCI = beta - 1.96* se
	g maxCI = beta + 1.96* se
	tw scatter i beta if sample != "Seoul", xline(0,lc(black) lp(dash)) mc(black*.5) ///
	|| scatter i beta if sample == "full_sample", mc(red)  ///
	|| scatter i beta if sample == "Seoul", mc(green) m(Oh) ///
	yscale(range(0.5(0.5)3.5)) ylabel( ///
	1 "combined effect" ///
	2 "Social distance (optional)" ///
	3 "Social distance (mandatory)" ///
	4 "Emergency declaration" ///
	5 "Quarantine positive cases",  angle(0)) ///
	xtitle("Estimated effect on daily growth rate", height(5)) ///
	legend(order(2 1 3) lab(2 "Full sample") lab(1 "Leaving one region out") ///
	lab(3 "w/o Seoul") region(lstyle(none)) rows(1)) ///
	ytitle("") xscale(range(-0.6(0.2)0.2)) xlabel(#5) xsize(7)
	graph export results/figures/appendix/cross_valid/KOR.pdf, replace
	graph export results/figures/appendix/cross_valid/KOR.png, replace
	outsheet * using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_KOR.csv", comma replace	
restore

tempfile base_data
save `base_data'

//------------------------------------FIXED LAG 

reghdfe D_l_active_cases testing_regime_change_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
coefplot, keep(p_*) gen(L0_) title(main model) xline(0)
local r2 = e(r2)

preserve
	keep if e(sample) == 1
	collapse  D_l_active_cases p_* 
	predictnl ATE = p_1*_b[p_1] + p_2*_b[p_2] + p_3*_b[p_3] + p_4*_b[p_4], ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g lag = 0
	g r2 = `r2'
	tempfile f0
	save `f0'
restore	 
  
foreach lags of num 1 2 3 4 5{ 
	quietly {
	foreach var in p_1 p_2 p_3 p_4{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag  == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag 

	reghdfe D_l_active_cases testing_regime_change_* p_1 p_2 p_3 p_4, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	coefplot, keep(p_*) gen(L`lags'_) title (with fixed lag (4 days)) xline(0)
	local r2 = e(r2)
	

	preserve
		keep if e(sample) == 1
		collapse  D_l_active_cases p_* 
		predictnl ATE = p_1*_b[p_1] + p_2*_b[p_2] + p_3*_b[p_3] + p_4*_b[p_4], ci(LB UB) se(sd) p(pval)
		keep ATE LB UB sd pval 
		g lag = `lags'
		g r2 = `r2'
		tempfile f`lags'
		save `f`lags''
	restore	 	
	
	replace L`lags'_at = L`lags'_at - 0.1 *`lags'
	
	foreach var in p_1 p_2 p_3 p_4{
		replace `var' = `var'_copy
		drop `var'_copy
	}
	}
	di `r2'
}



// get r2
matrix rsq = J(16,3,0)
foreach lags of num 0/15{ 
	quietly {
	foreach var in p_1 p_2 p_3 p_4 {
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag
	}
	bootstrap e(r2), rep(1000) seed(1) : ///
	reghdfe D_l_active_cases testing_regime_change_* p_1 p_2 p_3 p_4, absorb(i.adm1_id i.dow) 
	foreach var in p_1 p_2 p_3 p_4 {
		qui replace `var' = `var'_copy
		qui drop `var'_copy
	}
	matrix rsq[`lags'+1,1] = _b[_bs_1]
	matrix rsq[`lags'+1,2] = _se[_bs_1]
	matrix rsq[`lags'+1,3] = `lags'
}

preserve
clear
svmat rsq
rename (rsq1 rsq2 rsq3) (r2 se lag_length)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_r2_KOR.csv", replace	
restore


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
ylabel( ///
1 "Social distance (optional)" ///
2 "Social distance (mandatory)" ///
3 "Emergency declaration" ///
4 "Quarantine positive cases", angle(0)) ///
ytitle("") title("South Korea comparing fixed lags models") ///
legend(order(2 4 6 8 10 12) lab(2 "L0") lab(4 "L1") lab(6 "L2") lab(8 "L3") ///
lab(10 "L4") lab(12 "L5") rows(1) region(lstyle(none)))
graph export results/figures/appendix/fixed_lag/KOR.pdf, replace
graph export results/figures/appendix/fixed_lag/KOR.png, replace

drop if L0_b == .
keep *_at *_ll1 *_ul1 *_b
egen policy = seq()
reshape long L0_ L1_ L2_ L3_ L4_ L5_, i(policy) j(temp) string
rename *_ *
reshape long L, i(temp policy) j(val)
tostring policy, replace
replace policy = "Social distance (optional)" if policy == "1"
replace policy = "Social distance (mandatory)" if policy == "2"
replace policy = "Emergency declaration" if policy == "3"
replace policy = "Quarantine positive cases" if policy == "4"
rename val lag
reshape wide L, i(lag policy) j(temp) string
sort Lat
rename (Lat Lb Lll1 Lul1) (position beta lower_CI upper_CI)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_fixed_lag_KOR.csv", replace

use `f0', clear
foreach L of num 1 2 3 4 5{
	append using `f`L''
}
g adm0 = "KOR"
outsheet * using "models/KOR_ATE.csv", comma replace 

use `base_data', clear
