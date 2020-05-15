#Figure 2

#clean environment
rm(list = ls())

#load packages
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(magrittr))
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(gridExtra))

# set working directory
dir <- "results/source_data/"
output_dir <- "results/figures/fig2/"

if (!dir.exists(output_dir)){ #make dir if it doesn't exist
  dir.create(output_dir, recursive=TRUE)
}

#---------------------------------------------------------
# Load data and set up parameters for plotting
#---------------------------------------------------------

df <- read.csv(paste0(dir, "Figure2_data.csv"), header = T, stringsAsFactors = F) 

#Calculate 95% CI
df$ub <- df$beta + 1.96*df$se
df$lb <- df$beta - 1.96*df$se

#create effect size column
specify_decimal <- function(x, k) trimws(format(round(x, k), nsmall=k))
df$effectsize <- paste0(specify_decimal(df$beta, 2), " (", specify_decimal(df$lb,2), ", ", specify_decimal(df$ub,2), ")")

#calculate percentage growth
df$growth <- specify_decimal((exp(df$beta) - 1)*100, 2)

#Order countries
df$order[df$adm0 == "CHN"] <- 6
df$order[df$adm0 == "CHN_Wuhan"] <- 5.9
df$order[df$adm0 == "KOR"] <- 5
df$order[df$adm0 == "ITA"] <- 4
df$order[df$adm0 == "IRN"] <- 3
df$order[df$adm0 == "FRA"] <- 2
df$order[df$adm0 == "USA"] <- 1

#Panel 1: Infection growth rate without policy
df.no <- filter(df, df$policy == "no_policy rate") 

df.no$policy[df.no$adm0 == "KOR" & df.no$policy == "no_policy rate"] <- "South Korea"
df.no$policy[df.no$adm0 == "FRA" & df.no$policy == "no_policy rate"] <- "France"
df.no$policy[df.no$adm0 == "ITA" & df.no$policy == "no_policy rate"] <- "Italy"
df.no$policy[df.no$adm0 == "IRN" & df.no$policy == "no_policy rate"] <- "Iran"
df.no$policy[df.no$adm0 == "USA" & df.no$policy == "no_policy rate"] <- "United States"
df.no$policy[df.no$adm0 == "CHN" & df.no$policy == "no_policy rate"] <- "China"
df.no$policy[df.no$adm0 == "CHN_Wuhan" & df.no$policy == "no_policy rate"] <- "Wuhan, China"


#Panel 2: Effect of all policies combined
df.combined <- filter(df, (df$policy == "comb. policy" & df$adm0 != "CHN") |
                        df$policy == "first week" |
                        df$policy == "second week" |
                        df$policy == "third week" |
                        df$policy == "fourth week" |
                        df$policy == "fifth week and after" )

df.combined$policy[df.combined$adm0 == "KOR" & df.combined$policy == "comb. policy"] <- "South Korea"
df.combined$policy[df.combined$adm0 == "FRA" & df.combined$policy == "comb. policy"] <- "France"
df.combined$policy[df.combined$adm0 == "ITA" & df.combined$policy == "comb. policy"] <- "Italy"
df.combined$policy[df.combined$adm0 == "IRN" & df.combined$policy == "comb. policy"] <- "Iran"
df.combined$policy[df.combined$adm0 == "USA" & df.combined$policy == "comb. policy"] <- "United States"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "first week"] <- "China, Wk  1"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "second week"] <- "China, Wk  2"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "third week"] <- "China, Wk  3"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "fourth week"] <- "China, Wk  4"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "fifth week and after"] <- "China, Wk  5"

#Panel 3: Individual policies
df <- filter(df, policy != "comb. policy" &
               policy != "no_policy rate" &
               policy != "first week" &
               policy != "second week" &
               policy != "third week" &
               policy != "fourth week" &
               policy != "fifth week and after" &
               policy != "home_isolation_L0_to_L7" &
               policy != "home_isolation_L8_to_L14" &
               policy != "home_isolation_L15_to_L21" &
               policy != "home_isolation_L22_to_L28" &
               policy != "home_isolation_L29_to_L70" &
               !(df$adm0=="ITA" & df$policy=="p_6") &  #remove non-combined home isolation from ITA
               !(df$adm0=="FRA" & df$policy=="national_lockdown") &  #remove non-combined home isolation from FRA
               !(df$adm0=="USA" & df$policy=="p_10")) #remove non-combined home isolation from USA

#allow for duplicate discrete values to be plotted
df$effectsize[df$adm0 == "CHN" & df$beta == "-0.248"] <- " -0.25 (-0.34, -0.16)"
df$growth[df$adm0 == "CHN" & df$growth == "-0.90"] <- " -0.90"

#code individual policies
#KOR 
#order policies somewhat chronologically
df$order2[df$adm0 == "KOR" & df$policy == "p_1"] <- 2
df$order2[df$adm0 == "KOR" & df$policy == "p_2"] <- 1
df$order2[df$adm0 == "KOR" & df$policy == "p_3"] <- 3
df$order2[df$adm0 == "KOR" & df$policy == "p_4"] <- 4
#label policies
df$policy[df$adm0 == "KOR" & df$policy == "p_1"] <- "WFH, business closure, other social dist.(opt)" #Work from home, no gathering, business closure, social distance (opt)
df$policy[df$adm0 == "KOR" & df$policy == "p_2"] <- "Religious & welfare closure, no demonstration" 
df$policy[df$adm0 == "KOR" & df$policy == "p_3"] <- "Emergency declaration"
df$policy[df$adm0 == "KOR" & df$policy == "p_4"] <- "Quarantine positive cases "

#USA 
#order policies 
df$order2[df$adm0 == "USA" & df$policy == "p_1"] <- 9
df$order2[df$adm0 == "USA" & df$policy == "p_2"] <- 2
df$order2[df$adm0 == "USA" & df$policy == "p_3"] <- 4
df$order2[df$adm0 == "USA" & df$policy == "p_4"] <- 3
df$order2[df$adm0 == "USA" & df$policy == "p_5"] <- 8
df$order2[df$adm0 == "USA" & df$policy == "p_6"] <- 6
df$order2[df$adm0 == "USA" & df$policy == "p_7"] <- 5
df$order2[df$adm0 == "USA" & df$policy == "p_8"] <- 10
df$order2[df$adm0 == "USA" & df$policy == "p_9"] <- 7
df$order2[df$adm0 == "USA" & df$policy == "home_iso_combined"] <- 11 
df$order2[df$adm0 == "USA" & df$policy == "p_11"] <- 1
#label policies
df$policy[df$adm0 == "USA" & df$policy == "p_1"] <- "No gathering"
df$policy[df$adm0 == "USA" & df$policy == "p_2"] <- "Other social distance"
df$policy[df$adm0 == "USA" & df$policy == "p_3"] <- "Quarantine positive cases"
df$policy[df$adm0 == "USA" & df$policy == "p_4"] <- "Paid sick leave"
df$policy[df$adm0 == "USA" & df$policy == "p_5"] <- "Work from home (WFH)"
df$policy[df$adm0 == "USA" & df$policy == "p_6"] <- "School closure"
df$policy[df$adm0 == "USA" & df$policy == "p_7"] <- "Travel ban, transit suspension"
df$policy[df$adm0 == "USA" & df$policy == "p_8"] <- "Business closure"
df$policy[df$adm0 == "USA" & df$policy == "p_9"] <- "Religious closure" 
df$policy[df$adm0 == "USA" & df$policy == "home_iso_combined"] <- "Home isolation*" 
df$policy[df$adm0 == "USA" & df$policy == "p_11"] <- "Federal guidelines" 

#IRN
#order policies 
df$order2[df$adm0 == "IRN" & df$policy == "p_1"] <- 1
df$order2[df$adm0 == "IRN" & df$policy == "p_2"] <- 2
#label policies
df$policy[df$adm0 == "IRN" & df$policy == "p_1"] <- "WFH, school closure, travel ban(opt)"
df$policy[df$adm0 == "IRN" & df$policy == "p_2"] <- "Home isolation "

#ITA
#order policies 
df$order2[df$adm0 == "ITA" & df$policy == "p_1"] <- 3
df$order2[df$adm0 == "ITA" & df$policy == "p_2"] <- 1
df$order2[df$adm0 == "ITA" & df$policy == "p_3"] <- 4
df$order2[df$adm0 == "ITA" & df$policy == "p_4"] <- 2
df$order2[df$adm0 == "ITA" & df$policy == "p_5"] <- 5
df$order2[df$adm0 == "ITA" & df$policy == "home_iso_combined"] <- 6
#label policies
df$policy[df$adm0 == "ITA" & df$policy == "p_1"] <- " WFH, no gathering, other social distance " 
df$policy[df$adm0 == "ITA" & df$policy == "p_2"] <- " School closure"
df$policy[df$adm0 == "ITA" & df$policy == "p_3"] <- " Travel ban, transit suspension"
df$policy[df$adm0 == "ITA" & df$policy == "p_4"] <- " Quarantine positive cases"
df$policy[df$adm0 == "ITA" & df$policy == "p_5"] <- " Business closure"
df$policy[df$adm0 == "ITA" & df$policy == "home_iso_combined"] <- " Home isolation*" 

#CHN 
#order policies 
df$order2[df$adm0 == "CHN" & df$policy == "travel_ban_local_L0_to_L7"] <- 6
df$order2[df$adm0 == "CHN" & df$policy == "travel_ban_local_L8_to_L14"] <- 7
df$order2[df$adm0 == "CHN" & df$policy == "travel_ban_local_L15_to_L21"] <- 8
df$order2[df$adm0 == "CHN" & df$policy == "travel_ban_local_L22_to_L28"] <- 9
df$order2[df$adm0 == "CHN" & df$policy == "travel_ban_local_L29_to_L70"] <- 10
df$order2[df$adm0 == "CHN" & df$policy == "emergency_declaration_L0_to_L7"] <- 1
df$order2[df$adm0 == "CHN" & df$policy == "emergency_declaration_L8_to_L14"] <- 2
df$order2[df$adm0 == "CHN" & df$policy == "emergency_declaration_L15_to_L21"] <- 3
df$order2[df$adm0 == "CHN" & df$policy == "emergency_declaration_L22_to_L28"] <- 4
df$order2[df$adm0 == "CHN" & df$policy == "emergency_declaration_L29_to_L70"] <- 5
df$order2[df$adm0 == "CHN" & df$policy == "home_iso_L0_to_L7 + trvl_ban_loc_L0_to_L7"] <- 11
df$order2[df$adm0 == "CHN" & df$policy == "home_iso_L8_to_L14 + trvl_ban_loc_L8_to_L14"] <- 12
df$order2[df$adm0 == "CHN" & df$policy == "home_iso_L15_to_L21 + trvl_ban_loc_L15_to_L21"] <- 13
df$order2[df$adm0 == "CHN" & df$policy == "home_iso_L22_to_L28 + trvl_ban_loc_L22_to_L28"] <- 14
df$order2[df$adm0 == "CHN" & df$policy == "home_iso_L29_to_L70 + trvl_ban_loc_L29_to_L70"] <- 15
#label policies
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L0_to_L7"] <- "Travel ban, Wk 1"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L8_to_L14"] <- "Travel ban, Wk 2"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L15_to_L21"] <- "Travel ban, Wk 3"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L22_to_L28"] <- "Travel ban, Wk 4"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L29_to_L70"] <- "Travel ban, Wk 5"
df$policy[df$adm0 == "CHN" & df$policy == "emergency_declaration_L0_to_L7"] <- "Emergency declaration, Wk 1"
df$policy[df$adm0 == "CHN" & df$policy == "emergency_declaration_L8_to_L14"] <- "Emergency declaration, Wk 2"
df$policy[df$adm0 == "CHN" & df$policy == "emergency_declaration_L15_to_L21"] <- "Emergency declaration, Wk 3"
df$policy[df$adm0 == "CHN" & df$policy == "emergency_declaration_L22_to_L28"] <- "Emergency declaration, Wk 4"
df$policy[df$adm0 == "CHN" & df$policy == "emergency_declaration_L29_to_L70"] <- "Emergency declaration, Wk 5"
df$policy[df$adm0 == "CHN" & df$policy == "home_iso_L0_to_L7 + trvl_ban_loc_L0_to_L7"] <- "Home isolation, Wk 1*"
df$policy[df$adm0 == "CHN" & df$policy == "home_iso_L8_to_L14 + trvl_ban_loc_L8_to_L14"] <- "Home isolation, Wk 2*"
df$policy[df$adm0 == "CHN" & df$policy == "home_iso_L15_to_L21 + trvl_ban_loc_L15_to_L21"] <- "Home isolation, Wk 3*"
df$policy[df$adm0 == "CHN" & df$policy == "home_iso_L22_to_L28 + trvl_ban_loc_L22_to_L28"] <- "Home isolation, Wk 4*"
df$policy[df$adm0 == "CHN" & df$policy == "home_iso_L29_to_L70 + trvl_ban_loc_L29_to_L70"] <- "Home isolation, Wk 5*"

#FRA
#order policies 
df$order2[df$adm0 == "FRA" & df$policy == "school_closure_pop"] <- 1
df$order2[df$adm0 == "FRA" & df$policy == "pck_social_distanc"] <- 2
df$order2[df$adm0 == "FRA" & df$policy == "natl_lockdown_comb"] <- 3
#label policies
df$policy[df$adm0 == "FRA" & df$policy == "school_closure_pop"] <- "School closure "
df$policy[df$adm0 == "FRA" & df$policy == "pck_social_distanc"] <- "Cancel events, no gathering, other social dist." 
df$policy[df$adm0 == "FRA" & df$policy == "natl_lockdown_comb"] <- "National lockdown*" 

#order df
df <- dplyr::arrange(df, desc(order), order2) 
df.combined <- dplyr::arrange(df.combined, desc(order), order2) 
df.no <- dplyr::arrange(df.no, desc(order), order2) 

#set up columns for plotting
df$country <- "United States"
df$country[df$adm0 == "KOR"] <- "South Korea"
df$country[df$adm0 == "CHN"] <- "China"
df$country[df$adm0 == "IRN"] <- "Iran"
df$country[df$adm0 == "ITA"] <- "Italy"
df$country[df$adm0 == "FRA"] <- "France"

#plot
#set theme for plotting 
theme_fig2 <- function(base_size=6) {
  ret <- theme_bw(base_size) %+replace%
    theme(panel.background = element_rect(fill="#ffffff", colour=NA),
          title=element_text(vjust=1.2, face="bold", size = 6),
          panel.border = element_blank(), 
          axis.line=element_blank(),
          panel.grid.minor=element_blank(),
          panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(size=0.1, colour="grey80", linetype="solid"),
          axis.ticks=element_blank(),
          legend.position="none", 
          axis.title=element_text(size=rel(0.8), face="bold"),
          strip.text=element_text(size=rel(1)),
          strip.background=element_rect(fill="#ffffff", colour=NA),
          panel.spacing.y=unit(1.5, "lines"),
          legend.key = element_blank())
  
  ret
}

#average value across 6 countries
df.6 <- filter(df.no, policy %in% c("China", "South Korea", "Italy", "Iran", "France", "United States")) 
df.6$N <- c(3669, 595, 2898, 548, 270, 1238) # add number of obs for each country
average.beta <- round(mean(df.6$beta), 2)
average.se <- sqrt(sum((df.6$se)^2*df.6$N)/sum(df.6$N))
average.beta.percent <- round((exp(average.beta)-1)*100, 0)

#average value across 5 countries (exclude IRN)
df.5 <- filter(df.no, policy %in% c("China", "South Korea", "Italy", "France", "United States")) #without IRN
df.5$N <- c(3669, 595, 2898, 270, 1238) # without IRN
average.beta.5 <- round(mean(df.5$beta), 2)
average.se.5 <- sqrt(sum((df.5$se)^2*df.5$N)/sum(df.5$N))
average.beta.percent.5 <- round((exp(average.beta.5)-1)*100, 0)

#draw faint horizontal lines dividing countries
y.breaks <- plyr::count(df$order)[2]
y.breaks <- c(y.breaks[1:(nrow(y.breaks)-1),]) %>%
  cumsum() + 0.5

#---------------------------------------------------------
# Plot figures
#---------------------------------------------------------
dot.size <- 1

# Panel A: Infection growth rate without policy
betas.no <- ggplot(data = df.no) + 
  geom_segment(aes(x = lb, y = policy, xend = ub, yend = policy), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=policy),  color = "darkred", size=dot.size, alpha = 0.9) +
  geom_vline(xintercept=0, colour="grey30", linetype="solid", size = 0.3) + #zeroline
  geom_vline(xintercept=average.beta, colour="darkred", linetype="dotted", size = 0.3) + #average beta
  geom_vline(xintercept=average.beta.5, colour="darkred", linetype="dotted", size = 0.3, alpha = 0.5) + #average beta without IRN
  geom_hline(yintercept= 0.5, colour="grey50", linetype="solid", size = 0.3) + 
  geom_text(aes(x = 0.7, y = 6.5), size = 0.7, label= paste0("Average = ", average.beta, " (",average.beta.percent,"%)")) + 
  geom_text(aes(x = 0.7, y = 5.5), size = 0.7, label= paste0("Average (exc. Iran) = ", average.beta.5, " (",average.beta.percent.5,"%)")) + 
  scale_y_discrete(limits = rev(df.no$policy), position = "left") +
  theme_fig2() + 
  coord_cartesian(xlim =c(-0.9,0.9))  +
  xlab("Estimated daily growth rate") + ylab("") +
  ggtitle("Infection growth rate without policy") 

eff.size.no <- ggplot(data = df.no) + 
  geom_point(aes(x=beta, y=effectsize), color = "grey", size=dot.size, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.no$effectsize), position = "left") +
  xlab("Effect size (deltalog per day)") + ylab("") +
  theme_fig2() +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  ggtitle("") 

#growth plot
growth.no <- ggplot(data = df.no) + 
  geom_point(aes(x=beta, y=growth), color = "grey", size=dot.size, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.no$growth), position = "left") +
  xlab("As percent growth (% per day)") + ylab("") +
  theme_fig2() +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  ggtitle("") 

#combine 3 plots into 1 figure
all.plot.no <- grid.arrange(betas.no, eff.size.no, growth.no, ncol=3)
ggsave(all.plot.no, file = paste0(output_dir,"Fig2A_nopolicy.pdf"), width = 8, height = 1.1) #vertical

#---------------------------------------------------------
# Panel B: Effect of all policies combined

betas.combined <- ggplot(data = df.combined) + 
  geom_segment(aes(x = lb, y = policy, xend = ub, yend = policy), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=policy), color = "royalblue4", size=dot.size, alpha = 0.9) +
  geom_vline(xintercept=0, colour="grey30", linetype="solid", size = 0.3) + 
  geom_hline(yintercept= 0.5, colour="grey50", linetype="solid", size = 0.3) + 
  scale_y_discrete(limits = rev(df.combined$policy), position = "left") +
  theme_fig2() + 
  coord_cartesian(xlim =c(-0.9,0.9))  +
  xlab("Estimated effect on daily growth rate") + ylab("") +
  ggtitle("Effect of all policies combined") 

#effect size plot
eff.size.comb <- ggplot(data = df.combined) + 
  geom_point(aes(x=beta, y=effectsize), color = "grey", size=dot.size, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.combined$effectsize), position = "left") +
  xlab("Effect size (deltalog per day)") +
  theme_fig2() +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  xlab("Effect size (deltalog per day)") + ylab("") +
  ggtitle("") 

#growth plot
growth.comb <- ggplot(data = df.combined) + 
  geom_point(aes(x=beta, y=growth), color = "grey", size=dot.size, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.combined$growth), position = "left") +
  xlab("As percent growth (% per day)") + ylab("") +
  theme_fig2() +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  ggtitle("") 

#combine 3 plots into 1 figure
all.plot.comb <- grid.arrange(betas.combined, eff.size.comb, growth.comb, ncol=3)
ggsave(all.plot.comb, file = paste0(output_dir,"Fig2B_comb.pdf"), width = 8, height = 1.3) #vertical
#---------------------------------------------------------
# Panel C: Individual policies

betas <- ggplot(data = df) + 
  geom_segment(aes(x = lb, y = policy, xend = ub, yend = policy), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=policy, group = country, color = country),  size=dot.size, alpha = 0.9) +
  geom_hline(yintercept= y.breaks, colour="grey50", linetype="dotted", size = 0.3) +
  geom_hline(yintercept= 0.5, colour="grey50", linetype="solid", size = 0.3) + 
  geom_vline(xintercept=0, colour="grey30", linetype="solid", size = 0.3) + 
  scale_colour_manual(name="", 
                      breaks=c("China","France","Iran", "Italy", "South Korea", "United States"), 
                      values=c("China"="salmon", "France"="#655643", "Iran"="#78bea2", "Italy"="paleturquoise4", "South Korea"="#e6ac27", "United States"="#bb7693")) + #retro
   scale_y_discrete(limits = rev(df$policy), position = "left") +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  theme_fig2() + 
  ggtitle("Effect of individual policies") +
  xlab("Estimated effect on daily growth rate") + ylab("")  

#effect size plot
eff.size <- ggplot(data = df) + 
  geom_point(aes(x=beta, y=effectsize, group = country), color = "grey", size=dot.size, alpha = 0.9) +
  scale_y_discrete(limits = rev(df$effectsize), position = "left") +
  ggtitle("") +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  xlab("Effect size (deltalog per day)") + ylab("") +
  theme_fig2() 

#growth plot
growth <- ggplot(data = df) + 
  geom_point(aes(x=beta, y=growth, group = country), color = "grey",  size=dot.size, alpha = 0.9) +
  scale_y_discrete(limits = rev(as.character(df$growth)), position = "left") +
  ggtitle("") +
  coord_cartesian(xlim =c(-0.9,0.9))  +
  xlab("As percent growth (% per day)") + ylab("") +
  theme_fig2() 

#combine 3 plots into 1 figure
all.plot.ind <- grid.arrange(betas, eff.size, growth, ncol=3)
ggsave(all.plot.ind, file = paste0(output_dir,"Fig2C_ind.pdf"), width = 11, height = 4) #vertical

