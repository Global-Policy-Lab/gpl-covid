// Author: Sébastien AP
// Purpose: clean, reshape, and merge the policy data

import delim "data/interim/france/FRA_policy_data_sources.csv", clear 
replace policy = policy + "_opt" if optional == "Y"
keep *_name policy no_gathering_size date_start policy_intensity
g Date = date(date_start,"MDY",2000)
drop date adm0_name
rename Date date
format date %td
rename *_name *
destring adm1, replace force
destring adm2, replace force
destring no_gathering_size, replace force
rename no_gathering_size size //shorten name for reshape

preserve
	keep if adm1 == .
	drop adm1 adm2
	replace size = policy_intensity if size == .
	drop policy_int
	reshape wide size, i(date) j(policy) string
	rename size* *
	foreach var in "no_gathering" "school_closure" "social_distance"{
		rename `var' `var'_national
	}

	g no_gathering_size = no_gathering_national
	replace no_gathering_national = 1 if no_gathering_national != .
	
tempfile national
save `national'
restore
// remove national pol, to be merged further down
drop if adm1 == .
// drop if school_closure_size not clear
drop if policy == "no_gathering" & size == .
drop size
g school_closure_regional = 1 if policy == "school_closure_all"
preserve
	keep if school_closure_regional == 1 | adm2 == .
	g social_distance_opt = 1 if policy == "social_distance_opt"
	drop adm2 policy
	tempfile regional
	drop policy_intensity
	save `regional'
restore

*remove adm1_pol, to be merged further down
drop if school_closure_regional == 1 | adm2 == .
drop school_closure_regional


replace policy = subinstr(policy, "school_closure_", "school_closure-",1)
split policy, p("-")
drop policy

rename (policy1 policy2) (policy running_var)
destring running_var, replace force
merge m:1 adm2 using "data/interim/france/departement_info.dta", keep(3) nogen

*ad hoc population for corse
replace pop = 327283 if adm1 == 94 & adm2 == 2

drop departement_name  region_id
sort adm1 date
collapse policy_intensity (sum) running_var pop, by(date adm1 adm1_name policy)
rename policy pol //shortern variable name before reshape
replace running_var = policy_int if pol != "school_closure"
drop policy_int

reshape wide running_var pop, i(adm1 date) j(pol) string
rename running_var* *_size
rename population* *_popw
merge m:1 adm1 using "data/interim/france/region_ID.dta", nogen keep(1 3)
*ad hoc for region CORSE because of coding issue with the departement (2A and 2B)
replace adm1_pop = 327283 if adm1 == 94
foreach var in "no_gathering_inside" "event_cancel" "school_closure" "social_distance" "home_isolation" {
	replace `var'_popw = `var'_popw / adm1_pop
}

rename *_size *
replace school_closure = 1 if school_closure > 1
tempfile Local
save `Local'

import delim "data/interim/france/france_confirmed_cases_by_region.csv", clear
drop adm1_name
g Date = date(date,"MDY",2020)
drop date
rename Date date
format date %td


merge 1:1 date adm1 using `Local', nogen update
merge m:1 date adm1 using `regional',nogen update
merge m:1 date using `national', nogen update
// adjust _popw variable for place with both national and local intensity
foreach var in "event_cancel" "home_isolation" "no_gathering_inside" "social_distance" {
	replace `var'_popw = `var' + `var'_popw
	replace `var'_popw = `var' if `var'_popw == . & `var' != .
	replace `var'_popw = 1 if `var'_popw > 1 // limit intensity to 1
}

rename no_gathering_national no_gathering
drop adm1_name //reload region name, corrupted accent due to import csv above
merge m:1 adm1 using "data/interim/france/region_ID.dta", keep(1 3) keepusing(adm1_name adm1_pop) nogen update
replace adm1_name = "Corse" if adm1 == 94
replace adm1_pop = 327283 if adm1 == 94



order adm1 adm1_name date cum_c*
sort adm1 date
xtset adm1 date

foreach var in "event_cancel" "event_cancel_popw" "home_isolation" "home_isolation_popw" ///
"no_gathering_inside" "no_gathering_inside_popw" "school_closure" "school_closure_popw" ///
"social_distance" "social_distance_popw" "school_closure_regional" "business_closure" ///
"no_gathering"  "school_closure_national" "social_distance_national" ///
"social_distance_opt" "testing_regime" {
	egen seq = seq(), by(adm1)
	replace `var' = 0 if `var' == . & seq == 1
	drop seq
	bysort adm1: carryforward `var', replace
}

replace no_gathering_size = 0 if no_gathering_size == .
sort adm1 date
by adm1: replace no_gathering_size = sum(no_gathering_size)
replace no_gathering_size = 1000 if no_gathering_size == 6000 // decrease cutoff instead of adding the intensity
replace no_gathering_size = 100 if no_gathering_size == 6100 // decrease cutoff instead of adding the intensity

// ----------------------- merge national and regional measure, adjust for intensity
egen school_closure_local = rowmax(school_closure school_closure_regional school_closure_national) // same policy, aggregate taking max
egen school_closure_local_popw = rowmax(school_closure_popw school_closure_regional school_closure_national) // same policy, aggregate taking max
drop school_closure school_closure_regional school_closure_national school_closure_popw
rename (school_closure_local school_closure_local_popw) (school_closure school_closure_popw)


replace social_distance = (social_distance + social_distance_national)/2 // The national policy is different than regional, so treatment intensity is changing
replace social_distance_popw = (social_distance_popw + social_distance_national)/2
drop social_distance_national

//  ----------------------

*drop oversea regions
drop if adm1 < 10

*save
format date %tdCCYY-NN-DD
rename (adm1_pop adm1) (population adm1_id)
rename *_popw *_popwt
rename hospitalization cum_hospitalized
replace no_gathering_size = 99999 if no_gathering_size==. //to pass github checks
g adm0_name = "FRA"
order adm0_name
outsheet * using "data/processed/adm1/FRA_processed.csv", replace comma
