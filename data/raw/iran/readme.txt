Iran Covid-19 Data Acquisition and Cleaning

A. Hultgren
hultgren@berkeley.edu
3/17/20


* -------------------------------------------
* Covid-19 cases and deaths
* -------------------------------------------

A) Data collection

Iran announces its new Covid-19 confirmed cases by adm2 unit each day on the Ministry of Health website as a list. These data are compiled each day on a Wikipedia page tracking the outbreak in Iran, in a table "New COVID-19 cases in Iran by province" (https://en.wikipedia.org/wiki/2020_coronavirus_pandemic_in_Iran, accessed 3/16/20).  The data in this table were spot checked against the Ministry of Health announcements using a mix of Google Translate and direct comparison* of the Persian numbers. 

Example Ministry of Health data (accessed 3/14/20)
http://behdasht.gov.ir/index.jsp?siteid=1&fkeyid=&siteid=1&pageid=54782&newsview=200716


*Google Translate sometimes translates various Persian numbers as "1". Persian numbers compared here: https://www.languagesandnumbers.com/how-to-count-in-persian/en/fas/


B) Data cleaning procedure

The following is a step-by-step procedure to clean the Iran coronavirus data.

1) Copy all of the date lines from the "New COVID-19 cases in Iran by province" table on the Wikipedia page tracking this outbreak in Iran.(https://en.wikipedia.org/wiki/2020_coronavirus_pandemic_in_Iran)

2) Open the excel file <covid_iran_cases.xlsx>  This file contains the first step cleaning template for the cases data, as well as the information on key policy actions taken by the Iranian government. The tabs in this file are:

-- <200314_cases_raw> :  A template into which raw data from the Wikipedia table -- see (1) above -- should be pasted.
-- <cases_cleaned--to_csv> :  A cleaned column format for the intermediate cases data. Simply extend the formulas (by copy/paste) in each row so that each row of the raw data is included. Do not change the column headings. Once all raw data has been included, save this tab as a .csv as "intermediate/covid_iran_cases.csv"
-- <200314_policies--to_csv> :  A list of the key policies Iran implemented to combate the coronavirus, and sources. This tab saved as "intermediate/covid_iran_policies.csv" and should not generally need to be updated.

3) Run the script "code/iran_cleaning.R"

4) Upload the output from "cleaned/IRN_processed.csv" to dropbox "data/interim/iran.

5) Daniel runs a final script to further harmonize the dataset, which saves to "data/processed/adm2/IRN_processed.csv".

