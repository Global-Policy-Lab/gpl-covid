set matsize 5000
clear all

// CHN | ADM2 -----------------------------------------------------------------------------------

insheet using "models/reg_data/CHN_reg_data.csv", comma case clear

// look at obs pre any policy
gen any_policy = (travel_ban_local + home_isolation + emergency_declaration)>0
keep if any_policy==0

// flag which admin unit has longest series
drop adm1_adm2_name longest_series
gen adm1_adm2_name = adm2_name + ", " + adm1_name
tab adm1_adm2_name if active_cases!=., sort 
bysort adm1_name adm2_name: egen adm2_obs_ct = count(active_cases)

// if multiple admin units have max number of days w/ confirmed cases, 
// choose the admin unit with the max number of confirmed cases 
bysort adm1_name adm2_name: egen adm2_max_cases = max(active_cases)
egen max_obs_ct = max(adm2_obs_ct)
bysort adm2_obs_ct: egen max_obs_ct_max_cases = max(adm2_max_cases) 

gen longest_series = adm2_obs_ct==max_obs_ct & adm2_max_cases==max_obs_ct_max_cases
drop adm2_obs_ct adm2_max_cases max_obs_ct max_obs_ct_max_cases

sort adm12_id t
tab adm1_adm2_name if longest_series==1 & active_cases!=. //Wuhan

// set up panel
gen t2 = date(t, "DMY")
drop t
rename t2 t
format t %td

capture: drop adm2_id adm1_id adm12_id
encode adm2_name, gen(adm2_id)
encode adm1_name, gen(adm1_id)
gen adm12_id = adm1_id*1000+adm2_id
lab var adm12_id "Unique city identifier"

tsset adm12_id t, daily

// 1st diff of diff in log cases
gen D_D_l_active_cases = D.D_l_active_cases

// pre-policy time period
tab date if D_l_active_cases!=.

// checking for any time trend in pre-policy data
reg D_l_active_cases testing_regime_change_* t i.adm12_id, cluster(t)

local b_t = round(_b[t], .001)
local b_t_se = round(_se[t], .001)
local b_t_t = _b[t]/_se[t]
local b_t_p = round(2*ttail(e(df_r),abs(`b_t_t')), .001)
local n = e(N)

gen beta_t = _b[t] // basically the avg of D_D_l_active_cases but w/ controls
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at growth rate residuals
reg D_l_active_cases testing_regime_change_* i.adm12_id, cluster(t)
predict e_g if e(sample), resid

tw (sc e_g t)
hist e_g //looks skewed, right tail

gen D_e_g = D.e_g // first diff in resid
hist D_e_g //looks better, more normal, basically centered at zero, mean is slightly negative, but some outliers
// outlier = Beijing on 2/1

// plot 
tw (sc D_e_g t)(line beta_t t), title(CHN) ///
ytitle(Changes in growth rate residuals) xtitle("")

// look at date residuals, use for x-axis
// plotting by date doesn't exactly visually show what we're testing, 
// because the adm fixed effects also removes the mean from the date variable by adm unit
// date residuals represent the number of days before (for negative) or after (positive) the average date for that adm unit
// with an extra wee adjustment for testing regime changes
// It's like lining up all the adm units' dots from the other graph at their respective means
reg t testing_regime_change_* i.adm12_id if D_l_active_cases!=.
predict e_t if e(sample), resid

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e_g e_t, mlabel(adm2_name)) (lfit e_g e_t), title(CHN) ///
subtitle("pre-trend = `b_t', se = `b_t_se', p = `b_t_p', n = `n'") ///
ytitle(Growth rate residuals) xtitle("Date residuals") ///
xscale(r(-3(1)3)) xlabel(-3(1)3) name(CHN_pre, replace)

// checking for time trend in data w/ no policy in all of China
// first policy is Wuhan lockdown on 1/23
reg D_l_active_cases testing_regime_change_* t i.adm12_id if t<mdy(1,23,2020), cluster(t) 


// estimate a pretrend for each city seperately
bysort adm12_id: egen outcome_ct = count(D_l_active_cases)
drop if outcome_ct<2

// preserve
gen beta_t_adm2 = .
gen se = .
gen n = .

levelsof adm2_name, local(city)

foreach adm2 of local city{
	display "`adm2'"
	reg D_l_active_cases testing_regime_change_* t if adm2_name=="`adm2'", cluster(t)
	replace beta_t_adm2 = _b[t] if adm2_name=="`adm2'"
	capture replace se = _se[t] if adm2_name=="`adm2'"
	replace n = e(N) if adm2_name=="`adm2'"
}
collapse (first) beta_t_adm2 se n, by(adm2_name)



// KOR | ADM1 -----------------------------------------------------------------------------------

insheet using "models/reg_data/KOR_reg_data.csv", comma case clear

// look at obs pre any policy
egen policy_sum = rowtotal(p_*)
gen any_policy = policy_sum>0
keep if any_policy==0

// flag which admin unit has longest series
drop longest_series
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

// set up panel
gen t2 = date(t, "DMY")
drop t
rename t2 t
format t %td

capture: drop adm1_id
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// 1st diff of diff in log cases
gen D_D_l_active_cases = D.D_l_active_cases

// pre-policy time period
tab date if D_l_active_cases!=.

// plot growth rate levels 
// this does not control for testing regime changes or subnatl FE
tw (sc D_l_active_cases t, mlabel(adm1_name)), yline(.314) title(KOR) ///
ytitle(Growth rate) xtitle("")

// checking for any time trend in pre-policy data
// reghdfe D_l_active_cases testing_regime_change_* t, noconstant absorb(i.adm1_id, savefe) cluster(t) resid 
reg D_l_active_cases testing_regime_change_* t i.adm1_id, cluster(t) // same coef
	// no i.dow b/c only one week of pre-policy data

local b_t = round(_b[t], .001) //beta
local b_t_se = round(_se[t], .001) //se
local b_t_t = _b[t]/_se[t] //t-stat
local b_t_p = round(2*ttail(e(df_r),abs(`b_t_t')), .001) //p-value
local n = e(N)

gen beta_t = _b[t] // basically the avg of D_D_l_active_cases but w/ controls
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at growth rate residuals
// reghdfe D_l_active_cases testing_regime_change_*, noconstant absorb(i.adm1_id, savefe) cluster(t) resid
reg D_l_active_cases testing_regime_change_* i.adm1_id, cluster(t)
// residuals are the unobservables, and in this case it's time
predict e_g if e(sample), resid

// so plotting the residuals give us the time trend
// but controlling for testing regime change and adm1 FE
tw (sc e_g t)
hist e_g, freq width(.1)

gen D_e_g = D.e_g // first diff in resid
hist D_e_g, freq width(.01) title("First diff in residuals")

// plot --> can't see that it's diff from 0...
tw (sc D_e_g t)(line beta_t t), title(KOR) ///
ytitle(Changes in growth rate residuals) xtitle("")

// look at date residuals, use for x-axis
// plotting by date doesn't exactly visually show what we're testing, 
// because the adm fixed effects also removes the mean from the date variable by adm unit
// date residuals represent the number of days before (for negative) or after (positive) the average date for that adm unit
// with an extra wee adjustment for testing regime changes
// It's like lining up all the adm units' dots from the other graph at their respective means
reg t testing_regime_change_* i.adm1_id if D_l_active_cases!=.
predict e_t if e(sample), resid

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e_g e_t, mlabel(adm1_name)) (lfit e_g e_t), title(KOR) ///
subtitle("pre-trend = `b_t', se = `b_t_se', p = `b_t_p', n = `n'") ///
ytitle(Growth rate residuals) xtitle("Date residuals") ///
xscale(r(-3(1)3)) xlabel(-3(1)3) yscale(titlegap(*-37)) name(KOR_pre, replace) 

// 1st diff in log cases over time
tw (sc D_D_l_active_cases t), title(KOR) yscale(titlegap(*-37)) ///
ytitle(Diff in growth rates) xtitle("")



// ITA | ADM2 -----------------------------------------------------------------------------------

insheet using "models/reg_data/ITA_reg_data.csv", comma case clear

// look at obs pre any policy
egen policy_sum = rowtotal(p_*)
gen any_policy = policy_sum>0
keep if any_policy==0

// flag which admin unit has longest series
drop longest_series
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

// set up panel
gen t2 = date(t, "DMY")
drop t
rename t2 t
format t %td

capture: drop adm2_id
encode adm2_name, gen(adm2_id)
tsset adm2_id t, daily

// 1st diff of diff in log cases
gen D_D_l_cum_confirmed_cases = D.D_l_cum_confirmed_cases

// pre-policy time period
tab date if D_l_cum_confirmed_cases!=.

// plot growth rate levels --> can see negative trend
tw (sc D_l_cum_confirmed_cases t, m(Oh)) (lfit D_l_cum_confirmed_cases t), title(ITA) ///
ytitle(Growth rate) xtitle("")

// checking for any time trend in pre-policy data
// reghdfe D_l_cum_confirmed_cases t, noconstant absorb(i.adm2_id, savefe) cluster(t) resid //note: t is probably collinear with the fixed effects (all partialled-out values are close to zero
// reghdfe D_l_cum_confirmed_cases t i.adm2_id, noconstant noabsorb cluster(t) // matches reg w constant
// reg D_l_cum_confirmed_cases t i.adm2_id, noconstant cluster(t) // noconstant option gives junk results!!
reg D_l_cum_confirmed_cases t i.adm2_id, cluster(t)

// gen T = t - 21970
// reg D_l_cum_confirmed_cases T i.adm2_id, cluster(T) // rescaling t just calms down the constant

local b_t = round(_b[t], .001)
local b_t_se = round(_se[t], .001)
local b_t_t = _b[t]/_se[t]
local b_t_p = round(2*ttail(e(df_r),abs(`b_t_t')), .001)
local n = e(N)

gen beta_t = _b[t] // avg of D_D_l_cum_confirmed_cases
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at growth rate residuals
reg D_l_cum_confirmed_cases i.adm2_id, cluster(t)
predict e_g if e(sample), resid

tw (sc e_g t)
hist e_g, freq width(.1)

gen D_e_g = D.e_g // first diff in resid
hist D_e_g, freq width(.01) title("First diff in residuals")

// plot
tw (sc D_e_g t, m(Oh))(line beta_t t), title(ITA) ///
ytitle(Changes in growth rate residuals) xtitle("")

// look at date residuals, use for x-axis
reg t i.adm2_id if D_l_cum_confirmed_cases!=.
predict e_t if e(sample), resid

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e_g e_t, m(Oh) mlabel(adm2_name)) (lfit e_g e_t), title(ITA) ///
subtitle("pre-trend = `b_t', se = `b_t_se', p = `b_t_p', n = `n'")  ///
ytitle(Growth rate residuals) xtitle("Date residuals") ///
xscale(r(-1.5(.5)1.5)) xlabel(-1.5(.5)1.5) name(ITA_pre, replace)

// 1st diff in log cases over time
tw (sc D_D_l_cum_confirmed_cases t, m(Oh)), title(ITA) ///
ytitle(Diff in growth rates) xtitle("")



// IRN | ADM1 -----------------------------------------------------------------------------------

insheet using "models/reg_data/IRN_reg_data.csv", comma case clear

// look at obs pre any policy
egen policy_sum = rowtotal(p_*)
gen any_policy = policy_sum>0
keep if any_policy==0

// flag which admin unit has longest series
drop longest_series
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

// set up panel
gen t2 = date(t, "DMY")
drop t
rename t2 t
format t %td

capture: drop adm1_id
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// 1st diff of diff in log cases
gen D_D_l_cum_confirmed_cases = D.D_l_cum_confirmed_cases

// pre-policy time period
tab date if D_l_cum_confirmed_cases!=.

// plot growth rate levels
tw (sc D_l_cum_confirmed_cases t) (lfit D_l_cum_confirmed_cases t), title(IRN) ///
ytitle(Growth rate) xtitle("")

// checking for any time trend in pre-policy data
reg D_l_cum_confirmed_cases t i.adm1_id, cluster(t)

local b_t = round(_b[t], .001)
local n = e(N)

gen beta_t = _b[t] // avg of D_D_l_cum_confirmed_cases
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at growth rate residuals
reg D_l_cum_confirmed_cases i.adm1_id, cluster(t)
predict e_g if e(sample), resid

tw (sc e_g t)
hist e_g, freq width(.1)

gen D_e_g = D.e_g // first diff in resid
hist D_e_g, freq width(.01) title("First diff in residuals")

// plot
tw (sc D_e_g t)(line beta_t t), title(IRN) ///
ytitle(Changes in growth rate residuals) xtitle("")

// look at date residuals, use for x-axis
reg t i.adm1_id if D_l_cum_confirmed_cases!=.
predict e_t if e(sample), resid

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e_g e_t, mlabel(adm1_name)) (lfit e_g e_t), title(IRN) ///
subtitle("pre-trend = `b_t', n = `n'") ytitle(Growth rate residuals) xtitle("Growth rate residuals") ///
xscale(r(-1(0.5)1)) xlabel(-1(0.5)1) name(IRN_pre, replace)

// 1st diff in log cases over time
tw (sc D_D_l_cum_confirmed_cases t), title(IRN) ///
ytitle(Diff in growth rates) xtitle("")


// FRA | ADM1 -----------------------------------------------------------------------------------

insheet using "models/reg_data/FRA_reg_data.csv", comma case clear

// look at obs pre any policy
egen policy_sum = rowtotal(pck_social_distance school_closure national_lockdown)
gen any_policy = policy_sum>0
keep if any_policy==0

// flag which admin unit has longest series
drop longest_series
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

// set up panel
format t %td

capture: drop adm1_id
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// 1st diff of diff in log cases
gen D_D_l_cum_confirmed_cases = D.D_l_cum_confirmed_cases

// pre-policy time period
tab date if D_l_cum_confirmed_cases!=.

// plot growth rate levels
tw (sc D_l_cum_confirmed_cases t) ///
(lfit D_l_cum_confirmed_cases t), title(FRA) ///
ytitle(Growth rate) xtitle("")

// checking for any time trend in pre-policy data
reg D_l_cum_confirmed_cases t i.adm1_id, cluster(t)

local b_t = round(_b[t], .001)
local b_t_se = round(_se[t], .001)
local b_t_t = _b[t]/_se[t]
local b_t_p = round(2*ttail(e(df_r),abs(`b_t_t')), .001)
local n = e(N)

gen beta_t = _b[t] // avg of D_D_l_cum_confirmed_cases
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at growth rate residuals
reg D_l_cum_confirmed_cases i.adm1_id, cluster(t)
predict e_g if e(sample), resid

tw (sc e_g t)
hist e_g, freq width(.1)

gen D_e_g = D.e_g // first diff in resid
hist D_e_g, freq width(.01) title("First diff in residuals")

// plot
tw (sc D_e_g t)(line beta_t t), title(FRA) ///
ytitle(Changes in growth rate residuals) xtitle("")

// look at date residuals, use for x-axis
reg t i.adm1_id if D_l_cum_confirmed_cases!=.
predict e_t if e(sample), resid

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e_g e_t, mlabel(adm1_name)) (lfit e_g e_t), title(FRA) ///
subtitle("pre-trend = `b_t', se = `b_t_se', p = `b_t_p', n = `n'") ///
ytitle(Growth rate residuals) xtitle("Date residuals") ///
yscale(titlegap(*-37)) name(FRA_pre, replace)

// 1st diff in log cases over time
tw (sc D_D_l_cum_confirmed_cases t), title(FRA) ///
ytitle(Diff in growth rates) xtitle("")


// USA | ADM1 -----------------------------------------------------------------------------------

insheet using "models/reg_data/USA_reg_data.csv", comma case clear

// look at obs pre any policy
egen policy_sum = rowtotal(p_*)
gen any_policy = policy_sum>0
keep if any_policy==0

// flag which admin unit has longest series
drop longest_series
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

// set up panel
gen t2 = date(t, "DMY")
drop t
rename t2 t
format t %td

capture: drop adm1_id
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// 1st diff of diff in log cases
gen D_D_l_cum_confirmed_cases = D.D_l_cum_confirmed_cases

// pre-policy time period
tab date if D_l_cum_confirmed_cases!=.

// plot growth rate levels
tw (sc D_l_cum_confirmed_cases t) (lfit D_l_cum_confirmed_cases t), title(USA) ///
ytitle(Growth rate) xtitle("")

// checking for any time trend in pre-policy data
reg D_l_cum_confirmed_cases t i.adm1_id, cluster(t)

local b_t = round(_b[t], .001)
local b_t_se = round(_se[t], .001)
local b_t_t = _b[t]/_se[t]
local b_t_p = round(2*ttail(e(df_r),abs(`b_t_t')), .001)
local n = e(N)

gen beta_t = _b[t] // avg of D_D_l_cum_confirmed_cases
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at growth rate residuals
reg D_l_cum_confirmed_cases i.adm1_id, cluster(t)
predict e_g if e(sample), resid

tw (sc e_g t)
hist e_g, freq width(.1)

gen D_e_g = D.e_g // first diff in resid
hist D_e_g, freq width(.01) title("First diff in residuals")

// plot
tw (sc D_e_g t)(line beta_t t), title(USA) ///
ytitle(Changes in growth rate residuals) xtitle("")

// look at date residuals, use for x-axis
reg t i.adm1_id if D_l_cum_confirmed_cases!=.
predict e_t if e(sample), resid

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e_g e_t, mlabel(adm1_name)) (lfit e_g e_t), title(USA) ///
subtitle("pre-trend = `b_t', se = `b_t_se', p = `b_t_p', n = `n'")  ///
ytitle(Growth rate residuals) xtitle("Date residuals") name(USA_pre, replace)



// COMBINE -----------------------------------------------------------------------------------

graph combine CHN_pre KOR_pre ITA_pre IRN_pre FRA_pre USA_pre, ///
title("Pre-policy trends", size(small)) subtitle("controlling for testing regime changes and subnatl FE, clustered by date", size(small)) ///
colfirst cols(2) imargin(tiny) iscale(0.5)

graph export results/figures/appendix/prepolicy_growth_rates.pdf, replace
