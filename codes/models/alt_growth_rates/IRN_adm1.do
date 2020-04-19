// IRN | adm1 

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

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

// high_screening_regime in Qom, which transitioned on Mar 6
// assume rollout completed on Mar 13
drop testing_regime_change_06mar2020
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

// Merging March 1-5 policies, since they all happened at the same time during 
// break in the health data (missing cases for 3/2-3/3)
// so p_1 = 1/3 on 3/1 when opt travel ban enacted, then p_1 = 1 starting 3/5
gen p_1 = (travel_ban_local_opt + work_from_home + school_closure)/3
lab var p_1 "Travel ban (opt), work from home, school closure"

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
 addtext(Province FE, "YES", Day-of-Week FE, "YES") title(Iran, "Dependent variable: Growth rate of cumulative confirmed cases (\u0916?log per day\'29") ///
 ctitle("Coefficient"; "Robust Std. Error") nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" /// 
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

hist e, bin(30) tit(Iran) lcolor(white) fcolor(navy) xsize(5) name(hist_irn, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_irn, replace)

graph combine hist_irn qn_irn, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_irn.gph, replace)
graph drop hist_irn qn_irn

outsheet adm0_name e using "results/source_data/indiv/ExtendedDataFigure1_IRN_e.csv" if e(sample), comma replace


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
caption("p_1 = (travel_ban_local_opt + work_from_home + school_closure) / 3", span) ///
xline(0) name(IRN_policy, replace)


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
tw (rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/IRN_adm1_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_IRN_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

// tw (rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title(Iran, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21970(10)22011)) xlabel(21970(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0))


//-------------------------------Running the model for Tehran only 

// gen cases_to_pop = cum_confirmed_cases / population
// keep if cum_confirmed_cases!=.
// collapse (min) t (max) cases_to_pop cum_confirmed_cases, by(adm1_name)
// sort cum_confirmed_cases

reg D_l_cum_confirmed_cases testing_regime_* p_1 p_2 if adm1_name=="Tehran"

// predicted "actual" outcomes with real policies
predictnl y_actual_thr = xb() if e(sample), ci(lb_y_actual_thr ub_y_actual_thr)

// predicting counterfactual growth for each obs
predictnl y_counter_thr =  testing_regime_13mar2020 * _b[testing_regime_13mar2020] + ///
_b[_cons] if e(sample), ci(lb_counter_thr ub_counter_thr)

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual_thr y_counter_thr lb_y_actual_thr ub_y_actual_thr lb_counter_thr ub_counter_thr {
	replace `var' = 0 if `var'<0 & `var'!=.
}

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2
*post results ("IRN_Tehran") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter_thr
*post results ("IRN_Tehran") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

// export coefficients (FOR FIG2)
postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/indiv/Figure2_IRN_coefs.csv", comma replace
restore

// Observed avg change in log cases
reg D_l_cum_confirmed_cases i.t if adm1_name  == "Tehran"
predict day_avg_thr if adm1_name  == "Tehran" & e(sample) == 1

// Graph of predicted growth rates
// fixed x-axis across countries
tw (rspike ub_y_actual_thr lb_y_actual_thr t_random, lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter_thr lb_counter_thr t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual_thr t, msize(tiny) color(blue*.5) ) ///
(scatter y_counter_thr t, msize(tiny) color(red*.5)) ///
(connect y_actual_thr t, color(blue) m(square) lpattern(solid)) ///
(connect y_counter_thr t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg_thr t, color(black)) ///
if e(sample), ///
title("Tehran, Iran", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") xtit("") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8) titlegap(*6.5)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/subnatl_growth_rates/Tehran_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual_thr lb_y_actual_thr ub_y_actual_thr y_counter_thr lb_counter_thr ub_counter_thr day_avg_thr)
outsheet adm0_name adm1_name t y_actual_thr lb_y_actual_thr ub_y_actual_thr y_counter_thr lb_counter_thr ub_counter_thr day_avg_thr ///
using "results/source_data/indiv/ExtendedDataFigure9b_Tehran_data.csv" if miss_ct<7, comma replace
drop miss_ct


//----------------------------------------------FIXED LAG 
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
 
foreach lags of num 1 2 3 4 5 10 15{ 
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
ylabel(1 "Travel ban (opt), work from home, school closure" ///
2 "Home isolation", angle(0)) ///
ytitle("") title("Iran - comparing Fixed Lags models") ///
legend(order(2 4 6 8 10 12) lab(2 "L0") lab(4 "L1") lab(6 "L2") lab(8 "L3") ///
lab(10 "L4") lab(12 "L5") rows(1) region(lstyle(none)))
graph export results/figures/appendix/fixed_lag/IRN.pdf, replace
graph export results/figures/appendix/fixed_lag/IRN_FL.png, replace
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
outsheet * using "results/source_data/indiv/ExtendedDataFigure8_fixed_lag_IRN.csv", replace	

use `f0', clear
foreach L of num 1 2 3 4 5 10 15 {
	append using `f`L''
}
g adm0 = "IRN"
outsheet * using "models/IRN_ATE.csv", comma replace 

use `base_data', clear
//------------------------NEW: EVENT STUDY
preserve
local policy_study = "p_2"

gen D_`policy_study' = D.`policy_study'

egen other_policy = rowtotal(p_1 p_2)

replace other_policy = other_policy - `policy_study'

*xtset adm1_id t
g moveave = (F4.other_policy + F3.other_policy ///
+ F2.other_policy + F1.other_policy + other_policy + L1.other_policy ///
+ L2.other_policy + L3.other_policy + L4.other_policy) /9

g stable = other_policy == moveave
//create a dummy variable if keeping in the event study
g event_sample_`policy_study' = 0

//identify observations that could potentially go into the event study sample (nearby enough to event and not contaminated by travel ban)
replace event_sample_`policy_study' = 1 if D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if L1.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if L2.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if L3.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if L4.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1

replace event_sample_`policy_study' = 1 if F1.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if F2.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if F3.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1
replace event_sample_`policy_study' = 1 if F4.D_`policy_study' !=0 & D_l_cum_confirmed_cases ~=. & stable == 1


bysort adm1_id: egen event_count = total(event_sample_`policy_study')
tab event_count
keep if event_count >= 7 & event_sample == 1

//create dummy vars for the days relative to the event
gen f1 = F1.D_`policy_study' 
gen f2 = F2.D_`policy_study'
gen f3 = F3.D_`policy_study'
gen f4 = F4.D_`policy_study'

gen l0 = D_`policy_study' 
gen l1 = L1.D_`policy_study' 
gen l2 = L2.D_`policy_study' 
gen l3 = L3.D_`policy_study' 
gen l4 = L4.D_`policy_study' 

foreach var in f1 f2 f3 f4 l0 l1 l2 l3 l4 {
	replace `var' = 0 if `var' == .
}


//this is just a binary if pre-treatment
gen pre_treat = f4 + f3 +  f2 + f1

//computing the pre-treatment mean
sum D_l_cum_confirmed_cases if pre_treat > 0
loc pre_treat_val = r(mean)


//event study regression
reg D_l_cum_confirmed_cases f4 f3 f2 f1 l0 l1 l2 l3 l4, cluster(adm1_id) nocons

**alternative
lincom (f4 + f3 + f2 + f1) / 4
loc pre_treat_val = r(estimate)
coefplot , vertical keep(f4 f3 f2 f1 l0 l1 l2 l3 l4) yline(`pre_treat_val') ///
title("Iran - Event study - home isolation")  xline(4.5, lc(black) lp(dash))
graph export results/figures/appendix/IRN_event_study.png, replace
restore


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
	set scheme s1color
	use `results_file_crossV', clear
	egen i = group(policy)
	tw scatter i beta , xline(0,lc(black) lp(dash)) mc(black*.5)   ///
	|| scatter i beta if sample == "full_sample", mc(red)  ///
	yscale(range(0.5(0.5)3.5)) ylabel(1 "combined effect" ///
	2  "Travel ban (opt), work from home, school closure" ///
	3 "Home isolation", angle(0)) ///
	xtitle("Estimated effect on daily growth rate", height(5)) ///
	legend(order(2 1) lab(2 "Full sample") lab(1 "Leaving one region out") ///
	region(lstyle(none))) ///
	ytitle("") xscale(range(-0.6(0.2)0.2)) xlabel(#5) xsize(7)
	graph export results/figures/appendix/cross_valid/IRN.pdf, replace
	graph export results/figures/appendix/cross_valid/IRN.png, replace	
	outsheet * using "results/source_data/indiv/ExtendedDataFigure7_cross_valid_IRN.csv", comma replace
restore
