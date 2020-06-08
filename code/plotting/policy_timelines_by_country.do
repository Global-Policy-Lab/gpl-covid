// FRA | ADM1 -------------------------------------------------------------------

clear all
set scheme s2color

capture mkdir "results/figures/policy_timelines/fra"

// load data
insheet using data/processed/adm1/FRA_processed.csv, clear 
 
// set up time variables
gen t = date(date, "YMD",2020)
lab var t "date"
format t %td

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

// vertical dash line at 2020-02-29 for start date of sample in models

sort adm1_name t

egen policy_sum = rowtotal(school_closure_popwt pck_social_distance national_lockdown)
sum t if policy_sum>0
// tab date if t==`r(min)' // 2020-02-29 first policy date across US
keep if t>=(`r(min)' - 1) 
keep if t <= date("2020-03-25","YMD") // case data ends 

// for figure legend
tw line school_closure_popwt pck_social_distance national_lockdown t if adm1_name=="IledeFrance", ///
xline(21974, lpattern(shortdash) lcolor(black)) title("IledeFrance") legend(cols(1))
graph export "results/figures/policy_timelines/fra/idf_legend.pdf", replace

// graph policy timeline for each region
levelsof adm1_name, local(region)

foreach adm1 of local region{
	tw line school_closure_popwt pck_social_distance national_lockdown t if adm1_name=="`adm1'", ///
	xline(21974, lpattern(shortdash) lcolor(black)) title("`adm1'", color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21974(5)21999)) xlabel(21974(5)21999, format(%tdMon_DD)) tmtick(##5) name(`adm1', replace)
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

clear all
set scheme s2color

capture mkdir "results/figures/policy_timelines/usa"

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


encode adm1, gen(adm1_id)

// checking that all policy vars are increasing over time
// tsset adm1_id t, daily
// foreach var of varlist p_*{
// 	gen D_`var' = D.`var'
// 	gen D_`var'_neg = D_`var'<0
// }
//
// egen D_p_neg_any = rowtotal(D_p_*_neg)
// br if D_p_neg_any==1


//------------------------ timeline of policies by state

// vertical dash line at 2020-03-03 for start date of sample in models

sort adm1_name t

egen policy_sum = rowtotal(p_*)
sum t if policy_sum>0
// tab date if t==`r(min)' // 2020-02-01 first policy date across US
keep if t>=(`r(min)' - 1) 
keep if t <= date("`end_sample'","YMD") //end date = 2020-04-06

// for figure legend
tw line p_* t if adm1_name=="New York", xline(21977, lpattern(shortdash) lcolor(black)) ///
title("New York") legend(colfirst)
graph export "results/figures/policy_timelines/usa/ny_legend.pdf", replace

// graph policy timeline for each state + DC
forvalues s = 1/51{
	levelsof adm1_name if adm1_id==`s', local(state_name)

	tw line p_* t if adm1_id==`s', xline(21977, lpattern(shortdash) lcolor(black)) ///
	title(`state_name', color(black)) ytitle(Policy Intensity) xtitle("") ///
	ylabel(, angle(horizontal) nogrid) graphregion(color(white)) bgcolor(white) legend(off) ///
	xscale(range(21946(10)22011)) xlabel(21946(10)22011, format(%tdMon_DD)) tmtick(##10) name(state`s', replace)
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


