// generate appendix figure - cross validation

foreach ADM in "ITA" "CHN" "FRA" "IRN" "KOR" "USA"  {
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
g grp = 0
replace grp = 1 if adm0 == "FRA"
replace grp = 2 if adm0 == "IRN"
replace grp = 3 if adm0 == "ITA"
replace grp = 4 if adm0 == "KOR"
replace grp = 5 if adm0 == "CHN"
replace i = i*3 + grp * 50

sort i
egen Y = group(i)
g t = _n
tsset t
g sep = D.grp
g sep_line = (Y[_n-1] + Y)*.5 if sep == 1
local i = 1
foreach adm0 in "FRA" "IRN" "ITA" "KOR" "CHN" {
	qui sum sep_line if sep == 1 & adm0 == "`adm0'"
	local line`i' = r(mean) 
	local i = `i' + 1
}
drop sep* t

preserve
foreach pol in "comb. policy" "fifth week (home+t" "first week (home+t" "fourth week (home+" ///
"second week (home+" "third week (home+t" "no_policy rate"{ 
	drop if policy == "`pol'"
}
tw scatter Y beta if sample != "full_sample", xline(0, lc(black)) mc(gs10) m(Oh)  msize(large)  ///
|| scatter Y beta if sample == "full_sample" , mc(red) m(Oh)  msize(large)  legend(off) ///
ysize(12) yline(`line1', lc(black) lw(vthin)) ///
yline(`line2', lc(black) lw(vthin)) ///
yline(`line3', lc(black) lw(vthin)) ///
yline(`line4', lc(black) lw(vthin)) ///
yline(`line5', lc(black) lw(vthin))
outsheet * using results/source_data/ExtendedDataFigure4_cross_valid.csv, replace
graph export results/figures/appendix/cross_valid/fig4.pdf, replace


tw scatter Y beta if sample != "full_sample", xline(0, lc(black)) mc(gs10) m(Oh)  msize(large)  ///
legend(off) ysize(12) yline(`line1', lc(black) lw(vthin)) ///
yline(`line2', lc(black) lw(vthin)) ///
yline(`line3', lc(black) lw(vthin)) ///
yline(`line4', lc(black) lw(vthin)) ///
yline(`line5', lc(black) lw(vthin)) xscale(range(-.6(0.2)0.2))  xlabel(-.6(0.2)0.2)
graph export results/figures/appendix/cross_valid/fig4_layer0.pdf, replace


tw scatter Y beta if sample == "full_sample" , mc(red) m(Oh)  msize(large)  legend(off) ///
ysize(12) yline(`line1', lc(black) lw(vthin)) ///
yline(`line2', lc(black) lw(vthin)) ///
yline(`line3', lc(black) lw(vthin)) ///
yline(`line4', lc(black) lw(vthin)) ///
yline(`line5', lc(black) lw(vthin)) xscale(range(-.6(0.2)0.2))  xlabel(-.6(0.2)0.2)
graph export results/figures/appendix/cross_valid/fig4_layer1.pdf, replace

tempfile individual_pol
save `individual_pol'
restore
/*
sort adm0 policy beta

egen min = min(beta), by(grp i)
g MIN = min == beta
drop min
egen max = max(beta), by(grp i)
g MAX = max == beta
drop max
sort grp MIN i
br if MIN == 1 | MAX == 1
br
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

