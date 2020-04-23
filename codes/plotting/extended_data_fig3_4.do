// generate appendix figure - cross validation

foreach ADM in "CHN" "FRA" "IRN" "KOR" "ITA" "USA" {
	import delim using "results/source_data/indiv/ExtendedDataFigure34_cross_valid_`ADM'.csv", clear
	cap g i = ite
	tempfile f`ADM'
	save `f`ADM''
}

drop if _n > 0

foreach ADM in "CHN" "FRA" "IRN" "KOR" "ITA" "USA" {
	append using `f`ADM''
}

drop ite min max se

egen grp = group(adm0)
replace grp = grp - 1
replace grp = 0 if adm0 == "IRN"
replace grp = 2 if adm0 == "CHN"
replace i = i + grp * 11

preserve
foreach pol in "comb. policy" "fifth week (home+t" "first week (home+t" "fourth week (home+" ///
"second week (home+" "third week (home+t" "no_policy rate"{ 
	drop if policy == "`pol'"
}
tw scatter i beta , xline(0, lc(black) lp(dash)) mc(gs10) m(Oh)  msize(large)  ///
|| scatter i beta if sample == "full_sample" , mc(red) m(Oh)  msize(large)  legend(off) ///
ysize(10) 
outsheet * using results/source_data/ExtendedDataFigure4_cross_valid.csv, replace
graph export results/figures/appendix/cross_valid/fig4.pdf, replace

tempfile individual_pol
save `individual_pol'
restore
/*
sort adm0 policy beta

egen min = min(beta), by(grp policy)
g MIN = min == beta
drop min
egen max = max(beta), by(grp policy)
g MAX = max == beta
drop max
br if MIN == 1 | MAX == 1

*/

merge 1:1 i grp adm0 policy sample using `individual_pol', keep(1) nogen
replace grp = 1 if adm0 == "USA"
replace grp = 2 if adm0 == "FRA"
replace grp = 3 if adm0 == "IRN"
replace grp = 4 if adm0 == "ITA"
replace grp = 5 if adm0 == "KOR"
replace grp = 6 if adm0 == "CHN"
egen pol = group(policy)

local pol_i = 100
foreach pol in "fifth week (home+t" "fourth week (home+" ///
 "third week (home+t" "second week (home+" "first week (home+t"{ 
	replace pol = `pol_i' if policy == "`pol'"
	local pol_i = `pol_i' + 1
}

egen seq = group(grp pol)

replace seq = seq + 15 if pol == 5
tw scatter  seq beta if pol == 1 | pol == 5, xline(0, lc(black)) mc(gs10) m(Oh) msize(large) ///
|| scatter seq beta if pol !=1 & pol != 5, m(Oh) msize(large) mc(ebblue) ///
|| scatter  seq beta if sample == "full_sample", m(Oh) msize(large) mc(red) legend(off)
graph export results/figures/appendix/cross_valid/fig3.pdf, replace
outsheet * using results/source_data/ExtendedDataFigure3_cross_valid.csv, replace
