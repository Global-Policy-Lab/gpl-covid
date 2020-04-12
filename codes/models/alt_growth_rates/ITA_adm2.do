// ITA | adm2

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using codes/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm2/ITA_processed.csv, clear

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)


// clean up
drop if adm2_name == "Unknown"
drop adm1_id adm2_id
encode adm1_name, gen(adm1_id)
encode adm2_name, gen(adm2_id)
duplicates report adm2_id t

// set up panel
tsset adm2_id t, daily

// quality control
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 
keep if t >= mdy(2,26,2020) // start date
keep if t <= date("`end_sample'","YMD") // to match other country end dates

// flag which admin unit has longest series
tab adm2_name if cum_confirmed_cases!=., sort 
bysort adm1_name adm2_name: egen adm2_obs_ct = count(cum_confirmed_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name adm2_name: egen adm2_max_cases = max(cum_confirmed_cases)
egen max_obs_ct = max(adm2_obs_ct)
bysort adm2_obs_ct: egen max_obs_ct_max_cases = max(adm2_max_cases) 

gen longest_series = adm2_obs_ct==max_obs_ct & adm2_max_cases==max_obs_ct_max_cases
drop adm2_obs_ct adm2_max_cases max_obs_ct max_obs_ct_max_cases

sort adm2_id t
tab adm2_name if longest_series==1 & cum_confirmed_cases!=.

// construct dep vars
lab var cum_confirmed_cases "cumulative confirmed cases"

gen l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_cum_confirmed_cases "log(cum_confirmed_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases 
lab var D_l_cum_confirmed_cases "change in log(cum_confirmed_cases)"

// quality control: cannot have negative changes in cumulative values
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 


//--------------testing regime changes

// testing regime change on Feb 26, which is the start of sample so no changes to account for
// // grab each date of any testing regime change
// preserve
// 	collapse (min) t, by(testing_regime)
// 	sort t //should already be sorted but just in case
// 	drop if _n==1 //dropping 1st testing regime of sample (no change to control for)
// 	levelsof t, local(testing_change_dates)
// restore
//
// // create a dummy for each testing regime change date
// foreach t_chg of local testing_change_dates{
// 	local t_str = string(`t_chg', "%td")
// 	gen testing_regime_change_`t_str' = t==`t_chg'
// }

//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons] if longest_series==1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1
lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------grouping treatments (based on timing and similarity)

// popwt vars = policy intensity * population weight of respective admin 2 unit or sub admin 2 unit

// combine optional policies with respective mandatory policies
// weighing optional policies by 1/2
gen social_distance_comb_popwt = social_distance_popwt + social_distance_opt_popwt * 0.5 
gen work_from_home_comb_popwt = work_from_home_popwt + work_from_home_opt_popwt * 0.5


gen p_1 = (no_gathering_popwt + social_distance_comb_popwt + work_from_home_comb_popwt)/3
gen p_2 = school_closure_popwt  
gen p_3 = (travel_ban_local_popwt + transit_suspension_popwt)/2 //transit_suspensions all happen on 2/23 with travel_ban_local in respective admin units
gen p_4 = pos_cases_quarantine_popwt 
gen p_5 = business_closure_popwt
gen p_6 = home_isolation_popwt  
 
lab var p_1 "Social distance"
lab var p_2 "School closure"
lab var p_3 "Travel ban"
lab var p_4 "Quarantine positive cases"
lab var p_5 "Business closure"
lab var p_6 "Home isolation"

  
//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/ITA_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases p_*, absorb(i.adm2_id i.dow, savefe) cluster(t) resid

outreg2 using "results/tables/ITA_estimates_table", sideway noparen nodepvar word replace label ///
 addtext(Province FE, "YES", Day-of-Week FE, "YES") title(Italy, "Dependent variable: Growth rate of cumulative confirmed cases (\u0916?log per day\'29") ///
 ctitle("Coefficient"; "Robust Std. Error") nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" /// 
 "\'22Social distance\'22 includes policies for working from home, maintaining 1 meter distance from others in public, and prohibiting public and private events.")
cap erase "results/tables/ITA_estimates_table.txt"

// save coef
tempfile results_file
postfile results str18 adm0 str18 policy beta se using `results_file', replace
foreach var in "p_1" "p_2" "p_3" "p_4" "p_5" "p_6"{
	post results ("ITA") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

// check underreporting estimate
// gen D_l_cum_confirmed_cases_adj = D_l_cum_confirmed_cases
// 	replace D_l_cum_confirmed_cases_adj = . if ((cum_confirmed_cases/0.054) / population) > 0.01
//	
// reghdfe D_l_cum_confirmed_cases_adj p_*, absorb(i.adm2_id i.dow, savefe) cluster(t) resid


//------------- checking error structure (appendix)

predict e if e(sample), resid

hist e, bin(30) tit(Italy) lcolor(white) fcolor(navy) xsize(5) name(hist_ita, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) name(qn_ita, replace)

graph combine hist_ita qn_ita, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_ita.gph, replace)
graph drop hist_ita qn_ita

outsheet e using "results/source_data/ExtendedDataFigure1_ITA_e.csv" if e(sample), comma replace


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = ///
p_1 * _b[p_1] + ///
p_2 * _b[p_2] + ///
p_3 * _b[p_3] + /// 
p_4 * _b[p_4] + /// 
p_5 * _b[p_5] + /// 
p_6 * _b[p_6] /// 
if e(sample)

// predicting counterfactual growth for each obs
predictnl y_counter = _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of package of policies (FOR FIG2)
lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6
post results ("ITA") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// compute ATE
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases  p_* 
	predictnl ATE = p_1*_b[p_1] + p_2* _b[p_2] + p_3*_b[p_3] + p_4*_b[p_4] + p_5*_b[p_5] + p_6*_b[p_6], ci(LB UB) se(sd) p(pval)
	g adm0 = "ITA"
	outsheet * using "models/ITA_ATE.csv", comma replace 
restore

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix lb_y_actual so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}
	
// the mean here is the avg "biological" rate of initial spread (FOR Fig2)
sum y_counter
post results ("ITA") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to Fig2)
coefplot, keep(p_*) tit("ITA: policy packages") subtitle(`subtitle2') xline(0) name(ITA_policy, replace)

// export coefficients (FOR FIG2)
postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/Figure2_ITA_coefs.csv", comma replace
restore

//export predicted counterfactual growth rate
preserve
	keep if e(sample) == 1
	keep y_counter
	g adm0 = "ITA"
	outsheet * using "models/ITA_preds.csv", comma replace
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
title(Italy, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/fig3/raw/ITA_adm2_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(m_y_actual y_actual lb_y_actual ub_y_actual m_y_counter y_counter lb_counter ub_counter)
outsheet t m_y_actual y_actual lb_y_actual ub_y_actual m_y_counter y_counter lb_counter ub_counter ///
using "results/source_data/Figure3_ITA_data.csv" if miss_ct<8, comma replace
drop miss_ct

// tw (rspike ub_y_actual lb_y_actual t_random,  lwidth(vthin) color(blue*.5)) ///
// (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
// || (scatter y_actual t_random,  msize(tiny) color(blue*.5) ) ///
// (scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
// (connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
// (connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
// (sc day_avg t, color(black)) ///
// if e(sample), ///
// title(Italy, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
// xscale(range(21970(10)22011)) xlabel(21970(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
// yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) 
// br if adm2_name=="Isernia"


//-------------------------------Running the model for Lombardy only 

reghdfe D_l_cum_confirmed_cases p_* if adm1_name == "Lombardia", absorb(i.adm2_id i.dow, savefe) cluster(t) resid

// predicted "actual" outcomes with real policies
predictnl y_actual_lom = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual_lom ub_y_actual_lom)

// predicting counterfactual growth for each obs
predictnl y_counter_lom = _b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter_lom ub_counter_lom)

// quality control: don't want to be forecasting negative growth (not modeling recoveries)
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual_lom y_counter_lom lb_y_actual_lom ub_y_actual_lom lb_counter_lom ub_counter_lom {
	replace `var' = 0 if `var'<0 & `var'!=.
}

// computing daily avgs in sample, store with a single panel unit (longest time series)
reg y_actual_lom i.t if adm1_name == "Lombardia"
predict m_y_actual_lom if adm2_name=="Bergamo"

reg y_counter_lom i.t if adm1_name == "Lombardia"
predict m_y_counter_lom if adm2_name=="Bergamo"

// Observed avg change in log cases
reg D_l_cum_confirmed_cases i.t if adm1_name == "Lombardia"
predict day_avg_lom if adm2_name=="Bergamo" & e(sample) == 1

// Graph of predicted growth rates
// fixed x-axis across countries
tw (rspike ub_y_actual_lom lb_y_actual_lom t_random,  lwidth(vthin) color(blue*.5)) ///
(rspike ub_counter_lom lb_counter_lom t_random2, lwidth(vthin) color(red*.5)) ///
|| (scatter y_actual_lom t_random,  msize(tiny) color(blue*.5) ) ///
(scatter y_counter_lom t_random2, msize(tiny) color(red*.5)) ///
(connect m_y_actual_lom t, color(blue) m(square) lpattern(solid)) ///
(connect m_y_counter_lom t, color(red) lpattern(dash) m(Oh)) ///
(sc day_avg_lom t, color(black)) ///
if e(sample), ///
title("Lombardy, Italy", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") xtit("") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
saving(results/figures/appendix/sub_natl_growth_rates/Lombardy_conf_cases_growth_rates_fixedx.gph, replace)


//-------------------------------Running the model for certain provinces

gen cases_to_pop = cum_confirmed_cases / population
egen cases_to_pop_max = max(cases_to_pop)
tab adm2_name if cases_to_pop==cases_to_pop_max //Cremona

foreach province in "Cremona" "Bergamo" "Lodi" {

	reghdfe D_l_cum_confirmed_cases p_* if adm2_name=="`province'", noabsorb

	// predicted "actual" outcomes with real policies
	predictnl y_actual_`province' = xb() if e(sample), ci(lb_y_actual_`province' ub_y_actual_`province')
		
	// predicting counterfactual growth for each obs
	predictnl y_counter_`province' = _b[_cons] if e(sample), ci(lb_counter_`province' ub_counter_`province')

	// quality control: don't want to be forecasting negative growth (not modeling recoveries)
	// fix so there are no negative growth rates in error bars
	foreach var of varlist y_actual_`province' y_counter_`province' lb_y_actual_`province' ub_y_actual_`province' lb_counter_`province' ub_counter_`province' {
		replace `var' = 0 if `var'<0 & `var'!=.
	}

	// Observed avg change in log cases
	reg D_l_cum_confirmed_cases i.t if adm2_name=="`province'"
	predict day_avg_`province' if adm2_name=="`province'" & e(sample) == 1
	
	// Graph of predicted growth rates
	// fixed x-axis across countries
	local title = "`province'" + ", Italy"
	
	tw (rspike ub_y_actual_`province' lb_y_actual_`province' t,  lwidth(vthin) color(blue*.5)) ///
	(rspike ub_counter_`province' lb_counter_`province' t, lwidth(vthin) color(red*.5)) ///
	|| (scatter y_actual_`province' t,  msize(tiny) color(blue*.5) ) ///
	(scatter y_counter_`province' t, msize(tiny) color(red*.5)) ///
	(connect y_actual_`province' t, color(blue) m(square) lpattern(solid)) ///
	(connect y_counter_`province' t, color(red) lpattern(dash) m(Oh)) ///
	(sc day_avg_`province' t, color(black)) ///
	if e(sample), ///
	title("`title'", ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") xtit("") ///
	xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
	yscale(r(0(.2).8)) ylabel(0(.2).8) plotregion(m(b=0)) ///
	saving(results/figures/appendix/sub_natl_growth_rates/`province'_conf_cases_growth_rates_fixedx.gph, replace)
}

//-------------------------------Cross-validation
tempfile results_file_crossV
postfile results str18 adm0 str18 sample str18 policy beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_cum_confirmed_cases p_*, absorb(i.adm2_id i.dow, savefe) cluster(t) resid

foreach var in "p_1" "p_2" "p_3" "p_4" "p_5" "p_6"{
	post results ("ITA") ("full_sample") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}
lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6
post results ("ITA") ("full_sample") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_cum_confirmed_cases p_* if adm1_name != "`adm'", absorb(i.adm2_id i.dow, savefe) cluster(t) resid
	foreach var in "p_1" "p_2" "p_3" "p_4" "p_5" "p_6"{
		post results ("ITA") ("`adm'") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	}
	lincom p_1 + p_2 + p_3 + p_4 + p_5 + p_6
	post results ("ITA") ("`adm'") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
}
postclose results

preserve
	set scheme s1color
	use `results_file_crossV', clear
	egen i = group(policy)
	g minCI = beta - 1.96* se
	g maxCI = beta + 1.96* se
	tw scatter i beta if sample != "Lombardia", xline(0,lc(black) lp(dash)) mc(black*.5) ///
	|| scatter i beta if sample == "full_sample", mc(red)  ///
	|| scatter i beta if sample == "Lombardia", mc(green) m(Oh) ///
	yscale(range(0.5(0.5)3.5)) ylabel( ///
	1 "combined effect" ///
	2 "Social distance" ///
	3 "School closure" ///
	4 "Travel ban" ///
	5 "Quarantine positive cases" ///
	6 "Business closure" ///
	7 "Home isolation",  angle(0)) ///
	xtitle("Estimated effect on daily growth rate", height(5)) ///
	legend(order(2 1 3) lab(2 "Full sample") lab(1 "Leaving one region out") ///
	lab(3 "w/o Lombardia") region(lstyle(none)) rows(1)) ///
	ytitle("") xscale(range(-0.6(0.2)0.2)) xlabel(#5) xsize(7)
	graph export results/figures/appendix/cross_valid/ITA.pdf, replace
	graph export results/figures/appendix/cross_valid/ITA.png, replace	
	outsheet * using "results/source_data/extended_cross_validation_ITA.csv", replace	
restore

//-------------------------------Fixed lag

preserve
	reghdfe D_l_cum_confirmed_cases p_*, absorb(i.adm2_id i.dow, savefe) cluster(t) resid
	coefplot, keep(p_*) gen(L0_) title(main model) xline(0)
	 
	foreach lags of num 1/5 { 
		quietly {
		foreach var in p_1 p_2 p_3 p_4 p_5 p_6 {
			g `var'_copy = `var'
			g `var'_fixelag = L`lags'.`var'
			replace `var'_fixelag = 0 if `var'_fixelag  == .
			replace `var' = `var'_fixelag
			
		}
		drop *_fixelag 

		reghdfe D_l_cum_confirmed_cases p_1 p_2 p_3 p_4 p_5 p_6 , absorb(i.adm2_id i.dow, savefe) cluster(t) resid
		coefplot, keep(p_*) gen(L`lags'_) title (with fixed lag (4 days)) xline(0)
		local r2 = e(r2)
		replace L`lags'_at = L`lags'_at - 0.1 *`lags'
		
		foreach var in p_1 p_2 p_3 p_4 p_5 p_6 {
			replace `var' = `var'_copy
			drop `var'_copy
		}
		}
		di `r2'
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
	ylabel(1 "Social distance" ///
	2 "School closure" ///
	3 "Travel ban" ///
	4 "Quarantine positive cases" ///
	5 "Business closure" ///
	6 "Home isolation", angle(0)) ///
	ytitle("") title("Italy comparing Fixed Lags models") ///
	legend(order(2 4 6 8 10 12) lab(2 "L0") lab(4 "L1") lab(6 "L2") lab(8 "L3") ///
	lab(10 "L4") lab(12 "L5") rows(1) region(lstyle(none)))
	graph export results/figures/appendix/fixed_lag/ITA.pdf, replace
	graph export results/figures/appendix/fixed_lag/ITA.png, replace	
	drop if L0_b == .
	keep *_at *_ll1 *_ul1 *_b
	egen policy = seq()
	reshape long L0_ L1_ L2_ L3_ L4_ L5_, i(policy) j(temp) string
	rename *_ *
	reshape long L, i(temp policy) j(val)
	tostring policy, replace
	replace policy = "Social distance" if policy == "1"
	replace policy = "School closure" if policy == "2"
	replace policy = "Travel ban" if policy == "3"
	replace policy = "Quarantine positive cases" if policy == "4"
	replace policy = "Business closure" if policy == "5"
	replace policy = "Home isolation" if policy == "6"	
	rename val lag
	reshape wide L, i(lag policy) j(temp) string
	sort Lat
	rename (Lat Lb Lll1 Lul1) (position beta lower_CI upper_CI)
	outsheet * using "results/source_data/extended_fixed_lag_ITA.csv", replace
restore
