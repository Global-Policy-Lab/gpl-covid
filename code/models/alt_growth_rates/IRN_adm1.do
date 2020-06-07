// IRN | adm1 

clear all
set scheme s1color
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/IRN_processed.csv, clear 

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
keep if t >= mdy(2,27,2020) // start date
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

// note: missing case data on 3/2/2020 and 3/3/2020
replace D_l_cum_confirmed_cases = . if t == 21976 | t == 21977 // dropping obs when no obs were reported
replace l_cum_confirmed_cases = . if t == 21976 | t == 21977 
replace cum_confirmed_cases = . if t == 21976 | t == 21977 


//------------------testing regime changes

// high_screening_regime in Qom/Gilan/Isfahan, which transitioned on Mar 6
// assume rollout completed on Mar 13 w rest of nation
gen testing_regime_13mar2020 = t==mdy(3,13,2020)
lab var testing_regime_13mar2020 "Testing regime change on Mar 13, 2020"


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

// NOTE: no_gathering has no variation

// create national opt travel ban var for all provinces except for Qom
// since Qom institutes opt travel ban on 2/20 before sample period
// and national opt travel ban enacted on 3/1
gen travel_ban_local_opt_natl = travel_ban_local_opt
	replace travel_ban_local_opt_natl = 0 if adm1_name=="Qom"

// create national school_closure var for provinces that close schools on 3/5
by adm1_id: egen school_closure_natl0 = min(school_closure) 
gen school_closure_natl = school_closure if school_closure_natl0==0
	replace school_closure_natl = 0 if school_closure_natl==.
drop school_closure_natl0
	
// Merging March 1-5 policies, since they all happened at the same time during 
// break in the health data (missing cases for 3/2-3/3)
// so p_1 = 1/3 on 3/1 when opt travel ban enacted, then p_1 = 1 starting 3/5
gen p_1 = (travel_ban_local_opt_natl + work_from_home + school_closure_natl)/3
lab var p_1 "Trvl ban opt, work home, school clos (natl)"

// home isolation started March 13
gen p_2 = home_isolation
lab var p_2 "Home isolation"

// shrines in Qom closed March 17
// gen p_3 = religious_closure
// lab var p_3 "Religious closure"
// will not include, insufficient data after enactment


//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/IRN_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_* testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(date) resid

outreg2 using "results/tables/reg_results/IRN_estimates_table", sideway noparen nodepvar word replace label ///
 title(Iran, "Dependent variable: growth rate of cumulative confirmed cases (\u0916?log per day\'29") ///
 stats(coef se pval) dec(3) ctitle("Coefficient"; "Std Error"; "P-value") nocons nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" ///
 "This regression includes province fixed effects, day-of-week fixed effects, and clustered standard errors at the day level." "" ///
 "\'22Travel ban (opt), work from home, school closure\'22 policies were enacted March 1-5, 2020 which overlaps with missing provincial case data in Iran on March 2-3, 2020.")
cap erase "results/tables/reg_results/IRN_estimates_table.txt"

// saving coefs
tempfile results_file
postfile results str18 adm0 str50 policy beta se using `results_file', replace
foreach var in "p_1" "p_2"{
	post results ("IRN") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

//------------- checking error structure (FOR APPENDIX FIGURE)

predict e if e(sample), resid

hist e, bin(30) tit(Iran) lcolor(white) fcolor(navy) xsize(5) ///
ylabel(, angle(horizontal)) plotregion(lcolor(white)) name(hist_irn, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) ///
ylabel(, angle(horizontal)) plotregion(lcolor(white)) name(qn_irn, replace)

graph combine hist_irn qn_irn, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_irn.gph, replace)
graph drop hist_irn qn_irn

outsheet adm0_name e using "results/source_data/indiv/ExtendedDataFigure10_IRN_e.csv" if e(sample), comma replace


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1 * _b[p_1] + ///
p_2 * _b[p_2] ///
if e(sample)

// predicting counterfactual growth for each obs
*gen y_counter = y_actual - treatment if e(sample)
predictnl y_counter = testing_regime_13mar2020 * _b[testing_regime_13mar2020] + ///
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2
post results ("IRN") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// quality control: cannot have negative growth in cumulative cases
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter
post results ("IRN") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (FOR FIG2)
coefplot, keep(p_1 p_2) tit("IRN: policy packages") subtitle(`subtitle2') ///
caption("p_1 = (travel_ban_local_opt + work_from_home + school_closure_natl) / 3", span) ///
xline(0) name(IRN_policy, replace)


// export coefficients (FOR FIG2)
postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/indiv/Figure2_IRN_coefs.csv", comma replace
restore

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
tw (rspike ub_counter lb_counter t_random2, lwidth(vvthin) color(red*.5)) ///
(rspike ub_y_actual lb_y_actual t_random, lwidth(vvthin) color(blue*.5)) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(Iran, ring(0) position(11)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) ///
saving(results/figures/fig3/raw/IRN_adm1_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_IRN_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

// tw (rspike ub_counter lb_counter t_random2, lwidth(vvthin) color(red*.5)) ///
// (rspike ub_y_actual lb_y_actual t_random, lwidth(vvthin) color(blue*.5)) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21970(10)22011)) xlabel(21970(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) 


//----------------------------------------------FIXED LAG 
set seed 1234

tempfile base_data
save `base_data'

reghdfe D_l_cum_confirmed_cases testing_regime_* p_*, absorb(i.adm1_id i.dow, savefe) cluster(date) resid
local r2=e(r2)
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases  p_* 
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] , ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g lag = 0
	g r2 = `r2'
	tempfile f0
	save `f0'
restore	 
coefplot, keep(p_*) gen(L0_) title(main model) xline(0)
 
foreach lags of num 1 2 3 4 5{ 
	quietly {
	foreach var in p_1 p_2{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag 

	reghdfe D_l_cum_confirmed_cases p_1 p_2 testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	coefplot, keep(p_*) gen(L`lags'_) title (with fixed lag (4 days)) xline(0)
	local r2 = e(r2)
	preserve
		keep if e(sample) == 1
		collapse  D_l_cum_confirmed_cases  p_* 
		predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] , ci(LB UB) se(sd) p(pval)
		keep ATE LB UB sd pval 
		g lag = `lags'
		g r2 = `r2'
		tempfile f`lags'
		save `f`lags''
	restore	 
 	
	
	replace L`lags'_at = L`lags'_at - 0.1 *`lags'
	
	foreach var in p_1 p_2{
		replace `var' = `var'_copy
		drop `var'_copy
	}
	}
}

// get r2
matrix rsq = J(16,3,0)
foreach lags of num 0/15{ 
	di "LAG `lags'"
	quietly {
	foreach var in p_1 p_2{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag
	xtset adm1_id t
	}
	if $BS != 0 {
		mat j = J($BS,1,0)
		forvalues i = 1/$BS {
		preserve
		bsample
		qui reghdfe D_l_cum_confirmed_cases p_1 p_2 testing_regime_*, absorb(i.adm1_id i.dow)
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
		qui reghdfe D_l_cum_confirmed_cases p_1 p_2 testing_regime_*, absorb(i.adm1_id i.dow)	
		matrix rsq[`lags'+1,1] = e(r2)
		matrix rsq[`lags'+1,2] = .
		matrix rsq[`lags'+1,3] = `lags'		
	}
	
	
	foreach var in p_1 p_2{
		qui replace `var' = `var'_copy
		qui drop `var'_copy
	}	

}

preserve
clear
svmat rsq
rename (rsq1 rsq2 rsq3) (r2 se lag_length)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_r2_IRN.csv", replace	
restore

drop if L0_b == .
keep *_at *_ll1 *_ul1 *_b
egen policy = seq()
reshape long L0_ L1_ L2_ L3_ L4_ L5_, i(policy) j(temp) string
rename *_ *
reshape long L, i(temp policy) j(val)
tostring policy, replace
replace policy = "Travel ban (opt), work from home, school closure" if policy == "1"
replace policy = "Home isolation" if policy == "2"
rename val lag
reshape wide L, i(lag policy) j(temp) string
sort Lat
rename (Lat Lb Lll1 Lul1) (position beta lower_CI upper_CI)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_fixed_lag_IRN.csv", replace	

use `f0', clear
foreach L of num 1 2 3 4 5{
	append using `f`L''
}
g adm0 = "IRN"
outsheet * using "models/IRN_ATE.csv", comma replace 

use `base_data', clear


//-------------------------------Cross-validation
tempvar counter_CV
tempfile results_file_crossV
postfile results str18 adm0 str18 sample str18 policy beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_cum_confirmed_cases p_* testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(date) resid

foreach var in "p_1" "p_2"{
	post results ("IRN") ("full_sample") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}
lincom p_1 + p_2 
post results ("IRN") ("full_sample") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

predictnl `counter_CV' =  testing_regime_13mar2020 * _b[testing_regime_13mar2020] + ///
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
sum `counter_CV'
post results ("IRN") ("full_sample") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
drop `counter_CV'


*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_cum_confirmed_cases p_* testing_regime_* if adm1_name != "`adm'", absorb(i.adm1_id i.dow, savefe) cluster(date) resid
	foreach var in "p_1" "p_2"{
		post results ("IRN") ("`adm'") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	}
	lincom p_1 + p_2 
	post results ("IRN") ("`adm'") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	predictnl `counter_CV' =  testing_regime_13mar2020 * _b[testing_regime_13mar2020] + ///
	_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
	sum `counter_CV'
	post results ("IRN") ("`adm'") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
	drop `counter_CV'	
}
postclose results

preserve
	use `results_file_crossV', clear
	egen i = group(policy)
	outsheet * using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_IRN.csv", comma replace
restore
