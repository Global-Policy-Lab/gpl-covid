foreach ADM in "FRA" "IRN" "KOR" "ITA" "USA" {
	import delim using "results/source_data/indiv/ExtendedDataFigure5_r2_`ADM'.csv", clear
	g adm0 = "`ADM'"
	tempfile f`ADM'
	save `f`ADM''
}

drop if _n > 0

foreach ADM in "FRA" "IRN" "KOR" "ITA" "USA" {
	append using `f`ADM''
}

egen grp = group(adm0)
rename lag_ L
g max = r2 + 1.96*se
g min = r2 - 1.96*se

foreach GRP of num 2/5{
	replace L = L + `GRP'/10 if grp == `GRP'
}

tw connect r2 L if grp == 1, mc(gold) lc(gold) || rspike max min L if grp == 1, lc(gold*.7) ///
|| connect r2 L if grp == 2, mc(maroon) lc(maroon) || rspike max min L if grp == 2, lc(maroon*.7) ///
|| connect r2 L if grp == 3, mc(ebblue) lc(ebblue) || rspike max min L if grp == 3, lc(ebblue*.7) ///
|| connect r2 L if grp == 4, mc(green) lc(green) || rspike max min L if grp == 4, lc(green*.7) ///
|| connect r2 L if grp == 5, mc(black) lc(black) || rspike max min L if grp == 5, lc(black*.7) ///
legend(order(1 3 5 7 9) lab(1 "FRA") lab(3 "IRN") lab(5 "ITA") lab(7 "KOR") lab(9 "USA") rows(1) region(lstyle(none))) ///
xtitle(# fixed lags) ytitle(R-squared, height(10))

outsheet * using "results/source_data/ExtendedDataFigure5_b.csv", replace
graph export results/figures/appendix/fixed_lag/r2.pdf, replace


foreach ADM in "FRA" "IRN" "KOR" "ITA" "USA" {
	import delim using "results/source_data/indiv/ExtendedDataFigure5_fixed_lag_`ADM'.csv", clear
	
	cap rename (at b ll1 ul1) (position beta lower_ci upper_ci)
	g adm0 = "`ADM'"
	tempfile f`ADM'
	save `f`ADM''
}

drop if _n > 0

foreach ADM in "FRA" "IRN" "KOR" "ITA" "USA" {
	append using `f`ADM''
}

g grp = adm0 == "USA"
replace grp = 2 if adm0 == "FRA"
replace grp = 3 if adm0 == "IRN"
replace grp = 4 if adm0 == "ITA"
replace grp = 5 if adm0 == "KOR"

sort grp pos

preserve
	keep if hosp == 1
	drop position
	tempfile hosp
	save `hosp'
restore


drop if hosp == 1
egen seq = seq()
egen pol = seq(), by(policy grp)
replace pol = 0 if pol > 1
g sep = sum(pol)
replace seq = seq + sep * 3

g t = _n
tset t
g sep_adm = D.grp
qui sum seq if adm0 == "FRA" & sep_adm == 1
local yline1 = r(mean) - 2
qui sum seq if adm0 == "IRN" & sep_adm == 1
local yline2 = r(mean) - 2
qui sum seq if adm0 == "ITA" & sep_adm == 1
local yline3 = r(mean) - 2
qui sum seq if adm0 == "KOR" & sep_adm == 1
local yline4 = r(mean) - 2

preserve
	keep if hosp == 0
	keep seq lag policy
	merge 1:1 lag policy using `hosp', nogen
	replace seq = seq - 0.5
	save `hosp', replace
restore


append using `hosp'



tw rspike upper lower seq if hosp != 1 & lag == 0, lc(black) hor lw(thin) ///
|| scatter seq beta if hosp != 1 & lag == 0, mc(black) ///
|| rspike upper lower seq if hosp == 1 & lag == 0, hor lc(black)  lw(vthin) ///
|| scatter seq beta if hosp == 1 & lag == 0, mc(black) m(oh) ///
|| rspike upper lower seq if hosp != 1 & lag == 1, lc(black*.9) hor lw(thin) ///
|| scatter seq beta if hosp != 1 & lag == 1, mc(black*.9) ///
|| rspike upper lower seq if hosp == 1 & lag == 1, hor lc(black*.9)  lw(vthin) ///
|| scatter seq beta if hosp == 1 & lag == 1, mc(black*.9) m(oh) ///
|| rspike upper lower seq if hosp != 1 & lag == 2, lc(black*.7) hor lw(thin) ///
|| scatter seq beta if hosp != 1 & lag == 2, mc(black*.7) ///
|| rspike upper lower seq if hosp == 1 & lag == 2, hor lc(black*.7)  lw(vthin) ///
|| scatter seq beta if hosp == 1 & lag == 2, mc(black*.7) m(oh) ///
|| rspike upper lower seq if hosp != 1 & lag == 3, lc(black*.5) hor lw(thin) ///
|| scatter seq beta if hosp != 1 & lag == 3, mc(black*.5) ///
|| rspike upper lower seq if hosp == 1 & lag == 3, hor lc(black*.5)  lw(vthin) ///
|| scatter seq beta if hosp == 1 & lag == 3, mc(black*.5) m(oh) ///
|| rspike upper lower seq if hosp != 1 & lag == 4, lc(black*.3) hor lw(thin) ///
|| scatter seq beta if hosp != 1 & lag == 4, mc(black*.3) ///
|| rspike upper lower seq if hosp == 1 & lag == 4, hor lc(black*.3)  lw(vthin) ///
|| scatter seq beta if hosp == 1 & lag == 4, mc(black*.3) m(oh) ///
|| rspike upper lower seq if hosp != 1 & lag == 5, lc(black*.1) hor lw(thin) ///
|| scatter seq beta if hosp != 1 & lag == 5, mc(black*.1) ///
|| rspike upper lower seq if hosp == 1 & lag == 5, hor lc(black*.1)  lw(vthin) ///
|| scatter seq beta if hosp == 1 & lag == 5, mc(black*.1) m(oh) ///
yline(`yline1', lc(black) lp(dot)) ///
yline(`yline2', lc(black) lp(dot)) ///
yline(`yline3', lc(black) lp(dot)) ///
yline(`yline4', lc(black) lp(dot)) legend(off) ysize(20) xline(0, lc(black)) 

graph export results/figures/appendix/fixed_lag/fig5_FL.pdf, replace

// output source data for ED fig 5
export excel adm0 policy beta lower upper using "results/source_data/ExtendedDataFigure5_lags.xlsx", sheet("panel_a") firstrow(var) sheetreplace

import delim "results/source_data/indiv/ExtendedDataFigure5_b.csv", clear
rename ïlags lags
export excel using "results/source_data/ExtendedDataFigure5_lags.xlsx", sheet("panel_b") firstrow(var) sheetreplace

import delim "results/source_data/indiv/ExtendedDataFigure5_CHN_event_study.csv", clear
export excel using "results/source_data/ExtendedDataFigure5_lags.xlsx", sheet("panel_c") firstrow(var) sheetreplace

/*
tw rspike upper lower seq if hosp != 1 & adm0 == "USA", xline(0, lc(black)) hor mc(gs10) lw(thin) ///
|| scatter seq beta if hosp != 1 & adm0 == "USA", mc(black)  ///
|| rspike upper lower seq if hosp == 1 & adm0 == "USA", hor mc(ebblue) lw(thin) ///
|| scatter seq beta if hosp == 1 & adm0 == "USA", mc(ebblue)  ///
yline(`yline2', lc(black) lp(dot)) ///
yline(`yline3', lc(black) lp(dot)) ///
yline(`yline4', lc(black) lp(dot)) legend(off)

graph export results/figures/appendix/fixed_lag/fig5_FL_A.pdf, replace


drop if adm0 == "USA"

tw rspike upper lower seq if hosp != 1 & adm0 != "USA", xline(0, lc(black)) ysize(20) hor mc(gs10) lw(thin) ///
|| scatter seq beta if hosp != 1 & adm0 != "USA", mc(black)  ///
|| rspike upper lower seq if hosp == 1 & adm0 != "USA", hor mc(ebblue) lw(thin) ///
|| scatter seq beta if hosp == 1 & adm0 != "USA", mc(ebblue)  ///
yline(`yline2', lc(black) lp(dot)) ///
yline(`yline3', lc(black) lp(dot)) ///
yline(`yline4', lc(black) lp(dot)) legend(off) yscale(range(80(20)220)) xlab(#5)

graph export results/figures/appendix/fixed_lag/fig5_FL_B.pdf, replace
