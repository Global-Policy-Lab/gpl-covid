// generate appendix figure - cross validation

foreach ADM in "CHN" "FRA" "IRN" "KOR" "ITA" "USA" {
	import delim using "results/source_data/indiv/ExtendedDataFigure7_cross_valid_`ADM'.csv", clear
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

tw scatter i beta if policy != "comb. policy", xline(0, lc(black) lp(dash)) mc(gs10) m(Oh) ///
|| scatter i beta if sample == "full_sample" & policy != "comb. policy", mc(red) m(Oh) legend(off) ///
ysize(10) 


graph export results/figures/appendix/cross_valid/fig6.pdf, replace

// ouput source data for ED fig 6
outsheet adm0 sample policy beta using "results/source_data/ExtendedDataFigure7_cross_valid.csv", comma replace


sort adm0 policy beta

egen min = min(beta), by(grp policy)
g MIN = min == beta
drop min
egen max = max(beta), by(grp policy)
g MAX = max == beta
drop max
br if MIN == 1 | MAX == 1
