# process pomper saffran 2016 data
## libraries
library(here)
library(janitor)
library(tidyverse)
library(readxl)
library(peekds)
library(osfr)

## constants
sampling_rate_hz <- 30
sampling_rate_ms <- 33
dataset_name = "pomper_saffran_2016"
read_path <- here("data",dataset_name,"full_dataset")
write_path <- here("data",dataset_name, "processed_data/")

# processed data filenames
dataset_table_filename <- "datasets.csv"
aoi_table_filename <- "aoi_timepoints.csv"
subject_table_filename <- "subjects.csv"
administrations_table_filename <- "administrations.csv"
stimuli_table_filename <- "stimuli.csv"
trials_table_filename <- "trials.csv"
aoi_regions_table_filename <-  "aoi_region_sets.csv"
xy_table_filename <-  "xy_timepoints.csv"
osf_token <- read_lines(here("osf_token.txt"))


remove_repeat_headers <- function(d, idx_var) {
  d[d[,idx_var] != idx_var,]
}


# download datata from osf
#peekds::get_raw_data(dataset_name, path = read_path)


# read raw icoder files (is it one file per participant or aggregated?)
d_raw <- read_delim(fs::path(read_path, "pomper_saffran_2016_raw_datawiz.txt"),
                           delim = "\t")

# remove any column with all NAs (these are columns
# where there were variable names but no eye tracking data)
d_filtered <- d_raw %>%
  select_if(~sum(!is.na(.)) > 0)

# Create clean column headers --------------------------------------------------
d_processed <-  d_filtered %>%
  remove_repeat_headers(idx_var = "Months") %>%
  clean_names()

# Relabel time bins --------------------------------------------------
old_names <- colnames(d_processed)
metadata_names <- old_names[!str_detect(old_names,"x\\d|f\\d")]
pre_dis_names <- old_names[str_detect(old_names, "x\\d")]
post_dis_names  <- old_names[str_detect(old_names, "f\\d")]

pre_dis_names_clean <- seq(from = length(pre_dis_names) * sampling_rate_ms,
                           to = sampling_rate_ms,
                           by = -sampling_rate_ms) * -1

post_dis_names_clean <-  post_dis_names %>% str_remove("f")

colnames(d_processed) <- c(metadata_names, pre_dis_names_clean, post_dis_names_clean)

# Convert to long format --------------------------------------------------

# get idx of first time series
first_t_idx <- length(metadata_names) + 1             # this returns a numeric
last_t_idx <- colnames(d_processed) %>% dplyr::last() # this returns a string
d_tidy <- d_processed %>%
  tidyr::gather(t, aoi, first_t_idx:last_t_idx) # but gather() still works

# recode 0, 1, ., - as distracter, target, other, NA [check in about this]
# this leaves NA as NA
d_tidy <- d_tidy %>%
  rename(aoi_old = aoi) %>%
  mutate(aoi = case_when(
    aoi_old == "0" ~ "distractor",
    aoi_old == "1" ~ "target",
    aoi_old == "0.5" ~ "other",
    aoi_old == "." ~ "missing",
    aoi_old == "-" ~ "missing",
    is.na(aoi_old) ~ "missing"
  ))

# Go through counterbalancing files, tidy, and concatanate into one structure ----------------------------------------
order_read_path <- here("data",dataset_name,"full_dataset", "orders")
order_files = dir(order_read_path)
count_files = 0
for (o in order_files) {
  count_files = count_files+1

  # get order name from filename and make match the name in the  icoder file
  order_name = str_split_fixed(str_split_fixed(o, '-',2)[,2],'_',2)[,1]
  order_name = str_remove(order_name, '-')

  this_order = read_excel(fs::path(order_read_path, o))  %>%
    mutate(order = paste0('SwitchingCues-',order_name)) # to make icoder data for merging below

  if (count_files == 1){
    all_orders = this_order
  }
  else {
    all_orders <- all_orders %>%
      full_join(this_order)
  }
}

## clean up resulting dataframe and add easier names
all_orders_cleaned <- all_orders %>%
  rename('tr_num' = 'Tr. Num', 'condition' = 'Condition', 'target_side' = 'Target Side', 'target_image' = `Target Object`) %>%
  select(-`...10`, -`...5`, -`...11`, -Duration) %>%
  mutate(tr_num = as.character(tr_num))

# Get carrier phrases

## Carrier phrases were inconsistent and produced erorrs when joining; not including.
## Get color carrier phrases from audio file
# colors = c('Orange', 'Red','Yellow','White','Black','Brown','Blue','Green')
# color_carrier_phrases = all_orders_cleaned %>%
#   mutate(target_word = str_split_fixed(SoundStimulus, '_', 2)[,1]) %>%
#   filter(target_word %in% colors) %>%
#   mutate(carrier_try = str_split_fixed(SoundStimulus, '_', 3)[,2]) %>%
#   mutate(carrier_try = factor(carrier_try, levels=c('Find','Where','Look'), labels = c("Find the", "Where is the", "Look at the"))) %>%
#   mutate(full_phrase = paste0(carrier_try,' ', target_word, ' one')) %>%
#   select(target_word, target_image, carrier_try, full_phrase, SoundStimulus) %>%
#   distinct(target_word, target_image, carrier_try, full_phrase, SoundStimulus)

# ## Load noun carrier phrases from .csv
# all_carrier_phrases <- read_csv(here("data",dataset_name,"full_dataset", "carrier_phrases.csv")) %>% # only has nouns
#   mutate(target_word = lab_stimulus_id, target_image = lab_stimulus_id,  full_phrase = paste0(carrier_phrase,' ', lab_stimulus_id)) %>%
#   select(target_word, target_image, full_phrase) %>%
#   full_join(color_carrier_phrases) %>%
#   mutate(target_word = tolower(target_word), target_image = tolower(target_image))

# Get stimulus table for saving out with right datafields
## get every combination of word and color
stimulus_table <-  all_orders_cleaned %>%
  mutate(target_word = str_split_fixed(SoundStimulus, '_', 2)[,1]) %>%
  distinct(target_word, target_image) %>%
  mutate(target_word = tolower(target_word)) %>% # make same case
  filter(!target_image=='NA') %>% # intro/end trials
  filter(target_image != target_word) %>% # lets get object/color combinations so we have the full table, please!
  rename('color' = target_word) %>%
  mutate(stimulus_image_path = paste0('raw_data/stimuli/images/', target_image, '.jpg'),
         lab_stimulus_id = target_image, stimulus_novelty = 'familiar', dataset_id = 0) %>%
  gather(key="trial_type", value = "stimulus_label", color, target_image) %>%
  mutate(stimulus_id = seq(0, length(.$lab_stimulus_id) - 1),
         target_image = lab_stimulus_id, target_word = stimulus_label)

## join in carrier phrases with counterbalancing orders
all_orders_cleaned <- all_orders_cleaned  %>%
  mutate(target_word = tolower(str_split_fixed(all_orders_cleaned$SoundStimulus, '_', 2)[,1])) %>%
  # left_join(all_carrier_phrases, by = c('target_image','target_word')) %>% # not including because produced errors
  mutate(lab_stimulus_id = target_image, stimulus_label = target_word)

# Join back CB/trial info with tidy'd dataframes ----------------------------------------
get_distractor_id = function (trial_type, distractor_image, table){
  dist_id = table %>%
    filter(lab_stimulus_id==distractor_image & trial_type==trial_type)

  return(dist_id$stimulus_id)
}

d_tidy <- d_tidy %>%
  select(-prescreen_notes, -l_image, -c_image, -r_image, -target_side) %>%
  left_join(all_orders_cleaned, by=c('condition','tr_num', 'target_image','order')) %>%
  left_join(stimulus_table, by = c('lab_stimulus_id', 'stimulus_label'))

##
d_tidy <- d_tidy %>%
  mutate(distractor_image = case_when(target_side == "R" ~ LeftFile,
                                   TRUE ~ RightFile)) %>%
  mutate(target_id = stimulus_id) %>%
  select(-stimulus_id) %>%
  left_join(stimulus_table %>% select(trial_type, lab_stimulus_id, stimulus_id), by=c('trial_type' = 'trial_type', 'distractor_image' = 'lab_stimulus_id')) %>%
  mutate(distractor_id = stimulus_id) %>%
  select(-stimulus_id)

# create dataset variables
d_tidy <- d_tidy %>%
  mutate(lab_dataset_id = "pomper_saffran_2016",
         tracker = "video_camera",
         monitor = NA,
         monitor_sr = NA,
         sample_rate = sampling_rate_hz)

# get zero-indexed subject ids
d_subject_ids <- d_tidy %>%
  distinct(sub_num) %>%
  mutate(subject_id = seq(0, length(.$sub_num) - 1))

# create zero-indexed ids for trials
d_trial_ids <- d_tidy %>%
  distinct(order, tr_num, target_id, distractor_id, target_side) %>%
  mutate(trial_id = seq(0, length(.$tr_num) - 1))

# joins
d_tidy_semifinal <- d_tidy %>%
  mutate(aoi_data_id = seq(0, nrow(d_tidy) - 1)) %>%
  left_join(d_subject_ids, by = "sub_num") %>%
  left_join(d_trial_ids) %>%
  select(-target_image.y, -target_word.y) # duplicate values

# add some more variables to match schema
d_tidy_final <- d_tidy_semifinal %>%
  mutate(distractor_label = distractor_image,
         dataset_id = 0, # dataset id is always zero indexed since there's only one dataset
         target_label = target_image.x,
         lab_trial_id = paste(order, tr_num, sep = "-"),
         full_phrase = NA,
         administration_id = 0,
         aoi_region_set_id = NA, # was aoi_region_id
         monitor_size_x = NA, # 140cm .. diagonal?
         monitor_size_y = NA,
         lab_age_units = "months",
         age = as.numeric(months), # months
         point_of_disambiguation = 0 # unsure what 1024 was?
         ) %>%
  rename(lab_subject_id = sub_num,
         lab_age = months
         )

##### AOI TABLE ####
d_tidy_final %>%
  select(aoi_data_id, subject_id, t, aoi, trial_id, administration_id) %>%
  rename(aoi_timepoint_id = aoi_data_id,
         t_norm = t) %>% # original data had columns from -990ms to 6867ms...presumably centered at disambiguation per trial?
  write_csv(fs::path(write_path, aoi_table_filename))

##### SUBJECTS TABLE ####
d_tidy_final %>%
  distinct(subject_id, lab_subject_id, sex) %>%
  mutate(sex = factor(sex, levels = c('M','F'), labels = c('male','female'))) %>%
  write_csv(fs::path(write_path, subject_table_filename))

##### ADMINISTRATIONS TABLE ####
d_tidy_final %>%
  distinct(administration_id,
           dataset_id,
           subject_id,
           age,
           lab_age,
           lab_age_units,
           monitor_size_x,
           monitor_size_y,
           sample_rate,
           tracker) %>%
  mutate(coding_method = "manual gaze coding") %>%
  write_csv(fs::path(write_path, administrations_table_filename))

##### STIMULUS TABLE ####
stimulus_table %>%
  select(-trial_type, -target_word, -target_image) %>%
  write_csv(fs::path(write_path, stimuli_table_filename))

##### TRIALS TABLE ####
d_tidy_final %>%
  distinct(trial_id,
           full_phrase,
           point_of_disambiguation,
           target_side,
           lab_trial_id,
           aoi_region_set_id,
           dataset_id,
           target_id,
           distractor_id, 
           distractor_label,
           target_label) %>%
    mutate(full_phrase_language = "eng") %>%
    select(-distractor_label, -target_label) %>%
      write_csv(fs::path(write_path, trials_table_filename))

##### AOI REGIONS TABLE ####
# create empty other files aoi_region_sets.csv and xy_timepoints
# don't need 
# tibble(administration_id = d_tidy_final$administration_id[1],
#       aoi_region_set_id=NA,
#        l_x_max=NA ,
#        l_x_min=NA ,
#        l_y_max=NA ,
#        l_y_min=NA ,
#        r_x_max=NA ,
#        r_x_min=NA ,
#        r_y_max=NA ,
#        r_y_min=NA ) %>%
#   write_csv(fs::path(write_path, aoi_regions_table_filename))

##### XY TIMEPOINTS TABLE ####
# d_tidy_final %>% distinct(trial_id, administration_id) %>%
#   mutate(x = NA,
#          y = NA,
#          t = NA,
#          xy_timepoint_id = 0:(n()-1)) %>%
#   write_csv(fs::path(write_path, xy_table_filename))

##### DATASETS TABLE ####
# write Dataset table
data_tab <- tibble(
  dataset_id = 0, # doesn't matter (leave as 0 for all)
  dataset_name = "pomper_saffran_2016",
  lab_dataset_id = "SwitchingCues", # internal name from the lab (if known)
  cite = "Pomper, R., & Saffran, J. R. (2016). Roses Are Red, Socks Are Blue: Switching Dimensions Disrupts Young Children’s Language Comprehension. Plos one, 11(6), e0158459.
Chicago",
  shortcite = "Pomper & Saffran (2016)"
) %>%
  write_csv(fs::path(write_path, dataset_table_filename))


# validation check ----------------------------------------------------------
validate_for_db_import(dir_csv = write_path)

## OSF INTEGRATION ###
put_processed_data(osf_token, dataset_name, write_path, osf_address = "pr6wu")