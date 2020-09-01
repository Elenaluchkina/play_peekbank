#### Load packages ####
library(here)
library(XML)
library(reader)
library(fs)
library(feather)
library(tidyverse)
library(peekds) # local install..
library(osfr)

## for pushing to OSF
osf_token <- read_lines(here("osf_token.txt"))

### Search ### FIXME for things to continue working on

# load raw data
raw <- read_csv(here("data/byers-heinlein_2017/full_dataset/switching_data.csv"))
# "RecordingName","id","trial.number","order.seen","MediaName","TrialTimestamp","trial.type","carrier.language","target.language","look.target","look.distractor","look.any","GazePointX","GazePointY","PupilLeft","PupilRight","trackloss","per.eng","per.fr","per.dom","per.nondom","lang.mix","trial.number.unique","age.group","switch.type","Carrier"
#"Subject_1_Block1","Subject_1",1,1,"Dog_L_ENG",0,"same","English","English",NA,NA,NA,NA,NA,NA,NA,TRUE,55,45,55,45,21,1,"20-month-olds","Within-sentence","Dominant"
#"Subject_1_Block1","Subject_1",1,1,"Dog_L_ENG",17,"same","English","English",0,0,0,1559,-335,3.54,3.61,TRUE,55,45,55,45,21,1,"20-month-olds","Within-sentence","Dominant"
#"Subject_1_Block1","Subject_1",1,1,"Dog_L_ENG",33,"same","English","English",0,0,0,1601,-403,3.72,3.62,TRUE,55,45,55,45,21,1,"20-month-olds","Within-sentence","Dominant"
#"Subject_1_Block1","Subject_1",1,1,"Dog_L_ENG",50,"same","English","English",NA,NA,NA,NA,NA,NA,NA,TRUE,55,45,55,45,21,1,"20-month-olds","Within-sentence","Dominant"

#### general parameters ####
dataset_name <- "byers-heinlein_2017" 
tracker_name <- "Tobii T60-XL"
dataset_id <- 0 # doesn't matter (use 0)
max_lines_search <- 40 #maybe change this value?
subid_col_name <- "id"
# not found in paper/datafile, but Tobii T60-XL according to manual has a 24" TFT wide-screen display 1920 x 1200 pixels
monitor_size <- "1920x1200" # pixels  "Calibration Area" 
sample_rate <- 60 # Hz (found in paper, but could be automatically reverse-engineered from timestamps..)
lab_age_units = "months"

possible_delims <- c("\t",",")
left_x_col_name <-  "GazePointX" # data has no separate left and right eye measures (except for pupil diameter)
right_x_col_name <-  "GazePointX"
left_y_col_name <-  "GazePointY" 
right_y_col_name <-  "GazePointY"
# adding pupil size:
left_pupil_size_col_name <- "PupilLeft"
right_pupil_size_col_name <- "PupilRight"

#get maximum x-y coordinates on screen
screen_xy <- str_split(monitor_size,"x") %>%
  unlist()
monitor_size_x <- as.numeric(as.character(screen_xy[1]))
monitor_size_y <- as.numeric(as.character(screen_xy[2]))

# no stimuli included in OSF repo
#stims_to_remove_chars <- c(".avi")
#stims_to_keep_chars <- c("_")
stimulus_col_name = "MediaName" # strip filename if present (not applicable here)

# no separate trial / participant files
#trial_file_name <- "reflook_tests.csv"
#participant_file_name <- "reflook_v1_demographics.csv"

# problem: we only have age.group ("20-month-olds" vs. "Adults") -- not age in days
# also no other demographic info (e.g., sex)

# notes based on OSF's switching_analysis.R:
#  window_start_time = 5200, #200 ms prior to noun onset 
#  window_end_time = 5400, # noun onset
point_of_disambiguation = 5400

#### define directory ####
#Define root path
project_root <- here::here()

#build directory path
dir_path <- fs::path(project_root,"data",dataset_name,"full_dataset")
exp_info_path <- fs::path(project_root,"data",dataset_name,"experiment_info")
aoi_path <- fs::path(project_root,"data",dataset_name,"test_aois")

#output path
output_path <- fs::path(project_root,"data",dataset_name,"processed_data")


# write Dataset table
data_tab <- tibble(
  dataset_id = dataset_id, 
  dataset_name = dataset_name, 
  lab_dataset_id = NA, # internal name from the lab (if known)
  cite = "Byers-Heinlein, K., Morin-Lessard, E., & Lew-Williams, C. (2017). Bilingual infants control their languages as they listen. Proceedings of the National Academy of Sciences, 114(34), 9032-9037.",
  shortcite = "Byers-Heinlein et al. 2017"
) %>% 
  write_csv(fs::path(output_path, "datasets.csv"))

# Notes on stimuli:
# if dog is target, book is distractor
# if book is target, dog is distractor
# other two pairs: door - mouth, cookie - foot

# Basic dataset filtering and cleaning up
d_tidy <- raw %>% filter(age.group!="Adults" 
                         #trial.type!="switch"# remove language switch trials? decided to include.
                         ) %>% 
  ### FIXME: Import trial order .csvs instead of using regular expressions; currnetly missing some trials because of  inconsistent file naming conventions
  mutate(subject_id = as.numeric(map_chr(id, ~str_split(., "_")[[1]][2])),
         sex = 'unspecified', ### FIXME
         target = tolower(map_chr(MediaName, ~ str_split(., "_")[[1]][1])),
         target_side = map_chr(MediaName, ~ str_split(., "_")[[1]][2]),
         trial_language = map_chr(MediaName, ~ str_split(., "_")[[1]][3]), # ENG / FR / SW
         age = 20, ### FIXME
         lab_age = 20, ### FIXME
         t = TrialTimestamp) %>%
  mutate(distractor = case_when(target == "book" ~ "dog",
                                target == "dog"~ "book",
                                target == "door" ~ "mouth",
                                target == "mouth" ~ "door",
                                target == "cookie" ~ "foot",
                                target == "foot" ~ "cookie",
                                target == "livre" ~ "chien",
                                target == "chien"~ "livre",
                                target == "porte" ~ "bouche",
                                target == "bouche" ~ "porte",
                                target == "biscuit" ~ "pied",
                                target == "pied" ~ "biscuit")) %>% # do we want unique images, or image x language?
  filter(t >= 0, # a few -13..
         !is.na(distractor)) %>%  # effectively filteres filler trials as well as a few others because the mediaNames where inconsistent
  rename(lab_subject_id = id,
         lab_trial_id = trial.number.unique,
         lab_stimulus_id = MediaName) %>%
  select(-trial.number, -PupilLeft, -PupilRight)


# subjects table
d_tidy %>%
  distinct(subject_id, lab_subject_id, sex) %>%
  write_csv(fs::path(output_path, "subjects.csv"))
  

# administrations table
d_tidy %>%
  distinct(subject_id, 
           age,
           lab_age) %>%
  mutate(coding_method = "eyetracking",
         dataset_id = dataset_id,
         administration_id = subject_id,
         tracker = tracker_name,
         monitor_size_x = monitor_size_x,
         monitor_size_y = monitor_size_y,
         sample_rate = sample_rate,
         lab_age_units = lab_age_units) %>% # unless you have longitudinal data) %>%
  write_csv(fs::path(output_path, "administrations.csv"))


# stimulus table 
## FIXME -- there are filler trials that are not in the datafile that we currently have that would be useful.
stimuli_image <- unique(d_tidy$target)[1:6] # what about lf1, 3, 7 etc ...filler?
stimuli_label <- unique(c(d_tidy$target, d_tidy$distractor))

stim_trans <- d_tidy %>% distinct(target, distractor) %>%
  mutate(stimulus_image_path = rep(target[1:6], 2)) 

stim_tab <- cross_df(list(stimuli_image = stimuli_image, stimuli_label = stimuli_label)) %>%
  left_join(stim_trans, by=c("stimuli_image"="stimulus_image_path")) %>%
  filter(stimuli_image==stimuli_label) %>%
  select(-stimuli_label, -distractor) %>%
  rename(stimulus_label = target, 
         stimulus_image_path = stimuli_image) %>%
  mutate(stimulus_id = 0:(length(stimuli_label)-1),
         lab_stimulus_id = NA,
         dataset_id = dataset_id,
         stimulus_novelty = "familiar")

stim_tab %>% 
  write_csv(fs::path(output_path, "stimuli.csv"))


# write trials table
d_tidy_final <- d_tidy %>% 
  mutate(target_side = factor(target_side, levels=c('L','R'), labels = c('left','right'))) %>%
  left_join(stim_tab %>% select(stimulus_id, stimulus_label), by=c("target"="stimulus_label")) %>%
  rename(target_id = stimulus_id) %>%
  left_join(stim_tab %>% select(stimulus_id, stimulus_label), by=c("distractor"="stimulus_label")) %>%
  rename(distractor_id = stimulus_id) 

aoi_region_tab <- d_tidy_final %>%
  distinct(target_id, target, target_side) %>%
  mutate(aoi_region_set_id = seq(0,n()-1))

d_trial_ids <- d_tidy_final %>%
  distinct(target_id, distractor_id, target_side, carrier.language, lab_trial_id, distractor) %>% # lab_trial_id, switch.type, trial.type, 
  mutate(trial_id = seq(0, n() - 1)) %>%
  left_join(aoi_region_tab) %>%
  mutate(full_phrase_language = 'multiple') %>%
  mutate(point_of_disambiguation= point_of_disambiguation,
         full_phrase = NA,
         dataset_id = dataset_id) 

d_trial_ids %>% select(-carrier.language, -distractor, -target) %>% 
  write_csv(fs::path(output_path, "trials.csv"))


# add trial_id & administration id
d_tidy_final2 <- d_tidy_final %>%
  mutate(administration_id = subject_id) %>%
  left_join(d_trial_ids) 

# create aoi_region_sets.csv 
# in AOI region sets, origin is TOP LEFT -- so, ymin=top_left and ymax = top_left + length
# MZ will double check with authors.

aois <- read_csv(paste0(aoi_path,'/AOIs.csv')) %>%
  mutate(target.object = tolower(target.object)) %>%
  filter(target.object %in% d_tidy_final2$target) %>%
  mutate(l_x_max = case_when(target.side == 'left' ~ target.x.topleft + target.x.length,
                             TRUE ~ distractor.x.topleft + distractor.x.length),
         l_x_min = case_when(target.side == 'left' ~ target.x.topleft,
                             TRUE ~ distractor.x.topleft),
         l_y_max = case_when(target.side == 'left' ~ target.y.topleft + target.y.length,
                             TRUE ~ distractor.y.topleft + distractor.y.length),
         l_y_min = case_when(target.side == 'left' ~ target.y.topleft,
                             TRUE ~ distractor.y.topleft),
         
         r_x_max = case_when(target.side == 'right' ~ target.x.topleft + target.x.length,
                             TRUE ~ distractor.x.topleft + distractor.x.length),
         r_x_min = case_when(target.side == 'right' ~ target.x.topleft,
                             TRUE ~ distractor.x.topleft),
         r_y_max = case_when(target.side == 'right' ~ target.y.topleft + target.y.length,
                             TRUE ~ distractor.y.topleft + distractor.y.length),
         r_y_min = case_when(target.side == 'right' ~ target.y.topleft,
                             TRUE ~ distractor.y.topleft)) 

aois %>%
  left_join(aoi_region_tab, by=c("target.object" = 'target','target.side' ='target_side')) %>%
  distinct(aoi_region_set_id, l_x_max, l_x_min, l_y_max, l_y_min, r_x_max, r_x_min, r_y_max, r_y_min) %>%
write_csv(fs::path(output_path, "aoi_region_sets.csv"))
  

#  write AOI table
aoi_time_tab <- d_tidy_final2 %>% 
  mutate(
    administration_id = subject_id,
    aoi = case_when(
      look.target==1 ~ "target",
      look.distractor==1 ~ "distractor",
      is.na(look.target) ~ "missing",
      TRUE ~ "missing" # just in case
    )) %>% mutate(
      aoi_timepoint_id = 0:(n()-1)
    ) %>%
  select(aoi_timepoint_id, administration_id, t, aoi, trial_id) %>%
  mutate(t_norm = t - point_of_disambiguation) %>% 
  write_csv(fs::path(output_path, "aoi_timepoints.csv"))


# XY timepoints
d_tidy_final2 %>% distinct(trial_id, administration_id, GazePointX, GazePointY, TrialTimestamp) %>%
  mutate(x = GazePointX, 
         y = GazePointY, 
         t = TrialTimestamp,
         xy_timepoint_id = 0:(n()-1)) %>%
  write_csv(fs::path(output_path, "xy_timepoints.csv"))


#### Process data ####
peekds::validate_for_db_import(dir_csv=output_path)

#### Upload to OSF
put_processed_data(osf_token, dataset_name, paste0(output_path,'/'), osf_address = "pr6wu")