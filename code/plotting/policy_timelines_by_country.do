// USA | adm1

clear all
set scheme s1color

capture mkdir "results/figures/policy_timelines/usa"

// load data
insheet using data/processed/adm1/USA_processed.csv, clear 

// set up time variables
gen t = date(date, "YMD",2020)
lab var t "date"
format t %td

//------------------grouping treatments (based on timing and similarity)

// popwt vars = policy intensity * population weight of respective admin 2 unit or sub admin 2 unit

// emergency_declaration on for entire sample

gen p_1 = (event_cancel_popwt + no_gathering_popwt) / 2
gen p_2 = (social_distance_popwt + religious_closure_popwt) / 2 //the 2 religious_closure policies happen on same day as social_distance policies in respective state
gen p_3 = pos_cases_quarantine_popwt 
gen p_4 = paid_sick_leave_popwt
gen p_5 = work_from_home_popwt
gen p_6 = school_closure_popwt
gen p_7 = (travel_ban_local_popwt + transit_suspension_popwt) / 2 
gen p_8 = business_closure_popwt
gen p_9 = home_isolation_popwt

lab var p_1 "No gathering, event cancel"
lab var p_2 "Social distance"
lab var p_3 "Quarantine positive cases" 
lab var p_4 "Paid sick leave"
lab var p_5 "Work from home"
lab var p_6 "School closure"
lab var p_7 "Travel ban"
lab var p_8 "Business closure"
lab var p_9 "Home isolation" 

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


//--------------------------------------------------------------------------------

// timeline of policies by state
// vertical dash line at 2020-03-03 for start date of sample in models

sort adm1_name t

egen policy_sum = rowtotal(p_*)
sum t if policy_sum>0
tab date if t==21946 // 2020-02-01 first policy date across US
drop if t<21945
drop if t>22011 //end date = 2020-04-06

by adm1_name: egen first_policy_date = min(t) if policy_sum>0
format first_policy_date %td

cap set scheme covid19_w_legend // optional scheme for graphs
tw line p_* t if adm1_name=="New York", xline(21977, lpattern(shortdash) lcolor(black)) title("New York")
graph export "results/figures/policy_timelines/usa/ny_legend.pdf", replace

cap set scheme covid19_fig3 // optional scheme for graphs

forvalues s = 1/51{
	levelsof adm1_name if adm1_id==`s', local(state_name)

	tw line p_* t if adm1_id==`s', xline(21977, lpattern(shortdash) lcolor(black)) ///
	title(`state_name') ytitle(Policy Intensity) xtitle("") ///
	xscale(range(21946(10)22011)) xlabel(21946(10)22011, format(%tdMon_DD)) name(state`s', replace)
}

forvalues s = 1(6)48{
	local _2 = `s' + 1
	local _3 = `s' + 2
	local _4 = `s' + 3
	local _5 = `s' + 4
	local _6 = `s' + 5
	
	graph combine state`s' state`_2' state`_3' state`_4' state`_5' state`_6', cols(1) ysize(11) xsize(4) imargin(tiny) 
	graph export "results/figures/policy_timelines/usa/states`s'_`_6'.pdf", replace
}

graph combine state49 state50 state51 state51 state51 state51, cols(1) ysize(11) xsize(4) imargin(tiny) 
graph export "results/figures/policy_timelines/usa/states49_51.pdf", replace


