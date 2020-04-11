// Author: Sébastien AP
// Purpose: clean and reshape the raw infected count data

//Load data
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
drop if adm2 == .
save "data/interim/france/departement_info.dta", replace
keep adm2 adm1_name region_id pop
rename region_id adm1
collapse adm1 (sum) pop, by(adm1_name)
rename pop adm1_pop
replace adm1_name = "IledeFrance" if adm1 == 11
g adm0_name = "France"
save "data/interim/france/region_ID.dta", replace




import excel using "data/raw/france/fr-sars-cov-2-20200312.xlsx", clear first ///
 sheet("Nombre de cas confir par région")

drop Total X
rename * infected*
rename infectedDate date

drop if date == 21983 | date == 21987 // missing data, added later in script
// drop duplicate
drop if infectedFrancemétropolitaine == 191

reshape long infected, i(date) j(adm1_name) string
g last_date = mdy(03,13,2020)
drop if date > last_date
g adm0_name = "France"
rename infected cumulative_confirmed_cases

// merge scraped and manually filled data
preserve
	// data for march 9 found on regional websites
	import delim "data/raw/france/france_confirmed_cases_by_region_20200309.csv", clear
	keep adm1 date adm0 cumulative
	tempfile f0
	save `f0'
	//iterate for each day after march 13 until last available date
	local D = mdy(3,13,2020)
	while `D' <= 10e5 {
		local month_file = month(`D')
		local day_file = day(`D')
		if `month_file' < 10 {
			local month_file = "0`month_file'"
		}
		if `day_file' < 10 {
			local day_file = "0`day_file'"
		}		
		cap import delim "data/raw/france/france_confirmed_cases_by_region_2020`month_file'`day_file'.csv", clear
		if _rc == 601 {
			continue, break
		}
		drop if cumulative == .
		keep adm1 date adm0 cumulative
		tempfile f`D'
		save `f`D''
		local D = `D' + 1
	}
	use `f0', clear 
	local D = mdy(3,13,2020)
	while `D' <= 10e5{
		cap append using `f`D''
		if _rc == 198 {
			continue, break
		}
		local D = `D' + 1
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
drop L_conf _* appnd last_date

rename cumulative_f cum_confirmed_cases_imputed
rename cumulative_confirmed_cases cum_confirmed_cases
sort adm1 date

// add hospitalization for robustness check
preserve
	import delim using "data/raw/france/sursaud-covid19-quotidien-2020-04-07-19h00-region.csv", clear 
	keep if sursaud_ == "0"
	g t = date(date,"YMD",2020)
	keep nbre_hospit_corona reg t
	format t %td
	sort reg t
	by reg: g hospitalization = sum(nbre)
	rename (reg t) (adm1 date)
	drop nbre
	tempfile hospi
	save `hospi'
restore
merge 1:1 date adm1 using `hospi', nogen
merge m:1 adm1 using "data/interim/france/region_ID.dta", update replace nogen
replace adm1_name = "Corse" if adm1 == 94

outsheet * using "data/interim/france/france_confirmed_cases_by_region.csv", replace comma
