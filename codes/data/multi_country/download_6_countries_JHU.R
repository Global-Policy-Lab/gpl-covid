suppressPackageStartupMessages(library(tidyverse))
for (i in c("china", "france", "iran", "italy", "korea", "usa"))
{
    dir.create(paste("data/interim/",i, sep=""), recursive=TRUE, showWarnings=FALSE)
    source(paste("codes/data/", i, "/download_and_clean_JHU_", i, ".R", sep=""))
}