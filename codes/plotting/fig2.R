#Figure 2

#clean environment
rm(list = ls())

#load packages
library(dplyr)
library(magrittr)
library(ggplot2)

# set working directory
dir <- "models/"
output_dir <- "results/figures/fig2/"

if (!dir.exists(output_dir)){ #make dir if it doesn't exist
  dir.create(output_dir)
}

countrylist <- c("CHN", "KOR", "ITA", "IRN", "FRA", "USA")

#---------------------------------------------------------
# Load data and set up parameters for plotting
#---------------------------------------------------------

df <- c() #load all coeff cvs & combine data into a df
for (c in countrylist){
  iso <- read.csv(paste0(dir, c, "_coefs.csv"), header = T, stringsAsFactors = F)
  df <- rbind(df, iso)
  rm(iso)
}

#Calculate 95% CI
df$ub <- df$beta + 1.96*df$se
df$lb <- df$beta - 1.96*df$se

#create effect size column
df$effectsize <- factor(paste0(round(df$beta, 2), " (", round(df$lb,2), ", ", round(df$ub,2), ") "))

#calculate percentage growth
df$growth <- as.character(round((exp(df$beta) - 1),4)*100)

#Input number of days for each country
df$days[df$adm0 == "CHN"] <- 63
df$days[df$adm0 == "CHN_Wuhan"] <- 62.5
df$days[df$adm0 == "KOR"] <- 31
df$days[df$adm0 == "ITA"] <- 23
df$days[df$adm0 == "IRN"] <- 21
df$days[df$adm0 == "FRA"] <- 20.5
df$days[df$adm0 == "USA"] <- 10


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
                        df$policy == "comb. policy Teheran" |
                        df$policy == "first week (home+travel)" |
                        df$policy == "second week (home+travel)" |
                        df$policy == "third week (home+travel)" |
                        df$policy == "fourth week (home+travel)" |
                        df$policy == "fifth week (home+travel)" )

df.combined$policy[df.combined$adm0 == "KOR" & df.combined$policy == "comb. policy"] <- "South Korea"
df.combined$policy[df.combined$adm0 == "FRA" & df.combined$policy == "comb. policy"] <- "France"
df.combined$policy[df.combined$adm0 == "ITA" & df.combined$policy == "comb. policy"] <- "Italy"
df.combined$policy[df.combined$adm0 == "IRN" & df.combined$policy == "comb. policy"] <- "Iran"
df.combined$policy[df.combined$adm0 == "IRN" & df.combined$policy == "comb. policy Teheran"] <- "Tehran, Iran"
df.combined$policy[df.combined$adm0 == "USA" & df.combined$policy == "comb. policy"] <- "United States"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "first week (home+travel)"] <- "China, Week 1"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "second week (home+travel)"] <- "China, Week 2"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "third week (home+travel)"] <- "China, Week 3"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "fourth week (home+travel)"] <- "China, Week 4"
df.combined$policy[df.combined$adm0 == "CHN" & df.combined$policy == "fifth week (home+travel)"] <- "China, Week 5"

#Panel 3: Individual policies
df <- filter(df, df$policy != "comb. policy" &
               df$policy != "no_policy rate" &
               df$policy != "first week (home+travel)" &
               df$policy != "second week (home+travel)" &
               df$policy != "third week (home+travel)" &
               df$policy != "fourth week (home+travel)" &
               df$policy != "fifth week (home+travel)" &
               df$policy != "comb. policy Teheran")

#allow for duplicate discrete values to be plotted
df$growth[df$adm0 == "CHN" & df$growth == "-9.24"] <- "-9.24 "
df$growth[df$adm0 == "KOR" & df$growth == "-13.58"] <- "-13.58 "
df$growth[df$adm0 == "KOR" & df$growth == "-8.06"] <- "-8.06 "

#code policies individual policies
#KOR 
df$policy[df$adm0 == "KOR" & df$policy == "p_1"] <- "Business closures, work from home"
df$policy[df$adm0 == "KOR" & df$policy == "p_2"] <- "No demonstrations, religious closures"
df$policy[df$adm0 == "KOR" & df$policy == "p_3"] <- "Social distancing"
df$policy[df$adm0 == "KOR" & df$policy == "p_4"] <- "Emergency declaration"

#USA 
df$policy[df$adm0 == "USA" & df$policy == "p_1"] <- "Social distancing "
df$policy[df$adm0 == "USA" & df$policy == "p_2"] <- "Business closures, travel ban"
df$policy[df$adm0 == "USA" & df$policy == "p_3"] <- "School closures"

#IRN
df$policy[df$adm0 == "IRN" & df$policy == "p_1"] <- "School closures, travel ban, work from home"
df$policy[df$adm0 == "IRN" & df$policy == "p_2"] <- "Home isolation"

#ITA
df$policy[df$adm0 == "ITA" & df$policy == "p_1"] <- "Social distancing, home isolation, business closures"
df$policy[df$adm0 == "ITA" & df$policy == "p_2"] <- "Travel ban"
df$policy[df$adm0 == "ITA" & df$policy == "p_3"] <- "Quarantining positive cases"
df$policy[df$adm0 == "ITA" & df$policy == "p_4"] <- "School closures "

#CHN 
df$policy[df$adm0 == "CHN" & df$policy == "home_isolation_L0_to_L7"] <- "Home isolation, Week 1"
df$policy[df$adm0 == "CHN" & df$policy == "home_isolation_L8_to_L14"] <- "Home isolation, Week 2"
df$policy[df$adm0 == "CHN" & df$policy == "home_isolation_L15_to_L21"] <- "Home isolation, Week 3"
df$policy[df$adm0 == "CHN" & df$policy == "home_isolation_L22_to_L28"] <- "Home isolation, Week 4"
df$policy[df$adm0 == "CHN" & df$policy == "home_isolation_L29_to_L70"] <- "Home isolation, Week 5"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L0_to_L7"] <- "Travel ban, Week 1"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L8_to_L14"] <- "Travel ban, Week 2"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L15_to_L21"] <- "Travel ban, Week 3"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L22_to_L28"] <- "Travel ban, Week 4"
df$policy[df$adm0 == "CHN" & df$policy == "travel_ban_local_L29_to_L70"] <- "Travel ban, Week 5"

#FRA
df$policy[df$adm0 == "FRA" & df$policy == "event_cancel"] <- "Cancelling events"
df$policy[df$adm0 == "FRA" & df$policy == "school_closure_reg"] <- "School closures  "
df$policy[df$adm0 == "FRA" & df$policy == "social_distance"] <- "Social distancing  "
df$policy[df$adm0 == "FRA" & df$policy == "national_no_gather"] <- "No gatherings"
df$policy[df$adm0 == "FRA" & df$policy == "national_lockdown"] <- "National lockdown"

#order df
df <- dplyr::arrange(df, desc(days), policy) 
df.combined <- dplyr::arrange(df.combined, desc(days), policy) 
df.no <- dplyr::arrange(df.no, desc(days), policy) 

#set up columns for plotting
df$country <- "United States"
df$country[df$adm0 == "KOR"] <- "South Korea"
df$country[df$adm0 == "CHN"] <- "China"
df$country[df$adm0 == "IRN"] <- "Iran"
df$country[df$adm0 == "ITA"] <- "Italy"
df$country[df$adm0 == "FRA"] <- "France"

#plot
#set theme for plotting 
theme_fig2 <- function(base_size=11) {
  ret <- theme_bw(base_size) %+replace%
    theme(panel.background = element_rect(fill="#ffffff", colour=NA),
          title=element_text(vjust=1.2),
          panel.border = element_blank(), 
          axis.line=element_blank(),
          panel.grid.minor=element_blank(),
          panel.grid.major.y = element_blank(),
          panel.grid.major.x = element_line(size=0.1, colour="grey80", linetype="solid"),
          axis.ticks=element_blank(),
          legend.position="bottom", 
          axis.title=element_text(size=rel(0.8)),
          strip.text=element_text(size=rel(1)),
          strip.background=element_rect(fill="#ffffff", colour=NA),
          panel.spacing.y=unit(1.5, "lines"),
          legend.key = element_blank())
  
  ret
}


#draw faint horizontal lines dividing countries
y.breaks <- plyr::count(df$days)[2]
y.breaks <- c(0, y.breaks[1:(nrow(y.breaks)-1),]) %>%
  cumsum() + 0.5

#---------------------------------------------------------
# Plot figures
#---------------------------------------------------------

# Panel 1: Infection growth rate without policy

betas.no <- ggplot(data = df.no) + 
  geom_segment(aes(x = lb, y = policy, xend = ub, yend = policy), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=policy),  color = "darkred", size=3, alpha = 0.9) +
  geom_vline(xintercept=0, colour="grey30", linetype="solid", size = 0.3) + 
  geom_vline(xintercept=mean(df.no$beta), colour="darkred", linetype="dotted", size = 0.5) + #average beta
  geom_hline(yintercept= 0.5, colour="grey50", linetype="dotted", size = 0.5) + 
  scale_y_discrete(limits = rev(df.no$policy), position = "left") +
  theme_fig2() + 
  coord_cartesian(xlim =c(-0.6,0.6))  +
  xlab("Estimated daily growth rate") + ylab("") +
  ggtitle("Infection growth rate without policy") 
ggsave(betas.no, file = paste0(output_dir,"Fig2_nopolicy.pdf"), width = 8, height = 4)

#average value
print(mean(df.no$beta))

eff.size.no <- ggplot(data = df.no) + 
  geom_segment(aes(x = lb, y = effectsize, xend = ub, yend = effectsize), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=effectsize), color = "darkred", size=3, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.no$effectsize), position = "left") +
  xlab("Effect size (95% CI)") +
  theme_fig2() +
  ggtitle("Infection growth rate without policy") 
ggsave(eff.size.no, file = paste0(output_dir,"Fig2_effectsize_nopolicy.pdf"), width = 8, height = 4)

#growth plot
growth.no <- ggplot(data = df.no) + 
  geom_segment(aes(x = lb, y = growth, xend = ub, yend = growth), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=growth), color = "darkred", size=3, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.no$growth), position = "left") +
  xlab("Percentage growth") +
  theme_fig2() +
  ggtitle("Infection growth rate without policy") 
ggsave(growth.no, file = paste0(output_dir,"Fig2_growth_nopolicy.pdf"), width = 8, height = 4)


#---------------------------------------------------------
# Panel 2: Effect of all policies combined

betas.combined <- ggplot(data = df.combined) + 
  geom_segment(aes(x = lb, y = policy, xend = ub, yend = policy), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=policy), color = "royalblue4", size=3, alpha = 0.9) +
  geom_vline(xintercept=0, colour="grey30", linetype="solid", size = 0.3) + 
  geom_hline(yintercept= 0.5, colour="grey50", linetype="dotted", size = 0.5) + 
  scale_y_discrete(limits = rev(df.combined$policy), position = "left") +
  theme_fig2() + 
  coord_cartesian(xlim =c(-0.6,0.6))  +
  xlab("Estimated effect on daily growth rate") + ylab("") +
  ggtitle("Effect of all policies combined") 
ggsave(betas.combined, file = paste0(output_dir,"Fig2_comb.pdf"), width = 8, height = 6)

#effect size plot
eff.size.comb <- ggplot(data = df.combined) + 
  geom_segment(aes(x = lb, y = effectsize, xend = ub, yend = effectsize), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=effectsize), color = "royalblue4", size=3, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.combined$effectsize), position = "left") +
  xlab("Effect size (95% CI)") +
  theme_fig2() +
  ggtitle("Effect of all policies combined") 
ggsave(eff.size.comb, file = paste0(output_dir,"Fig2_effectsize_comb.pdf"), width = 8, height = 6)

#growth plot
growth.comb <- ggplot(data = df.combined) + 
  geom_segment(aes(x = lb, y = growth, xend = ub, yend = growth), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=growth), color = "royalblue4", size=3, alpha = 0.9) +
  scale_y_discrete(limits = rev(df.combined$growth), position = "left") +
  xlab("Percentage growth") +
  theme_fig2() +
  ggtitle("Effect of all policies combined") 
ggsave(growth.comb, file = paste0(output_dir,"Fig2_growth_comb.pdf"), width = 8, height = 6)


#---------------------------------------------------------
# Panel 3: Individual policies

betas <- ggplot(data = df) + 
  geom_segment(aes(x = lb, y = policy, xend = ub, yend = policy), size = 0.3, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=policy, group = country, color = country),  size=3, alpha = 0.9) +
  geom_hline(yintercept= y.breaks, colour="grey50", linetype="dotted", size = 0.5) + 
  geom_vline(xintercept=0, colour="grey30", linetype="solid", size = 0.3) + 
  scale_colour_manual(name="", 
                      breaks=c("China","France","Iran", "Italy", "South Korea", "United States"), 
                      values=c("China"="salmon", "France"="#655643", "Iran"="#78bea2", "Italy"="paleturquoise4", "South Korea"="#e6ac27", "United States"="#bb7693")) + #retro
   scale_y_discrete(limits = rev(df$policy), position = "left") +
  coord_cartesian(xlim =c(-0.6,0.6))  +
  theme_fig2() + 
  xlab("Estimated effect on daily growth rate") + ylab("") 
ggsave(betas, file = paste0(output_dir,"Fig2_ind.pdf"), width = 8, height = 10)

#effect size plot
eff.size <- ggplot(data = df) + 
  geom_segment(aes(x = lb, y = effectsize, xend = ub, yend = effectsize), size = 0.1, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=effectsize, group = country, color = country),   size=3, alpha = 0.9) +
  scale_y_discrete(limits = rev(df$effectsize), position = "left") +
  xlab("Effect size (95% CI)") +
  theme_fig2() 
ggsave(eff.size, file = paste0(output_dir,"Fig2_effectsize_ind.pdf"), width = 6, height = 9.8)

#growth plot
growth <- ggplot(data = df) + 
  geom_segment(aes(x = lb, y = growth, xend = ub, yend = growth), size = 0.1, colour =  "grey39") + #grey CI
  geom_point(aes(x=beta, y=growth, group = country, color = country),   size=3, alpha = 0.9) +
  scale_y_discrete(limits = rev(as.character(df$growth)), position = "left") +
  xlab("Percentage growth") +
  theme_fig2() 
ggsave(growth, file = paste0(output_dir,"Fig2_growth_ind.pdf"), width = 6, height = 9.8)

