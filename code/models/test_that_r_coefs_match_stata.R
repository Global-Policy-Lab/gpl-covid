suppressPackageStartupMessages(library(tidyverse))
suppressPackageStartupMessages(library(gt))
suppressPackageStartupMessages(library(ggsci))
suppressPackageStartupMessages(library(patchwork))

list.files("code/models", full.names = TRUE) %>% 
  str_subset("data_and_model_projection") %>% 
  walk(source)

stata_coefficients <- read_csv("results/source_data/Figure2_data.csv",
                               col_types = cols(
                                 adm0 = col_character(),
                                 policy = col_character(),
                                 beta = col_double(),
                                 se = col_double()
                               ))

suppressWarnings({
  check <- tibble(country =   c("CHN", "IRN", "KOR", "ITA", "FRA", "USA"),
                  model = list(china_model, iran_model, korea_model, italy_model, france_model, usa_model)
  ) %>% 
    mutate(check = list(country, model) %>% pmap_lgl(~{
      check <- stata_coefficients %>% 
        filter(adm0 == .x) %>% 
        left_join(.y %>% 
                    broom::tidy(),
                  by = c("policy" = "term")) %>% 
        drop_na()
      isTRUE(all.equal(round(check$estimate, 3), check$beta)) & 
        isTRUE(all.equal(round(check$std.error, 3), check$se))
    }))
})
if(TRUE){
  stop("Coefficients in stata do not match replications in projection code.")
}