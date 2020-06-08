capture mkdir "results/figures/policy_timelines/"

// CHN | ADM2 -------------------------------------------------------------------

capture mkdir "results/figures/policy_timelines/chn"
clear all

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag=="CHN_analysis"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm2/CHN_processed.csv, clear 

// set up time variables
gen t = date(date, "YMD")
lab var t "date"

// sample date range
keep if t >= mdy(1,16,2020) // start date
keep if t <= date("`end_sample'","YMD") // cutoff date to ensure we are not looking at effects of lifting policy

// use this to identify cities, some have same names but different provinces
capture: drop adm2_id
encode adm2_name, gen(adm2_id)
encode adm1_name, gen(adm1_id)
gen adm12_id = adm1_id*1000+adm2_id
lab var adm12_id "Unique city identifier"
duplicates report adm12_id t

// set up panel
tsset adm12_id t, daily

//------------------clean

// grab province-level population totals
preserve
contract adm1_name adm2_name population
collapse (sum) population_adm1 = population, by(adm1_name)

tempfile adm1_pop
save `adm1_pop'
restore

// drop obs in two cities that lifted local travel ban before 3/5
tab adm2_name t if D.travel_ban_local==-1
bysort adm12_id: egen travel_ban_local_lift = min(t) if D.travel_ban_local==-1
bysort adm12_id: egen travel_ban_local_lift_cut = min(travel_ban_local_lift)

drop if travel_ban_local_lift_cut!=. & t>=travel_ban_local_lift_cut
drop travel_ban_local_lift travel_ban_local_lift_cut

// drop cities if they never report when policies are implemented (e.g. could not find due to news censorship)
bysort adm12_id : egen ever_policy1 = max(home_isolation) 
bysort adm12_id : egen ever_policy2 = max(travel_ban_local) 
gen ever_policy = ever_policy1 + ever_policy2 // only keeping 115 cities where we find at least one of travel ban or home iso b/c unlikely that the rest of cities did not implement
keep if ever_policy > 0

//------------------create population weighted policy "intensity" by province

// total population treated by policy at city-level
foreach policy in emergency_declaration travel_ban_local home_isolation{
	gen `policy'_pop = `policy' * population
}
// sum to province-level by day
collapse (sum) *_pop, by(adm1_name date t)

// add province-level population totals
merge m:1 adm1_name using `adm1_pop', nogen keep(3)
// do not have policy data for 5 province: Macao, Qinghai, Shanxi, Xinjiang, Xizang


// calc % of population treated by policy at province-level
foreach policy in emergency_declaration travel_ban_local home_isolation{
	gen `policy'_popwt = `policy'_pop / population_adm1
}

lab var emergency_declaration_popwt "Emergency declaration"
lab var travel_ban_local_popwt "Travel ban"
lab var home_isolation_popwt "Home isolation"

//------------------------ timeline of policies by province

// for figure legend
tw line *_popwt t if adm1_name=="Hubei", title("Hubei") legend(cols(1)) scheme(s2color)
graph export "results/figures/policy_timelines/chn/hubei_legend.pdf", replace

// graph policy timeline for each province
levelsof adm1_name, local(region)
local i = 1
foreach adm1 of local region{
	tw line *_popwt t if adm1_name=="`adm1'", ///
	title("`adm1'", color(black)) ytitle(Policy Intensity) xtitle("") ///
	yscale(r(0(.2)1)) ylabel(0(.2)1, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21930(7)21979)) xlabel(21930(7)21979, format(%tdMon_DD)) tmtick(##7) scheme(s2color) name(g`i', replace)
	local i = `i' + 1
}

foreach j of num 1(5)25{
	local k = `j' + 1
	local l = `j' + 2
	local m = `j' + 3
	local n = `j' + 4
	graph combine g`j' g`k' g`l' g`m' g`n', ///
	cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
	graph export "results/figures/policy_timelines/chn/reg`j'_`n'.pdf", replace
}
graph combine g26 g27 g27 g27 g27, cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
graph export "results/figures/policy_timelines/chn/reg26_27.pdf", replace


// KOR | ADM1 -------------------------------------------------------------------

capture mkdir "results/figures/policy_timelines/kor"
clear all

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/KOR_processed.csv, clear 

// set up time variables
gen t = date(date, "YMD")
lab var t "date"

// set up panel
capture: drop adm2_id
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// sample date range
keep if t >= mdy(2,17,2020) // start date
keep if t <= date("`end_sample'","YMD") // to match other country end dates

//------------------grouping treatments (based on timing and similarity)

gen p_1 = (no_demonstration + religious_closure + welfare_services_closure) / 3
gen p_2 = (business_closure_opt + work_from_home_opt + social_distance_opt + no_gathering_opt) / 4
gen p_3 = emergency_declaration
gen p_4 = pos_cases_quarantine

lab var p_1 "Religious & welfare closure, no demonstration"
lab var p_2 "Work from home, business closure, other social distance (opt)"
lab var p_3 "Emergency declaration"
lab var p_4 "Quarantine inbound travelers"

//------------------------ timeline of policies by province

// for figure legend
tw line p_* t if adm1_name=="Busan", title("Busan") legend(cols(1)) scheme(s2color)
graph export "results/figures/policy_timelines/kor/busan_legend.pdf", replace

// graph policy timeline for each province
levelsof adm1_name, local(region)
local i = 1
foreach adm1 of local region{
	tw line p_* t if adm1_name=="`adm1'", ///
	title("`adm1'", color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21962(6)22011)) xlabel(21962(6)22011, format(%tdMon_DD)) tmtick(##6) scheme(s2color) name(g`i', replace)
	local i = `i' + 1
}

foreach j of num 1(5)15{
	local k = `j' + 1
	local l = `j' + 2
	local m = `j' + 3
	local n = `j' + 4
	graph combine g`j' g`k' g`l' g`m' g`n', ///
	cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
	graph export "results/figures/policy_timelines/kor/reg`j'_`n'.pdf", replace
}

graph combine g16 g17 g17 g17 g17, ///
cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white))
graph export "results/figures/policy_timelines/kor/reg16_17.pdf", replace


// ITA | adm1 -------------------------------------------------------------------

capture mkdir "results/figures/policy_timelines/ita"
clear all

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/ITA_processed.csv, clear 
// NOTE: using adm1 level data for policy timelines instead of adm2 b/c there are 107 adm2 units

// set up time variables
gen t = date(date, "YMD")
lab var t "date"

// set up panel
drop adm1_id
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// sample date range
keep if t >= mdy(2,26,2020) // start date
keep if t <= date("`end_sample'","YMD") // cutoff date to ensure we are not looking at effects of lifting policy

//------------------grouping treatments (based on timing and similarity)

// popwt vars = policy intensity * population weight of respective admin 1 unit or sub admin 1 unit

// combine optional policies with respective mandatory policies
// weighing optional policies by 1/2
gen social_distance_comb_popwt = social_distance_popwt + social_distance_opt_popwt * 0.5 
gen work_from_home_comb_popwt = work_from_home_popwt + work_from_home_opt_popwt * 0.5

gen p_1 = school_closure_popwt  
gen p_2 = pos_cases_quarantine_popwt 
gen p_3 = (no_gathering_popwt + social_distance_comb_popwt + work_from_home_comb_popwt)/3
gen p_4 = (travel_ban_local_popwt + transit_suspension_popwt)/2 
gen p_5 = business_closure_popwt
gen p_6 = home_isolation_popwt  

lab var p_1 "School closure"
lab var p_2 "Quarantine positive cases"
lab var p_3 "Work from home, no gathering, other social distance"
lab var p_4 "Travel ban, transit suspension"
lab var p_5 "Business closure"
lab var p_6 "Home isolation"

//------------------------ timeline of policies by region

// for figure legend
tw line p_* t if adm1_name=="Lombardia", title("Lombardia") legend(cols(1)) scheme(s2color)
graph export "results/figures/policy_timelines/ita/lombardy_legend.pdf", replace

// graph policy timeline for each region
levelsof adm1_name, local(region)
local i = 1
foreach adm1 of local region{
	tw line p_* t if adm1_name=="`adm1'", ///
	title("`adm1'", color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21971(5)22011)) xlabel(21971(5)22011, format(%tdMon_DD)) tmtick(##5) scheme(s2color) name(g`i', replace)
	local i = `i' + 1
}

foreach j of num 1(6)18{
	local k = `j' + 1
	local l = `j' + 2
	local m = `j' + 3
	local n = `j' + 4
	local o = `j' + 5
	graph combine g`j' g`k' g`l' g`m' g`n' g`o', ///
	cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
	graph export "results/figures/policy_timelines/ita/reg`j'_`o'.pdf", replace
}
graph combine g19 g20 g21 g21 g21 g21, cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
graph export "results/figures/policy_timelines/ita/reg19_21.pdf", replace


// IRN | adm1 -------------------------------------------------------------------

capture mkdir "results/figures/policy_timelines/irn"
clear all

// load data
insheet using data/processed/adm1/IRN_processed.csv, clear 

// set up time variables
gen t = date(date, "YMD")
lab var t "date"
format t %td

// set up panel
encode adm1_name, gen(adm1_id)
tsset adm1_id t, daily

// sample date range
keep if t >= mdy(2,27,2020) // start date
keep if t <= date("2020-03-22","YMD") // case data ends 

//------------------grouping treatments (based on timing and similarity)

// create national opt travel ban var for all provinces except for Qom
gen travel_ban_local_opt_natl = travel_ban_local_opt
	replace travel_ban_local_opt_natl = 0 if adm1_name=="Qom"

// create national school_closure var for provinces that close schools on 3/5
by adm1_id: egen school_closure_natl0 = min(school_closure) 
gen school_closure_natl = school_closure if school_closure_natl0==0
	replace school_closure_natl = 0 if school_closure_natl==.
drop school_closure_natl0
	
	
gen p_1 = (travel_ban_local_opt_natl + work_from_home + school_closure_natl)/3
lab var p_1 "Travel ban (opt), work from home, school closure"

gen p_2 = home_isolation
lab var p_2 "Home isolation"

//------------------------ timeline of policies by province

// for figure legend
tw line p_* t if adm1_name=="Qom", title("Qom") legend(cols(1)) scheme(s2color)
graph export "results/figures/policy_timelines/irn/qom_legend.pdf", replace

// graph policy timeline for each province
levelsof adm1_name, local(region)
local i = 1
foreach adm1 of local region{
	tw line p_* t if adm1_name=="`adm1'", ///
	title("`adm1'", color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21972(4)21996)) xlabel(21972(4)21996, format(%tdMon_DD)) tmtick(##4) scheme(s2color) name(g`i', replace)
	local i = `i' + 1
}

foreach j of num 1(5)30{
	local k = `j' + 1
	local l = `j' + 2
	local m = `j' + 3
	local n = `j' + 4
	graph combine g`j' g`k' g`l' g`m' g`n', ///
	cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
	graph export "results/figures/policy_timelines/irn/reg`j'_`n'.pdf", replace
}
graph combine g31 g31 g31 g31 g31, cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
graph export "results/figures/policy_timelines/irn/reg31.pdf", replace






// FRA | ADM1 -------------------------------------------------------------------

capture mkdir "results/figures/policy_timelines/fra"
clear all

// load data
insheet using data/processed/adm1/FRA_processed.csv, clear 
 
// set up time variables
gen t = date(date, "YMD",2020)
lab var t "date"
format t %td

sort adm1_name t

// sample date range
keep if t >= date("2020-02-29","YMD") // start date
keep if t <= date("2020-03-25","YMD") // case data ends 

//------------------generate policy packages

lab var school_closure_popwt "School closure"

gen no_gathering_5000 = no_gathering_size <= 5000 
gen no_gathering_1000 = no_gathering_size <= 1000 
gen no_gathering_100 = no_gathering_size <= 100

gen pck_social_distance = (no_gathering_1000 + no_gathering_100 + event_cancel_popw + no_gathering_inside_popw + social_distance_popw) / 5
lab var pck_social_distance "Cancel events, no gathering, other social distance"

gen national_lockdown = (business_closure + home_isolation_popw) / 2 // big national lockdown policy
lab var national_lockdown "Business closure, home isolation"

//------------------------ timeline of policies by region

// for figure legend
tw line school_closure_popwt pck_social_distance national_lockdown t if adm1_name=="IledeFrance", ///
title("IledeFrance") legend(cols(1)) scheme(s2color)
graph export "results/figures/policy_timelines/fra/idf_legend.pdf", replace

// graph policy timeline for each region
levelsof adm1_name, local(region)
foreach adm1 of local region{
	tw line school_closure_popwt pck_social_distance national_lockdown t if adm1_name=="`adm1'", ///
	title("`adm1'", color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21974(4)21999)) xlabel(21974(4)21999, format(%tdMon_DD)) tmtick(##4) scheme(s2color) name(`adm1', replace)
}

graph combine IledeFrance Centre BourgogneFrancheComté Normandie HautsdeFrance, ///
cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
graph export "results/figures/policy_timelines/fra/reg1_5.pdf", replace

graph combine GrandEst PaysdelaLoire Bretagne NouvelleAquitaine Occitanie, ///
cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
graph export "results/figures/policy_timelines/fra/reg6_10.pdf", replace

graph combine AuvergneRhôneAlpes Paca Corse Corse Corse, ///
cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white))
graph export "results/figures/policy_timelines/fra/reg11_13.pdf", replace


 
// USA | adm1 -------------------------------------------------------------------

capture mkdir "results/figures/policy_timelines/usa"
clear all

// import end of sample cut-off 
import delim using code/data/cutoff_dates.csv, clear 
keep if tag == "default"
local end_sample = end_date[1]

// load data
insheet using data/processed/adm1/USA_processed.csv, clear 

// set up time variables
gen t = date(date, "YMD",2020)
lab var t "date"
format t %td

// set up panel
encode adm1, gen(adm1_id)
tsset adm1_id t, daily

// sample date range
keep if t >= mdy(3,3,2020) // start date
keep if t <= date("`end_sample'","YMD") //end date = 2020-04-06

//------------------grouping treatments (based on timing and similarity)

// popwt vars = policy intensity * population weight of respective admin 2 unit or sub admin 2 unit

gen p_1 = federal_guidelines
gen p_2 = social_distance_popwt 
gen p_3 = paid_sick_leave_popwt
gen p_4 = pos_cases_quarantine_popwt 
gen p_5 = (travel_ban_local_popwt + transit_suspension_popwt) / 2 
gen p_6 = school_closure_popwt
gen p_7 = religious_closure_popwt
gen p_8 = work_from_home_popwt
gen p_9 = no_gathering_popwt
gen p_10 = business_closure_popwt
gen p_11 = home_isolation_popwt

lab var p_1 "Slow the Spread Guidelines" 
lab var p_2 "Other social distance"
lab var p_3 "Paid sick leave"
lab var p_4 "Quarantine positive cases" 
lab var p_5 "Travel ban, transit suspension"
lab var p_6 "School closure"
lab var p_7 "Religious closure" 
lab var p_8 "Work from home"
lab var p_9 "No gathering"
lab var p_10 "Business closure"
lab var p_11 "Home isolation" 

//------------------------ timeline of policies by state

// for figure legend
tw line p_* t if adm1_name=="New York", title("New York") legend(colfirst) scheme(s2color)
graph export "results/figures/policy_timelines/usa/ny_legend.pdf", replace

// graph policy timeline for each state + DC
forvalues s = 1/51{
	levelsof adm1_name if adm1_id==`s', local(state_name)

	tw line p_* t if adm1_id==`s', ///
	title(`state_name', color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21977(4)22011)) xlabel(21977(4)22011, format(%tdMon_DD)) tmtick(##4) scheme(s2color) name(state`s', replace)
}

forvalues s = 1(6)48{
	local _2 = `s' + 1
	local _3 = `s' + 2
	local _4 = `s' + 3
	local _5 = `s' + 4
	local _6 = `s' + 5
	
	graph combine state`s' state`_2' state`_3' state`_4' state`_5' state`_6', ///
	cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white)) 
	graph export "results/figures/policy_timelines/usa/states`s'_`_6'.pdf", replace
}

graph combine state49 state50 state51 state51 state51 state51, ///
cols(1) ysize(11) xsize(4) imargin(tiny) graphregion(color(white))
graph export "results/figures/policy_timelines/usa/states49_51.pdf", replace


