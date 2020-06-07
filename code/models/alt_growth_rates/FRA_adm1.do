// FRA | ADM1 

clear all
set scheme s1color
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/FRA_processed.csv, clear 
 
// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)

// set up panel
xtset adm1_id t

// quality control
drop if cum_confirmed_cases < 10  
keep if t >= date("20200229","YMD") // Non stable growth before that point & missing data, only one region with +10 but no growth
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


// construct dep vars
lab var cum_confirmed_cases "cumulative confirmed cases"

gen l_cum_confirmed_cases = log(cum_confirmed_cases)
lab var l_cum_confirmed_cases "log(cum_confirmed_cases)"

gen D_l_cum_confirmed_cases = D.l_cum_confirmed_cases 
lab var D_l_cum_confirmed_cases "change in log(cum. confirmed cases)"

gen l_cum_hospitalized = log(cum_hospitalized)
lab var l_cum_hospitalized "log(cum_hospitalized)"

gen D_l_cum_hospitalized = D.l_cum_hospitalized
lab var D_l_cum_hospitalized "change in log(cum_hospitalized)"


// quality control: cannot have negative changes in cumulative values
replace D_l_cum_confirmed_cases = . if D_l_cum_confirmed_cases < 0 //0 negative changes for France


//------------------diagnostic

// diagnostic plot of trends with sample avg as line
reg D_l_cum_confirmed_cases
gen sample_avg = _b[_cons] if e(sample)
replace sample_avg = . if longest_series==1

reg D_l_cum_confirmed_cases i.t
predict day_avg if longest_series==1 & e(sample)
lab var day_avg "Observed avg. change in log cases"

*tw (sc D_l_cum_confirmed_cases t, msize(tiny))(line sample_avg t)(sc day_avg t)


//------------------testing regime changes

g testing_regime_15mar2020 = t == mdy(3,15,2020) // start of stade 3, none systematic testing
lab var testing_regime_15mar2020 "Testing regime change on Mar 15, 2020"


//------------------generate policy packages
gen national_lockdown = (business_closure + home_isolation_popw) / 2 // big national lockdown policy
lab var national_lockdown "National lockdown"

gen no_gathering_5000 = no_gathering_size <= 5000 
gen no_gathering_1000 = no_gathering_size <= 1000 
gen no_gathering_100 = no_gathering_size <= 100

gen pck_social_distance = (no_gathering_1000 + no_gathering_100 + event_cancel_popw + no_gathering_inside_popw + social_distance_popw) / 5
lab var pck_social_distance "Social distance"

lab var school_closure_popwt "School closure"

//------------------main estimates

// output data used for reg
outsheet using "models/reg_data/FRA_reg_data.csv", comma replace

// main regression model
reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popw national_lockdown ///
 testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid  
est store base

outreg2 using "results/tables/reg_results/FRA_estimates_table", sideway noparen nodepvar word replace label ///
 title(France, "Dependent variable: growth rate of cumulative confirmed cases (\u0916?log per day\'29") ///
 stats(coef se pval) dec(3) ctitle("Coefficient"; "Std Error"; "P-value") nocons nonotes addnote("*** p<0.01, ** p<0.05, * p<0.1" "" ///
 "This regression includes region fixed effects, day-of-week fixed effects, and clustered standard errors at the day level." "" ///
 "\'22National lockdown\'22 policies include business closures and home isolation.")
cap erase "results/tables/reg_results/FRA_estimates_table.txt"

// saving coefs
tempfile results_file
postfile results str18 adm0 str18 policy beta se using `results_file', replace
foreach var in "national_lockdown" "school_closure_popwt" "pck_social_distance" {
	post results ("FRA") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

//------------- checking error structure (make fig for appendix)

predict e if e(sample), resid

hist e, bin(30) tit(France) lcolor(white) fcolor(navy) xsize(5) ///
ylabel(, angle(horizontal)) plotregion(lcolor(white)) name(hist_fra, replace)

qnorm e, mcolor(black) rlopts(lcolor(black)) xsize(5) ///
ylabel(, angle(horizontal)) plotregion(lcolor(white)) name(qn_fra, replace)

graph combine hist_fra qn_fra, rows(1) xsize(10) saving(results/figures/appendix/error_dist/error_fra.gph, replace)
graph drop hist_fra qn_fra

outsheet adm0_name e using "results/source_data/indiv/ExtendedDataFigure10_FRA_e.csv" if e(sample), comma replace


// ------------- generating predicted values and counterfactual predictions based on treatment

// predicted "actual" outcomes with real policies
*predict y_actual if e(sample)
predictnl y_actual = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual ub_y_actual)
lab var y_actual "predicted growth with actual policy"

// estimating magnitude of treatment effects for each obs
gen treatment = pck_social_distance * _b[pck_social_distance] + ///
school_closure_popwt * _b[school_closure_popwt] + ///
national_lockdown* _b[national_lockdown] ///
if e(sample)

// predicting counterfactual growth for each obs
predictnl y_counter = testing_regime_15mar2020 * _b[testing_regime_15mar2020] + ///
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter ub_counter)

// effect of package of policies (FOR FIG2)

// home_iso (national_lockdown) implies event_cancel, social_distance, no_gathering_inside and no_gathering
lincom national_lockdown + pck_social_distance
post results ("FRA") ("natl_lockdown_combined") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

nlcom (natl_lockdown_combined: _b[national_lockdown] + _b[pck_social_distance]), post
est store nlcom

// all policies
est restore base
lincom national_lockdown + school_closure_popwt + pck_social_distance 
post results ("FRA") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

local comb_policy = round(r(estimate), 0.001)
local subtitle = "Combined effect = " + string(`comb_policy') // for coefplot

// quality control: cannot have negative growth in cumulative cases
// fix so there are no negative growth rates in error bars
foreach var of varlist y_actual y_counter lb_y_actual ub_y_actual lb_counter ub_counter{
	replace `var' = 0 if `var'<0 & `var'!=.
}

// the mean here is the avg "biological" rate of initial spread (FOR FIG2)
sum y_counter
post results ("FRA") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 

local no_policy = round(r(mean), 0.001)
local subtitle2 = "`subtitle' ; No policy = " + string(`no_policy') // for coefplot

// looking at different policies (similar to FIG2)
// coefplot, keep(pck_social_distance school_closure_popwt national_lockdown) ///
// tit("FRA: policy packages") subtitle("`subtitle2'") ///
// caption("Social distance = (no_gath_1000 + no_gath_100 + event_cancel +" " no_gathering_inside + social_distance) / 5" ///
// "National lockdown = (business_closure + home_isolation) / 2", span) ///
// xline(0) name(FRA_policy, replace) 

coefplot (base, keep(pck_social_distance school_closure_popwt)) ///
(nlcom, keep(natl_lockdown_combined)), tit("FRA: policy packages") ///
subtitle(`subtitle2') xline(0) legend(off) name(FRA_policy, replace)

// export coefficients (FOR FIG2)
postclose results
preserve
	use `results_file', clear
	outsheet * using "results/source_data/indiv/Figure2_FRA_coefs.csv", comma replace
restore

// export predicted counterfactual growth rate
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
predict m_y_actual if longest_series==1

reg y_counter i.t
predict m_y_counter if longest_series==1


// add random noise to time var to create jittered error bars
set seed 1234
g t_random = t + rnormal(0,1)/10
g t_random2 = t + rnormal(0,1)/10

// Graph of predicted growth rates (FOR FIG3)

// fixed x-axis across countries
tw (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
(rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(France, ring(0) position(11)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21930(10)22011)) xlabel(21930(10)22011, nolabels tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) ///
saving(results/figures/fig3/raw/FRA_adm1_conf_cases_growth_rates_fixedx.gph, replace)

egen miss_ct = rowmiss(y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg)
outsheet adm0_name t y_actual lb_y_actual ub_y_actual y_counter lb_counter ub_counter m_y_actual m_y_counter day_avg ///
using "results/source_data/indiv/Figure3_FRA_data.csv" if miss_ct<9 & e(sample), comma replace
drop miss_ct

tw (rspike ub_counter lb_counter t_random2, lwidth(vthin) color(red*.5)) ///
(rspike ub_y_actual lb_y_actual t_random, lwidth(vthin) color(blue*.5)) ///
(scatter y_counter t_random2, msize(tiny) color(red*.5)) ///
(scatter y_actual t_random, msize(tiny) color(blue*.5) ) ///
(connect m_y_counter t, color(red) lpattern(dash) m(Oh)) ///
(connect m_y_actual t, color(blue) m(square) lpattern(solid)) ///
(sc day_avg t, color(black)) ///
if e(sample), ///
title(France, ring(0)) ytit("Growth rate of" "cumulative cases" "({&Delta}log per day)") ///
xscale(range(21970(10)22000)) xlabel(21970(10)22000, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) 


//-------------------------------Hospitalizations

tempfile base_data0
save `base_data0'

	// France reports hospitalization data by region past 3/25/2020
	keep if t>=mdy(3,3,2020) //data quality cutoff, only one region had 10 hospitalizations prior to 3/3
	gen testing_regime_06apr2020 = t==mdy(4,6,2020)
	gen mask_opt = t>=mdy(4,3,2020)
	outsheet using "models/reg_data/FRA_hosp_reg_data.csv", comma replace

	// hospitalization model
	reghdfe D_l_cum_hospitalized pck_social_distance school_closure_popwt national_lockdown mask_opt ///
	 testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid 
	 
	// predicted "actual" outcomes with real policies
	predictnl y_actual_hosp = xb() + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_y_actual_hosp ub_y_actual_hosp)

	// effect of all policies combined
	lincom national_lockdown + school_closure_popwt + pck_social_distance + mask_opt
	
	// compute ATE
	preserve
		collapse (first) adm0_name (mean) D_l_cum_hospitalized ///
		pck_social_distance school_closure_popwt national_lockdown mask_opt if e(sample) == 1
		
		predictnl ATE = pck_social_distance * _b[pck_social_distance] + ///
		school_closure_popwt * _b[school_closure_popwt] + ///
		national_lockdown * _b[national_lockdown] + ///
		mask_opt * _b[mask_opt]	///
		if e(sample), ci(LB UB) se(sd) p(pval)
		
		display ATE sd
	restore

	// predicting counterfactual growth for each obs
	predictnl y_counter_hosp = testing_regime_15mar2020 * _b[testing_regime_15mar2020] + ///
	testing_regime_06apr2020 * _b[testing_regime_06apr2020] + ///
	_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample), ci(lb_counter_hosp ub_counter_hosp)

	// quality control: cannot have negative growth in cumulative cases
	// fix so there are no negative growth rates in error bars
	foreach var of varlist y_actual_hosp y_counter_hosp lb_y_actual_hosp ub_y_actual_hosp lb_counter_hosp ub_counter_hosp{
		replace `var' = 0 if `var'<0 & `var'!=.
	}

	// looking at different policies (similar to FIG2)
	coefplot, keep(pck_social_distance school_closure_popwt national_lockdown mask_opt) ///
	tit("FRA: hospitalizations") xline(0) name(FRA_hosp_coef, replace) 

	// computing daily avgs in sample, store with a single panel unit (longest time series)
	reg y_actual_hosp i.t
	predict m_y_actual_hosp if longest_series==1

	reg y_counter_hosp i.t
	predict m_y_counter_hosp if longest_series==1

	// Observed avg change in log cases
	reg D_l_cum_hospitalized i.t
	predict day_avg_hosp if longest_series==1 & e(sample)

	// Graph of predicted growth rates (FOR ED FIG9)
	// fixed x-axis across countries
	tw (rspike ub_counter_hosp lb_counter_hosp t_random2, lwidth(vthin) color(red*.5)) ///
	(rspike ub_y_actual_hosp lb_y_actual_hosp t_random, lwidth(vthin) color(blue*.5)) ///
	(scatter y_counter_hosp t_random2, msize(tiny) color(red*.5)) ///
	(scatter y_actual_hosp t_random, msize(tiny) color(blue*.5) ) ///
	(connect m_y_counter_hosp t, color(red) lpattern(dash) m(Oh)) ///
	(connect m_y_actual_hosp t, color(blue) m(square) lpattern(solid)) ///
	(sc day_avg_hosp t, color(black) m(Dh)) ///
	if e(sample), ///
	title(France Hospitalizations, ring(0)) ytit("Growth rate of" "hospitalizations" "({&Delta}log per day)") ///
	xscale(range(21930(10)22011)) xlabel(21930(10)22011, format(%tdMon_DD) tlwidth(medthick)) tmtick(##10) ///
	yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white)) legend(off) ///
	saving(results/figures/appendix/FRA_adm1_hosp_growth_rates_fixedx.gph, replace)

	egen miss_ct = rowmiss(y_actual_hosp lb_y_actual_hosp ub_y_actual_hosp y_counter_hosp lb_counter_hosp ub_counter_hosp m_y_actual_hosp m_y_counter_hosp day_avg_hosp)
	outsheet adm0_name t y_actual_hosp lb_y_actual_hosp ub_y_actual_hosp y_counter_hosp lb_counter_hosp ub_counter_hosp m_y_actual_hosp m_y_counter_hosp day_avg_hosp ///
	using "results/source_data/indiv/ExtendedDataFigure6c_FRA_hosp_data.csv" if miss_ct<9 & e(sample), comma replace
	drop miss_ct

	// for legend
	tw (rspike ub_counter_hosp lb_counter_hosp t_random2, lwidth(vthin) color(red*.5)) ///
	(rspike ub_y_actual_hosp lb_y_actual_hosp t_random, lwidth(vthin) color(blue*.5)) ///	
	(scatter y_counter_hosp t_random2, msize(tiny) color(red*.5)) ///
	(scatter y_actual_hosp t_random, msize(tiny) color(blue*.5) ) ///
	(connect m_y_counter_hosp t, color(red) lpattern(dash) m(Oh)) ///
	(connect m_y_actual_hosp t, color(blue) m(square) lpattern(solid)) ///
	(sc day_avg_hosp t, color(black) m(Dh)) ///
	if e(sample), ///
	title(France Hospitalizations, ring(0)) ytit("Growth rate of" "hospitalizations" "({&Delta}log per day)") ///
	legend(order(7) cols(1) lab(7 "Observed change in log hospitalizations national avg") ///
	region(lcolor(none))) xlabel(, format(%tdMon_DD)) ///
	yscale(r(0(.2).8)) ylabel(0(.2).8, angle(horizontal)) plotregion(m(l=0.5 r=0.5 b=0 t=0.5) lcolor(white))
	graph export results/figures/appendix/legend_edfig9.pdf, replace

use `base_data0', clear

	// France reports hospitalization data by region past 3/25/2020
	keep if t>=mdy(3,3,2020) //data quality cutoff, only one region had 10 hospitalizations prior to 3/3
	keep if t<=mdy(3,25,2020) //use same end date as confirmed cases sample period

	// hospitalization model
	reghdfe D_l_cum_hospitalized pck_social_distance school_closure_popwt national_lockdown ///
	 testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid 

	// effect of all policies combined
	lincom national_lockdown + school_closure_popwt + pck_social_distance
	
	// compute ATE
	collapse (first) adm0_name (mean) D_l_cum_hospitalized ///
	pck_social_distance school_closure_popwt national_lockdown if e(sample) == 1
	
	predictnl ATE = pck_social_distance * _b[pck_social_distance] + ///
	school_closure_popwt * _b[school_closure_popwt] + ///
	national_lockdown * _b[national_lockdown] ///
	if e(sample), ci(LB UB) se(sd) p(pval)
	
	display ATE sd
		
use `base_data0', clear

//-------------------------------Cross-validation
tempvar counter_CV
tempfile results_file_crossV
postfile results str18 adm0 str18 sample str18 policy beta se using `results_file_crossV', replace

*Resave main effect
reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popwt ///
national_lockdown testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid 

foreach var in "school_closure_popwt" "pck_social_distance" {
	post results ("FRA") ("full_sample") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
}

lincom national_lockdown + pck_social_distance
post results ("FRA") ("full_sample") ("national_lockdown*") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

lincom national_lockdown + school_closure_popwt + pck_social_distance
post results ("FRA") ("full_sample") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 

predictnl `counter_CV' = testing_regime_15mar2020 * _b[testing_regime_15mar2020] + ///
_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
sum `counter_CV'
post results ("FRA") ("full_sample") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
drop `counter_CV'

*Estimate same model leaving out one region
levelsof adm1_name, local(state_list)
foreach adm in `state_list' {
	reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popwt national_lockdown ///
	 testing_regime_* if adm1_name != "`adm'" , absorb(i.adm1_id i.dow, savefe) cluster(t) resid 
	foreach var in "school_closure_popwt" "pck_social_distance" {
		post results ("FRA") ("`adm'") ("`var'") (round(_b[`var'], 0.001)) (round(_se[`var'], 0.001)) 
	}
	lincom national_lockdown + pck_social_distance
	post results ("FRA") ("`adm'") ("national_lockdown*") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 	
	
	lincom national_lockdown + school_closure_popwt + pck_social_distance
	post results ("FRA") ("`adm'") ("comb. policy") (round(r(estimate), 0.001)) (round(r(se), 0.001)) 
	predictnl `counter_CV' = testing_regime_15mar2020 * _b[testing_regime_15mar2020] + ///
	_b[_cons] + __hdfe1__ + __hdfe2__ if e(sample)
	sum `counter_CV'
	post results ("FRA") ("`adm'") ("no_policy rate") (round(r(mean), 0.001)) (round(r(sd), 0.001)) 
	drop `counter_CV'	
}
postclose results

preserve
	use `results_file_crossV', clear
	egen i = group(policy)
	outsheet * using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_FRA.csv", comma replace
restore


//-------------------------------FIXED LAG
set seed 1234

tempfile base_data
save `base_data'

reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popwt ///
national_lockdown testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid 
coefplot, keep(pck_social_distance school_closure_popwt national_lockdown) gen(L0_) title(main model) xline(0) 
lincom national_lockdown + pck_social_distance
replace L0_b = r(estimate) if L0_at == 3
replace L0_ll1 = r(estimate) - 1.959964 * r(se) if L0_at == 3
replace L0_ul1 = r(estimate) + 1.959964 * r(se) if L0_at == 3


// get ATE
local r2 = e(r2)
preserve
	keep if e(sample) == 1
	collapse  D_l_cum_confirmed_cases  pck_social_distance school_closure_popwt national_lockdown  
	predictnl ATE = school_closure_popwt * _b[school_closure_popwt] + ///
	pck_social_distance * _b[pck_social_distance] + ///
	national_lockdown* _b[national_lockdown], ci(LB UB) se(sd) p(pval)
	keep ATE LB UB sd pval 
	g lag = 0
	g r2 = `r2'
	tempfile f0
	save `f0'
restore		

reghdfe D_l_cum_hospitalized pck_social_distance school_closure_popwt national_lockdown ///
testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid 	 
coefplot, keep(pck_social_distance school_closure_popwt national_lockdown) gen(H0_) title(main model) xline(0) 
lincom national_lockdown + pck_social_distance
replace H0_b = r(estimate) if H0_at == 3
replace H0_ll1 = r(estimate) - 1.959964 * r(se) if H0_at == 3
replace H0_ul1 = r(estimate) + 1.959964 * r(se) if H0_at == 3
replace H0_at = H0_at - 0.04


foreach lags of num 1 2 3 4 5{ 
	quietly {
	foreach var in pck_social_distance school_closure_popwt national_lockdown{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag 

	reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popwt ///
	national_lockdown testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	coefplot, keep(pck_social_distance school_closure_popwt national_lockdown) ///
	gen(L`lags'_) title (with fixed lag (4 days)) xline(0)
	lincom national_lockdown + pck_social_distance
	replace L`lags'_b = r(estimate) if L`lags'_at == 3
	replace L`lags'_ll1 = r(estimate) - 1.959964 * r(se) if L`lags'_at == 3
	replace L`lags'_ul1 = r(estimate) + 1.959964 * r(se) if L`lags'_at == 3
	
	local r2 = e(r2)
	preserve
		keep if e(sample) == 1
		collapse  D_l_cum_confirmed_cases  pck_social_distance school_closure_popwt national_lockdown  
		predictnl ATE = school_closure_popwt * _b[school_closure_popwt] + ///
		pck_social_distance * _b[pck_social_distance] + ///
		national_lockdown* _b[national_lockdown], ci(LB UB) se(sd) p(pval)	
		keep ATE LB UB sd pval 
		g lag = `lags'
		g r2 = `r2'
		tempfile f`lags'
		save `f`lags''
	restore		
	
	replace L`lags'_at = L`lags'_at - 0.1 *`lags'
	
	reghdfe D_l_cum_hospitalized pck_social_distance school_closure_popwt national_lockdown ///
	testing_regime_*, absorb(i.adm1_id i.dow, savefe) cluster(t) resid
	coefplot, keep(pck_social_distance school_closure_popwt national_lockdown) ///
	gen(H`lags'_) title (with fixed lag (4 days)) xline(0)
	lincom national_lockdown + pck_social_distance
	replace H`lags'_b = r(estimate) if H`lags'_at == 3
	replace H`lags'_ll1 = r(estimate) - 1.959964 * r(se) if H`lags'_at == 3
	replace H`lags'_ul1 = r(estimate) + 1.959964 * r(se) if H`lags'_at == 3	
	replace H`lags'_at = H`lags'_at - 0.1 *`lags' - 0.04	
	
	foreach var in pck_social_distance school_closure_popwt national_lockdown{
		replace `var' = `var'_copy
		drop `var'_copy
	}
	}
}

// get r2
preserve
drop if t > date("20200325","YMD")
matrix rsq = J(16,3,0)
foreach lags of num 0/15{ 
	quietly {
	foreach var in pck_social_distance school_closure_popwt national_lockdown{
		g `var'_copy = `var'
		g `var'_fixelag = L`lags'.`var'
		replace `var'_fixelag = 0 if `var'_fixelag == .
		replace `var' = `var'_fixelag
		
	}
	drop *_fixelag
	}
	if $BS != 0 {	
		bootstrap e(r2), rep($BS) seed(1) : ///
		reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popwt ///
		national_lockdown testing_regime_*, absorb(i.adm1_id i.dow) 
		matrix rsq[`lags'+1,1] = _b[_bs_1]
		matrix rsq[`lags'+1,2] = _se[_bs_1]
		matrix rsq[`lags'+1,3] = `lags'
	}
	else {
		reghdfe D_l_cum_confirmed_cases pck_social_distance school_closure_popwt ///
		national_lockdown testing_regime_*, absorb(i.adm1_id i.dow) 
		matrix rsq[`lags'+1,1] = e(r2)
		matrix rsq[`lags'+1,2] = .
		matrix rsq[`lags'+1,3] = `lags'	
	}
	
	foreach var in pck_social_distance school_closure_popwt national_lockdown{
		qui replace `var' = `var'_copy
		qui drop `var'_copy
	}	
}
restore

preserve
clear
svmat rsq
rename (rsq1 rsq2 rsq3) (r2 se lag_length)
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_r2_FRA.csv", replace	
restore



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
|| rspike H0_ll1 H0_ul1 H0_at , hor xline(0) lc(ebblue) lw(thin) ///
|| scatter  H0_at H0_b, mc(ebblue)  ///
|| rspike H1_ll1 H1_ul1 H1_at , hor xline(0) lc(ebblue*.9) lw(thin) ///
|| scatter  H1_at H1_b, mc(ebblue*.9) ///
|| rspike H2_ll1 H2_ul1 H2_at , hor xline(0) lc(ebblue*.7) lw(thin) ///
|| scatter  H2_at H2_b, mc(ebblue*.7) ///
|| rspike H3_ll1 H3_ul1 H3_at , hor xline(0) lc(ebblue*.5) lw(thin) ///
|| scatter  H3_at H3_b, mc(ebblue*.5) ///
|| rspike H4_ll1 H4_ul1 H4_at , hor xline(0) lc(ebblue*.3) lw(thin) ///
|| scatter  H4_at H4_b, mc(ebblue*.3) ///
|| rspike H5_ll1 H5_ul1 H5_at , hor xline(0) lc(ebblue*.1) lw(thin) ///
|| scatter  H5_at H5_b, mc(ebblue*.1) ///	
ylabel(1 "Social distance" ///
2 "School closure" ///
3 "National lockdown", angle(0)) ///
ytitle("") title("France comparing Fixed Lags models") ///
legend(order(2 4 6 8 10 12 14 16 18 20 22 24) lab(2 "Conf. cases (end 03/25)")  ///
lab(4 "L1") lab(6 "L2") lab(8 "L3") lab(10 "L4") lab(12 "L5") ///
lab(14 "Hospitalization (end 04/06)") lab(16 "L1") lab(18 "L2") lab(20 "L3") ///
lab(22 "L4") lab(24 "L5")  cols(6) region(lstyle(none))) 
graph export results/figures/appendix/fixed_lag/FRA.pdf, replace
cap graph export results/figures/appendix/fixed_lag/FRA.png, replace
drop if L0_b == .
keep *_at *_ll1 *_ul1 *_b
egen policy = seq()
reshape long L0_ L1_ L2_ L3_ L4_ L5_ H0_ H1_ H2_ H3_ H4_ H5_, i(policy) j(temp) string
rename *_ *
reshape long L H, i(temp policy) j(val)
tostring policy, replace
replace policy = "Social distance" if policy == "1"
replace policy = "School closure" if policy == "2"
replace policy = "National lockdown" if policy == "3"
rename val lag
reshape wide L H, i(lag policy) j(temp) string
sort Lat
rename (Lat Lb Lll1 Lul1 Hat Hb Hll1 Hul1) (atL bL ll1L ul1L atH bH ll1H ul1H)
reshape long at b ll1 ul1, i(policy lag) j(hosp) string
replace hosp = "0" if hosp == "L"
replace hosp = "1" if hosp == "H"
destring hosp, replace
outsheet * using "results/source_data/indiv/ExtendedDataFigure5_fixed_lag_FRA.csv", replace

use `f0', clear
foreach L of num 1 2 3 4 5{
	append using `f`L''
}
g adm0 = "FRA"
outsheet * using "models/FRA_ATE.csv", comma replace 
use `base_data', clear
