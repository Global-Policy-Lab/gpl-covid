# Jeanette Tseng
# Created: 2020-03-14
# Description: schedule auto scraping of daily confirmed cases by region

# working directory = < GPL_covid > folder

library(taskscheduleR)
scraping_script <- 'C:/Users/Jeanette/Desktop/scrape/scrape_conf_cases_by_region.R'

# Schedule to run every day at 10am PT (6pm in France)
taskscheduler_create(taskname = "france_sp_conf_cases_12pm", rscript = scraping_script, 
                     schedule = "DAILY", starttime = "12:00", startdate = "03/17/2020")

## Tasks information can be captured in a dataframe
tasks_log <- taskscheduler_ls()
str(tasks_log)
dplyr::filter(tasks_log, stringr::str_detect(TaskName, "france"))

## To delete the tasks use the followig command
# taskscheduler_delete(taskname = "france_sp_conf_cases_10am")