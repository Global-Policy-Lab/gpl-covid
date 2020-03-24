// Author: Sébastien AP
// Purpose: clean and reshape the raw infected count data

import delim "data/interim/france/adm2_to_adm1.csv", clear 

// Deal with accents and hyphen
foreach ite of num 1/10 {
replace region = subinstr(region, "-", "",1)
replace region = subinstr(region, " ", "",1)
replace region = subinstr(region, "Ã´", "ô",1)
replace region = subinstr(region, "Ã©", "é",1)	
}
rename region adm1_name
rename (num nom) (adm2 departement_name)
replace adm1_name = "Paca" if adm1_name == "ProvenceAlpesCôted'Azur"
replace adm1_name = "Centre" if adm1_name == "CentreValdeLoire"
replace adm1_name = "Réunion" if adm1_name == "LaRéunion"

// save admin2 population & ID
destring adm2, replace force
drop if adm2 ==.
save "data/interim/france/departement_info.dta", replace

keep adm2 adm1_name region_id pop
rename region_id adm1
collapse adm1 (sum) pop, by(adm1_name)
rename pop adm1_pop
replace adm1_name = "IledeFrance" if adm1 == 11
save "data/interim/france/region_ID.dta", replace

* date of the last update file
local m = "3"
local M = "`m'"
if `m' < 10 {
	local M = "0`m'"
}
local d = "13"
local date_file = "2020`M'`d'"

import excel using "data/raw/france/fr-sars-cov-2-`date_file'.xlsx", clear first ///
 sheet("Nombre de cas confir par région")

drop Total X-AI


rename * infected*
rename infectedDate date
// drop duplicate
drop if infectedFrancemétropolitaine == 191

reshape long infected, i(date) j(adm1_name) string
g last_date = mdy(`m',`d',2020)
drop if date > last_date
g adm0_name = "France"

rename infected cumulative_confirmed_cases



preserve
	foreach day of num 14/18{
	import delim "data/raw/france/france_confirmed_cases_by_region_202003`day'.csv", clear
	tempfile f`day'
	save `f`day''
	}
	drop if _n >0 
	foreach day of num 14/18{
		append using `f`day''
	}
	replace cum = . if cum == 0
	// deal with accents
	foreach ite of num 1/10 {
	replace adm1_name = subinstr(adm1_name, "-", "",1)
	replace adm1_name = subinstr(adm1_name, " ", "",1)
	replace adm1_name = subinstr(adm1_name, "Ã´", "ô",1)
	replace adm1_name = subinstr(adm1_name, "Ã©", "é",1)	
	}
	replace adm1_name = "Centre" if adm1_name == "CentreValdeLoire"
	replace adm1_name = "Paca" if adm1_name == "ProvenceAlpesCôtedâAzur"
	replace adm1_name = "Réunion" if adm1_name == "LaRéunion"
	g Date = date(date,"YMD",2000)
	format Date %td
	keep adm* Date cum
	rename Date date 
	g appnd = 1
	tempfile daily_updates
	save `daily_updates'

restore

append using `daily_updates'
//drop totals
drop if adm1_name == "Francemétropolitaine"
drop if adm1_name == "TotalMétropole"
drop if adm1_name == "TotalOutreMer"
drop appnd last_date

merge m:1 adm1_name using "data/interim/france/region_ID.dta", nogen

replace adm1 = 94 if adm1_name == "Corse" 
drop if adm1 == .
sort date adm1

keep if date >= 21960

g cumulative_filled_cases = cumulative_confirmed_cases
levelsof adm1 if adm1 > 10, l(list)

g L_conf = log(cumulative_confirmed)

// impute data for the 2 missing days (feb 29 & mar 1)
foreach adm1 of num `list' {
	reg L_conf date if adm1 == `adm1' & date >= 21972 & date <= 21983
	if e(rss) == 0 {
		replace cumulative_filled = 0 if adm1 == `adm1' & ///
		(date == 21974 | date == 21975)
	}
	else {
	tempvar pred
	predict `pred'
	replace cumulative_filled = floor(exp(`pred')) if adm1 == `adm1' & ///
	(date == 21974 | date == 21975)
	}

}
drop L_conf _*
rename cumulative_f cum_confirmed_cases_imputed
rename cumulative_confirmed_cases cum_confirmed_cases
sort adm1 date
outsheet * using "data/interim/france/france_confirmed_cases_by_region.csv", replace comma
