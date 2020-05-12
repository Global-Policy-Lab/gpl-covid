suppressPackageStartupMessages(library(tidyverse))
tryCatch({
    for (i in c("china", "france", "iran", "italy", "korea", "usa"))
    {
        dir.create(paste("data/interim/",i, sep=""), recursive=TRUE, showWarnings=FALSE)
        source(paste("code/data/", i, "/download_and_clean_JHU_", i, ".R", sep=""))
    }
},
error=function(cond) {
    message("SKIP ERROR: JHU download/processing not working. Data format/URL has likely changed and script will need to be updated")
})