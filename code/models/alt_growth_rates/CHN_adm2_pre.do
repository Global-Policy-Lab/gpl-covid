// CHN | ADM2

clear all
//-----------------------setup

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag=="CHN_analysis"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm2/CHN_processed.csv, clear 

cap set scheme covid19_fig3 // optional scheme for graphs

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
gen dow = dow(t)
gen month = month(t)
gen year = year(t)
gen day = day(t)


// clean up
replace cum_confirmed_cases = . if t < mdy(1,16,2020) 	//data quality cutoff date
replace active_cases = . if t < mdy(1,16,2020) 			//data quality cutoff date
replace active_cases_imputed = . if t < mdy(1,16,2020)	//data quality cutoff date

// cutoff date to ensure we are not looking at effects of lifting policy
keep if t <= date("`end_sample'","YMD")

// use this to identify cities, some have same names but different provinces
capture: drop adm2_id
encode adm2_name, gen(adm2_id)
encode adm1_name, gen(adm1_id)
gen adm12_id = adm1_id*1000+adm2_id
lab var adm12_id "Unique city identifier"
duplicates report adm12_id t

// set up panel
tsset adm12_id t, daily

// drop obs in two cities that lifted local travel ban before 3/5
tab adm2_name t if D.travel_ban_local==-1
bysort adm12_id: egen travel_ban_local_lift = min(t) if D.travel_ban_local==-1
bysort adm12_id: egen travel_ban_local_lift_cut = min(travel_ban_local_lift)

drop if travel_ban_local_lift_cut!=. & t>=travel_ban_local_lift_cut
drop travel_ban_local_lift travel_ban_local_lift_cut

// quality control
replace active_cases = . if cum_confirmed_cases < 10 
replace cum_confirmed_cases = . if cum_confirmed_cases < 10 

// drop cities if they never report when policies are implemented (e.g. could not find due to news censorship)
bysort adm12_id : egen ever_policy1 = max(home_isolation) 
bysort adm12_id : egen ever_policy2 = max(travel_ban_local) 
bysort adm12_id : egen ever_policy3 = max(emergency_declaration) 
// gen ever_policy = ever_policy1 + ever_policy2 + ever_policy3
// br if ever_policy==0 //Macau but no cases
gen ever_policy = ever_policy1 + ever_policy2 // only keeping 116 cities where we find at least one of travel ban or home iso b/c unlikely that the rest of cities did not implement
keep if ever_policy > 0

// look at obs pre any policy
gen any_policy = (travel_ban_local + home_isolation + emergency_declaration)>0
keep if any_policy==0

// flag which admin unit has longest series
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


// construct dep vars
lab var active_cases "active cases"

gen l_active_cases = log(active_cases)
lab var l_active_cases "log(active_cases)"

gen D_l_active_cases = D.l_active_cases 
lab var D_l_active_cases "change in log(active_cases)"


//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT

// this causes a smooth transition to avoid having negative transmissions, corrects for recoveries and deaths when the log approximation is very good
gen transmissionrate = D.cum_confirmed_cases/L.active_cases 
gen D_l_active_cases_raw = D_l_active_cases 
lab var D_l_active_cases_raw "change in log active cases (no recovery adjustment)"
replace D_l_active_cases = transmissionrate if D_l_active_cases_raw < 0.04

//------------------------------------------------------------------------ ACTIVE CASES ADJUSTMENT: END

//quality control
replace D_l_active_cases = . if D_l_active_cases > 1.5  // quality control
replace D_l_active_cases = . if D_l_active_cases < 0  // trying to not model recoveries
replace D_l_active_cases = . if D_l_active_cases == 0 & month == 1 // period of no case growth, not part of this analysis


//--------------testing regime changes

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

//--------------pretrend diagonostic

// pre-policy time period
tab date if D_l_active_cases!=.

// checking for any time trend in pre-policy data
reg D_l_active_cases testing_regime_change_* t i.adm12_id, cluster(t)

local b_t = round(_b[t], .001)
local b_t_se = round(_se[t], .001)
local n = e(N)

gen beta_t = _b[t] // basically the avg of D_D_l_active_cases but w/ controls
replace beta_t = . if longest_series==0 & e(sample) == 1

// look at residuals
reg D_l_active_cases testing_regime_change_* i.adm12_id, cluster(t)
predict e if e(sample), resid

tw (sc e t)
hist e //looks skewed, right tail

gen D_e = D.e // first diff in resid
hist D_e //looks better, more normal, basically centered at zero, mean is slightly negative, but some outliers
// outlier = Beijing on 2/1

// plot 
tw (sc D_e t)(line beta_t t), title(CHN: pre-policy) ///
ytitle(Changes in growth rate residuals) xtitle("")

// plot growth rate residuals, take out effect of controls
// plot dots and plot best fit line
tw (sc e t, mlabel(adm2_name)) (lfit e t), title(CHN: pre-policy) ///
subtitle("pre-trend = `b_t', se = `b_t_se', n = `n'") ///
ytitle(Growth rate residuals) xtitle("") name(CHN_pre, replace)

// checking for time trend in data w/ no policy in all of China
// first policy is Wuhan lockdown on 1/23
reg D_l_active_cases testing_regime_change_* t i.adm12_id if t<mdy(1,23,2020), cluster(t) 


// estimate a pretrend for each city seperately, and then plot the distribution of these pretrends?
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
// restore


// reg D_l_active_cases testing_regime_change_* t#i.adm12_id i.adm12_id, cluster(t)
//
// matrix B = e(b)
// matrix S = e(V)
//
// clear
// svmat S
// egen i = seq()
// reshape long S, i(i) j(adm0)
// keep if i == adm0
// g se = sqrt(S)
// keep adm0 se
// tempfile f
// save `f'
// clear
// svmat B
// g i = 1
// reshape long B, i(i) j(adm0)
// drop i
// merge 1:1 adm0 using `f', keep(3) nogen
// g min = B -1.96*se
// g max = B +1.96*se
// egen seq =seq()
//
// drop if B==0
//
// hist B, w(0.01) lc(white) fc(navy) name(histo, replace) ylabel(none) ytitle("") xtitle(betas)
//
// g w = 1/se
// *collapse (mean) B = B (sd) sd = B [aw=w]
//
// sort B
// egen X = seq()
//
// g star = (B < 0 & max <0) | (B > 0 & min >0)
//
// tw rspike max min X if star == 0, hor lc(black) lw(thin) ///
// || rspike max min X if star == 1, hor lc(red) lw(thin) ///
// || scatter X B if star == 0 , mc(black) msize(small)  ///
// || scatter X B if star == 1, mc(red) msize(small) ///
// xline(0,lc(black) lp(dash)) name(full, replace) ysize(7) ylabel(none) ytitle("") xtitle(betas)
//
// graph combine histo full, xcomm rows(2) ysize(10)

