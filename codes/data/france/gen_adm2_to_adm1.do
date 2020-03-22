// JT
// read and merge departement (adm2) and region (adm1) codes and 
// departement population data for France

// read departement to region id crosswalk
import delim "data/raw/france/departement2019.csv", clear 
keep dep reg
rename (dep reg) (num region_id)

tempfile xwalk
save `xwalk'

// read region name to region id crosswalk
import excel using "data/raw/france/TCRD_004.xls", sheet(REG) clear 
keep A B
rename (A B) (region_id region)
drop if region=="" | region_id=="M" | region_id=="F"
destring region_id, replace

tempfile regionxwalk
save `regionxwalk'

// read in population data by departement
import excel using "data/raw/france/TCRD_004.xls", sheet(DEP) clear 
keep A B C
rename (A B C) (num nom population)
drop if nom==""

// merge on region id and name
merge 1:1 num using `xwalk', nogen
drop if region_id==.
merge m:1 region_id using `regionxwalk', nogen

// save
compress
sort nom
outsheet using "data/interim/france/adm2_to_adm1.csv", comma replace
