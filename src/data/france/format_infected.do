/*
Author: Sébastien AP
Purpose: clean and reshape the raw infected count data
Date: 3/14/2020

Last update comment:

*/

cd "~/Dropbox/GPL_covid/data/"

import delim "raw/france/adm2_to_adm1.csv", clear 
replace region = subinstr(region, "Ã´", "ô",1)
replace region = subinstr(region, "Ã©", "é",1)
rename region adm1_name
destring num, replace force
rename (num nom) (adm2 departement_name)
replace adm1_name = "Paca" if adm1_name == "Provence-Alpes-Côte d'Azur"
drop if adm2 == .
save "interim/france/departement_info.dta", replace
keep adm2 adm1_name region_id pop
rename region_id adm1
collapse adm1 (sum) pop, by(adm1_name)
rename pop adm1_pop
foreach ite of num 1/10 {
replace adm1_name = subinstr(adm1_name, "-", "",1)
replace adm1_name = subinstr(adm1_name, " ", "",1)
replace adm1_name = subinstr(adm1_name, "Ã´", "ô",1)
replace adm1_name = subinstr(adm1_name, "Ã©", "é",1)	
}
replace adm1_name = "Centre" if adm1_name == "CentreValdeLoire"
replace adm1_name = "Paca" if adm1_name == "ProvenceAlpesCôtedâAzur"
replace adm1_name = "Réunion" if adm1_name == "LaRéunion"
save "interim/france/region_ID.dta", replace

* date of the last update file
local m = "3"
local M = "`m'"
if `m' < 10 {
	local M = "0`m'"
}
local d = "13"
local date_file = "2020`M'`d'"

import excel using "raw/france/fr-sars-cov-2-`date_file'.xlsx", clear first ///
 sheet("Nombre de cas confir par région")

drop Total X-AI


rename * infected*
rename infectedDate date
drop if infectedFrancemétropolitaine == 191



reshape long infected, i(date) j(adm1_name) string
g last_date = mdy(`m',`d',2020)
drop if date > last_date
g adm0_name = "France"

rename infected cumulative_confirmed_cases



preserve
	foreach day of num 14/17{
	import delim "interim/france/france_confirmed_cases_by_region_202003`day'.csv", clear
	tempfile f`day'
	save `f`day''
	}
	drop if _n >0 
	foreach day of num 14/17{
		append using `f`day''
	}
	replace cum = . if cum == 0
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
drop if adm1_name == "Francemétropolitaine"
drop if adm1_name == "TotalMétropole"
drop if adm1_name == "TotalOutreMer"
drop appnd last_date

merge m:1 adm1_name using "interim/france/region_ID.dta"
replace adm1 = 94 if adm1_name == "Corse" 
drop if adm1 == .
sort date adm1
drop _m
keep if date >= 21960

g cumulative_filled_cases = cumulative_confirmed_cases
levelsof adm1 if adm1 > 10, l(list)

/*
play with date to get the aggregate number to match the national report 
(100 and 130 cases on Feb 29 and Mar 1st, respectively)
*/
g L_conf = log(cumulative_confirmed)

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

outsheet * using "interim/france/france_confirmed_cases_by_region.csv", replace comma
