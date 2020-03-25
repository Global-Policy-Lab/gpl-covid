// Author: Sébastien AP
// Purpose: clean, reshape, and merge the policy data 

import delim "data/raw/france/france_policy_static_20200319.csv", clear 
drop if minor == 1
keep adm0-policy_cat
g Date = date(date,"MDY",2000)
drop date
rename Date date
format date %td

preserve
	keep if adm1 == .
	drop adm1 adm2
	replace policy = subinstr(policy,"no_gathering_", "no_gathering-",1)
	split policy, p("-")
	drop policy_category
	rename (policy_category1 policy_category2) (policy_category size)
	destring size, replace
	replace size = 1 if size == .
	reshape wide size, i(date adm0) j(policy_category) string
	rename size* *

	foreach var in "no_gathering" "school_closure" "social_distance"{
		replace `var' = 0 if `var' == .
		rename `var' `var'_national
	}
	replace business_closure = 0 if business_closure == .
	replace home_isolation = 0 if home_isolation == .
	replace paid_sick_leave = 0 if paid_sick_leave == .
	g no_gathering_national_size = no_gathering
	replace no_gathering_national = 1 if no_gathering_national > 0
tempfile national
save `national'

restore
*remove national pol
drop if adm1 == .


g school_closure_regional = policy_category == "school_closure_all"
preserve
	keep if school_closure_regional == 1 | adm2 == .
	g social_distance_regional = policy_cat == "social_distance"
	drop adm2 policy
	tempfile regional
	save `regional'
restore
*remove adm1_pol

drop if school_closure_regional == 1 | adm2 == .
drop school_closure_regional

replace policy_category = subinstr(policy_category, "no_gathering_", "no_gathering-",1)
replace policy_category = subinstr(policy_category, "school_closure_", "school_closure-",1)
split policy_category, p("-") 

drop policy_category
rename (policy_category1 policy_category2) (policy_category running_var)
destring running_var, replace force
merge m:1 adm2 using "data/interim/france/departement_info.dta", keep(3) nogen
tab adm1_name
*ad hoc for corse

replace pop = 327283 if adm1 == 94 & adm2 == 2

drop departement_name  region_id
sort adm1 date

collapse (sum) running_var pop, by(date adm0 adm1 adm1_name policy_cat)
rename policy_cat pol
reshape wide running_var pop, i(adm0 adm1 date) j(pol) string
rename running_var* *_size
rename population* *_popw
merge m:1 adm1 using "data/interim/france/region_ID.dta", nogen keep(1 3)

*ad hoc for region CORSE because of coding issue with the departement (2A and 2B)
replace adm1_pop = 327283 if adm1 == 94

foreach var in "event_cancel" "no_gathering" "school_closure" "social_distance" {
	replace `var'_size = 1 if `var'_size == 0
	replace `var'_size = 0 if `var'_size == .
	replace `var'_popw = 0 if `var'_popw == .
	replace `var'_popw = `var'_popw / adm1_pop
	g `var' = `var'_size > 0
}

drop if no_gathering_size == 1

tempfile Local
save `Local'

import delim "data/interim/france/france_confirmed_cases_by_region.csv", clear
drop adm1_name
rename adm0_name adm0
g Date = date(date,"MDY",2020)
drop date
rename Date date
format date %td
merge 1:1 date adm1 using `Local', nogen
merge m:1 date adm1 using `regional',nogen
merge m:1 date adm0 using `national', nogen
drop adm1_name //reload region name, corrupted accent due to import csv above
merge m:1 adm1 using "data/interim/france/region_ID.dta", keep(1 3) keepusing(adm1_name adm1_pop) nogen update
replace adm1_name = "Corse" if adm1 == 94
replace adm1_pop = 327283 if adm1 == 94

rename adm0 adm0_name
order adm0_name adm1 adm1_name date cum_c* event_cancel ///
event_cancel_size no_gathering no_gathering_size ///
no_gathering_national no_gathering_national_size ///
school_closure school_closure_size school_closure_regional school_closure_national ///
social_distance social_distance_size 

sort adm1 date


*change no_gathering_national for multiple dummies with different cut-off
g no_gathering_national_5000 = 1 if no_gathering_national_size == 5000
g no_gathering_national_1000 = 1 if no_gathering_national_size == 1000
g no_gathering_national_100 = 1 if no_gathering_national_size == 100
drop no_gathering_national no_gathering_national_size



foreach var in "event_cancel" "event_cancel_popw" "business_closure" "home_isolation" ///
"event_cancel_size" "no_gathering" "no_gathering_popw" "no_gathering_size" ///
"no_gathering_national_5000" "no_gathering_national_1000" "paid_sick_leave" ///
"no_gathering_national_100" "school_closure" "school_closure_popw" "school_closure_size" ///
"school_closure_regional" "school_closure_national" "social_distance" "social_distance_popw" ///
"social_distance_size" "social_distance_national" "social_distance_regional" {
	replace `var' = 0 if `var' == .

	sort adm1 date
	by adm1: replace `var' = sum(`var')
}

*keep dummy equals to 1 even if the policy is reinforced

foreach var in "event_cancel" "event_cancel_popw" "business_closure" "home_isolation" ///
"event_cancel_size" "no_gathering" "no_gathering_popw" "no_gathering_size" ///
"no_gathering_national_5000" "no_gathering_national_1000" "paid_sick_leave" ///
"no_gathering_national_100" "school_closure" "school_closure_popw" "school_closure_size" ///
"school_closure_regional" "school_closure_national" "social_distance" "social_distance_popw" ///
"social_distance_size" "social_distance_national" "social_distance_regional" {
	replace `var' = 1 if `var' > 1
}

*drop oversea regions for now
drop if adm1 < 10
*save
format date %tdCCYY-NN-DD
rename adm1_pop population
outsheet * using "data/processed/adm1/FRA_processed.csv", replace comma


