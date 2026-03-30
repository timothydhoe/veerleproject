library('dplyr')
library('readr')
library('signal')
library('data.table')
library('GGIR')
library('randomForest')
library('lubridate')

folder_functions = "E:/Eigen versie/1_thigh_PA_type/"
source(paste0(folder_functions, 'resample_boundaries_calibration.R'))
source(paste0(folder_functions, 'generate_activity_features.R'))
source(paste0(folder_functions, 'predict_AT.R'))
source(paste0(folder_functions, 'rbind_5s.R'))
# source(paste0(folder_functions, 'aggregate_5s_min.R'))
source(paste0(folder_functions, 'enmo_nonwear.R'))

tz_local = 'Europe/Brussels'

folder_data = "E:/Eigen versie/"
folder_adm = paste0(folder_data, "0_admin/")
folder_raw = paste0(folder_data, "1_raw/")
folder_ggi = paste0(folder_data, "1_gpart_meta/")
folder_cal = paste0(folder_data, "0_calibrated/")
folder_axi = paste0(folder_data, "1_axivity_prep/")
folder_fea = paste0(folder_data, "2_features/")
folder_pre = paste0(folder_data, "3_activity_type_pred/")
folder_bout = paste0(folder_data, "4_activity_type_5s_bout/")
folder_min = paste0(folder_data, "4_activity_type_minute/")
folder_sec_all = paste0(folder_data, "4_all_by_5sec/")
folder_enm = paste0(folder_data, "4_enmo_nonwear_minute/")
folder_agg = paste0(folder_data, "5_activity_type_complete/")
folder_agg_bout = paste0(folder_data, "6_activity_type_complete_by_bout/")

#########
# rough bounds
# no longer applicable
#########

# meta_school = data.table(haven::read_spss(paste0(folder_adm, 'Dataset_Scholen.sav')))
# 
# start_school = meta_school[, .(start = ymd(min(Datum))), by = Schoolnummer]
# stopp_school = meta_school[, .(stop  = ymd(max(Datum)) + days(1)), by = Schoolnummer]
# 
# bound = data.table(pid = substr(dir(folder_raw), 1, 3))
# bound[, Schoolnummer := as.numeric(substr(pid, 1, 1))]
# 
# bound = merge(bound, start_school, by = 'Schoolnummer')
# bound = merge(bound, stopp_school, by = 'Schoolnummer')
# 
# readr::write_rds(bound, paste0(folder_adm, 'boundaries.Rds'))
# bound = readr::read_rds(paste0(folder_adm, 'boundaries.Rds'))

################
# prepare axivity data (set boundaries, resample and calibrate)
################

# parts = gsub('.cwa', '', dir(folder_raw))
# parts = parts[which(parts != 'settings')]
# #big_files = c('102_PRE', '112_PRE', '315_PRE', '407_PRE', '605_POS', '607_POS', '614_POS')
# for(part in parts){
#   #if (part %in% big_files){
#   #next
#   #}
#   print(part)
#   resam_bound_callib(part, folder_raw, folder_axi, folder_cal, 'UTC')
#   print('Finished')
# }

##################
# functie features
##################

# parts = substr(dir(folder_axi), 1, 7)
# parts_done = substr(dir(folder_fea), 1, 7)
# parts = parts[which(!parts %in% c(parts_done))]
# #c('111_NUL','205_PRE','213_NUL','213_PRE','241_NUL','254_PRE','121_PRE','123_POS','125_POS','126_POS','128_PRE','131_PRE','204_NUL','212_POS','224_POS','231_POS','238_POS',parts_done)
# for(part in parts){
#   generate_activity_features(part = part, folder_inn = folder_axi, folder_out = folder_fea)
# }

################
# predict
################

# folder_rf = 'C:/Users/vvoeckel/Documents/Eigen versie/1_thigh_PA_type/RF_models_kids_PA_type/'
# model_AT = read_rds(paste0(folder_rf, 'model.rf.thigh.rds'))
# 
# parts = substr(dir(folder_fea), 1, 7)
# 
# for(part in parts){
#   predict_AT(part = part, folder_inn = folder_fea, folder_out = folder_pre, rf_model = model_AT)
# }

################
# ENMO en nonwear via gpart
# i.e. eerste deel van de GGIR_shell (of de volledig shell) laten lopen
################

# GGIR::g.part1(folder_raw, folder_ggi, f1 = length(dir(folder_raw)),
#               chunksize = 1, windowsizes = c(1, 900, 3600),
#               overwrite = FALSE, desiredtz = 'Europe/Brussels')

################
# rbind the GGIR results: ENMO + detected nonwear by minute

# parts = gsub('.cwa', '', dir(folder_raw))
# parts = parts[which(!parts %in% c('settings'))]
# 
# for(part in parts){
#   print(part)
# 
#   enmo_nonwear_min = enmo_nonwear_to_min(part, folder_ggi, tz_local)
# 
#   if(part == parts[1]){
#     enmo_nonwear_all = copy(enmo_nonwear_min)
#   }else{
#     enmo_nonwear_all = rbindlist(list(enmo_nonwear_all, enmo_nonwear_min))
#   }
# }
# 
# write_rds(enmo_nonwear_all, paste0(folder_enm, 'enmo_nonwear_per_minute.Rds'))

################
# We opted for 5 second epochs for the activity type. So, per minute, several activities are possible.
# (Before we opted for a 1 minute epoch, by using the most common activity for that minute.)
# There are also bouts of sedentary time detected 
# i.e. 1-4 min, 5-9, 10-19, 20-29 and 30+. 
# The bouts are mutually exclusive, i.e. to know all time spend in bouts of at least 5 minutes, 
# you need to add up the time in bouts of at least 5 minutes. 
################

# parts = substr(dir(folder_pre), 1, 7)
# 
# rbind_5s(parts = parts, folder_inn = folder_pre, folder_bout = folder_bout)

##############
# 5s data 

AT_sec = read_rds(paste0(folder_bout, 'Activity_type_bout_per_5s.Rds'))

################
# add variables from admin data: outside school hours and outside observation period (hours of school visits)
################
# observatie period (per school)
# school hours info (per school)

meta_school = data.table(haven::read_spss(paste0(folder_adm, 'Dataset_Scholen.sav')))

start_nul = meta_school[!is.na(Startuur_Meting_NUL), .(Schoolnummer = Schoolnummer, time = 'NUL', 
                                                       start_datum = ymd_hms(paste0(Datum_NUL, Startuur_Meting_NUL), tz = tz_local))]
stopp_nul = meta_school[!is.na(Einduur_Meting_NUL), .(Schoolnummer = Schoolnummer, 
                                                      stopp_datum = ymd_hms(paste0(Datum_NUL, Einduur_Meting_NUL), tz = tz_local))]

start_pre = meta_school[!is.na(Startuur_Meting_PRE), .(Schoolnummer = Schoolnummer, time = 'PRE', 
                                                       start_datum = ymd_hms(paste0(Datum_PRE, Startuur_Meting_PRE), tz = tz_local))]
stopp_pre = meta_school[!is.na(Einduur_Meting_PRE), .(Schoolnummer = Schoolnummer, 
                                                      stopp_datum = ymd_hms(paste0(Datum_PRE, Einduur_Meting_PRE), tz = tz_local))]

start_pos = meta_school[!is.na(Startuur_Meting_POST), .(Schoolnummer = Schoolnummer, time = 'POST',
                                                        start_datum = ymd_hms(paste0(Datum_POST, Startuur_Meting_POST), tz = tz_local))]
stopp_pos = meta_school[!is.na(Einduur_Meting_POST), .(Schoolnummer = Schoolnummer, 
                                                       stopp_datum = ymd_hms(paste0(Datum_POST, Einduur_Meting_POST), tz = tz_local))]
observation_period = rbindlist(list(merge(start_nul, stopp_nul, by = 'Schoolnummer'),
                                    merge(start_pre, stopp_pre, by = 'Schoolnummer'),
                                    merge(start_pos, stopp_pos, by = 'Schoolnummer')))

school_hours_nul = meta_school[, .(Schoolnummer, 
                                   Datum = Datum_NUL,
                                   Startuur_School, Einduur_School, 
                                   Startuur_Lesuur1, Einduur_Lesuur1, 
                                   Startuur_Lesuur2, Einduur_Lesuur2, 
                                   Startuur_Lesuur3, Einduur_Lesuur3, 
                                   Startuur_Lesuur4, Einduur_Lesuur4, 
                                   Startuur_Lesuur5, Einduur_Lesuur5, 
                                   Startuur_Lesuur6, Einduur_Lesuur6, 
                                   Startuur_Lesuur7, Einduur_Lesuur7)]

school_hours_pre = meta_school[, .(Schoolnummer, 
                                   Datum = Datum_PRE,
                                   Startuur_School, Einduur_School, 
                                   Startuur_Lesuur1, Einduur_Lesuur1, 
                                   Startuur_Lesuur2, Einduur_Lesuur2, 
                                   Startuur_Lesuur3, Einduur_Lesuur3, 
                                   Startuur_Lesuur4, Einduur_Lesuur4, 
                                   Startuur_Lesuur5, Einduur_Lesuur5, 
                                   Startuur_Lesuur6, Einduur_Lesuur6, 
                                   Startuur_Lesuur7, Einduur_Lesuur7)]

school_hours_post = meta_school[, .(Schoolnummer, 
                                    Datum = Datum_POST,
                                    Startuur_School, Einduur_School, 
                                    Startuur_Lesuur1, Einduur_Lesuur1, 
                                    Startuur_Lesuur2, Einduur_Lesuur2, 
                                    Startuur_Lesuur3, Einduur_Lesuur3, 
                                    Startuur_Lesuur4, Einduur_Lesuur4, 
                                    Startuur_Lesuur5, Einduur_Lesuur5, 
                                    Startuur_Lesuur6, Einduur_Lesuur6, 
                                    Startuur_Lesuur7, Einduur_Lesuur7)]
school_hours = rbindlist(list(school_hours_nul, school_hours_pre, school_hours_post))

# apply observation period and school time simultaneously

AT_sec[, ':='(Schoolnummer = substr(pid, 1, 1),
              time = substr(pid, 5, 7),
              during_observation = 0,
              during_school_hours = 0,
              during_class_1 = 0,
              during_class_2 = 0,
              during_class_3 = 0,
              during_class_4 = 0,
              during_class_5 = 0,
              during_class_6 = 0,
              during_class_7 = 0)]
AT_sec[, pid := substr(pid, 1, 3)]

for(i in unique(AT_sec[, Schoolnummer])){
  # during observation period (3 per school)
  observation_period_i = observation_period[Schoolnummer == i] 
  for(j in 1:nrow(observation_period_i)){
    start_school = observation_period_i[j, start_datum]
    stopp_school = observation_period_i[j, stopp_datum]
    AT_sec[Schoolnummer == i & timestamp >= start_school & timestamp < stopp_school, during_observation := 1]
  }
  
  # during school hours and classes
  school_hours_i = school_hours[Schoolnummer == i] 
  
  for(k in 1:nrow(school_hours_i)){
    # school hours
    start_schoolday = school_hours_i[k, ymd_hms(paste(Datum, Startuur_School), tz = tz_local)]
    stopp_schoolday = school_hours_i[k, ymd_hms(paste(Datum, Einduur_School), tz = tz_local)]
    AT_sec[Schoolnummer == i & timestamp >= start_schoolday & timestamp < stopp_schoolday, during_school_hours := 1]
    
    # class 1
    if(!is.na(school_hours_i[k, Startuur_Lesuur1])){
      start_class1 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur1), tz = tz_local)]
      stopp_class1 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur1), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class1 & timestamp < stopp_class1, during_class_1 := 1]
    }
    
    # class 2
    if(!is.na(school_hours_i[k, Startuur_Lesuur2])){
      start_class2 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur2), tz = tz_local)]
      stopp_class2 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur2), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class2 & timestamp < stopp_class2, during_class_2 := 1]
      }
    
    # class 3
    if(!is.na(school_hours_i[k, Startuur_Lesuur3])){
      start_class3 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur3), tz = tz_local)]
      stopp_class3 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur3), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class3 & timestamp < stopp_class3, during_class_3 := 1]
      }
    
    # class 4
    if(!is.na(school_hours_i[k, Startuur_Lesuur4])){
      start_class4 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur4), tz = tz_local)]
      stopp_class4 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur4), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class4 & timestamp < stopp_class4, during_class_4 := 1]
      }
    
    # class 5
    if(!is.na(school_hours_i[k, Startuur_Lesuur5])){
      start_class5 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur5), tz = tz_local)]
      stopp_class5 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur5), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class5 & timestamp < stopp_class5, during_class_5 := 1]
      }
    
    # class 6
    if(!is.na(school_hours_i[k, Startuur_Lesuur6])){
      start_class6 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur6), tz = tz_local)]
      stopp_class6 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur6), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class6 & timestamp < stopp_class6, during_class_6 := 1]
      }
    
    # class 7
    if(!is.na(school_hours_i[k, Startuur_Lesuur7])){
      start_class7 = school_hours_i[k, ymd_hms(paste(Datum, Startuur_Lesuur7), tz = tz_local)]
      stopp_class7 = school_hours_i[k, ymd_hms(paste(Datum, Einduur_Lesuur7), tz = tz_local)]
      AT_sec[Schoolnummer == i & timestamp >= start_class7 & timestamp < stopp_class7, during_class_7 := 1]
      }
  }
}

# AT_sec[Schoolnummer == i & during_observation == 1 & during_class_7 == 1, .(pid, timestamp)] 

######################
# absentees students
######################

meta_afwezig = data.table(haven::read_spss(paste0(folder_adm, 'Dataset_Afwezigheden.sav')))
AT_sec[, absent := 0]

for(i in unique(meta_afwezig[, ID])){
  # during observation period
  start_afwezig = meta_afwezig[ID == i, ymd_hms(paste(Datum_afwezig, Beginuur_afwezig), tz = tz_local)]
  stopp_afwezig = meta_afwezig[ID == i, ymd_hms(paste(Datum_afwezig,  Einduur_afwezig), tz = tz_local)]
  
  for(j in 1:length(start_afwezig)){
    if(!is.na(start_afwezig[j]) & !is.na(stopp_afwezig[j])){
      AT_sec[pid == i & timestamp >= start_afwezig[j] & timestamp < stopp_afwezig[j], absent := 1]
    }
  }
}

######################
# sleep time (as detected by Axivity)
######################

meta_sleep = data.table(haven::read_spss(paste0(folder_adm, 'Databestand_Slaap.sav')))
AT_sec[, sleep_axivity := 0]

for(i in unique(meta_sleep[, ID])){
  # during observation period
  start_sleep = meta_sleep[ID == i, ymd_hms(paste(Date_Bedtime, Hour_Bedtime), tz = tz_local)]
  stopp_sleep = meta_sleep[ID == i, ymd_hms(paste(Date_Wakeuptime,  Hour_Wakeuptime), tz = tz_local)]
  
  for(j in 1:length(start_sleep)){
    if(!is.na(start_sleep[j]) & !is.na(stopp_sleep[j])){
      AT_sec[pid == i & timestamp >= start_sleep[j] & timestamp < stopp_sleep[j], sleep_axivity := 1]
    }
  }
}

# use Axivity sleep for the activity

AT_sec[, activity_type_original := activity_type]
AT_sec[sleep_axivity == 1, activity_type := 'Sleeping']

######################
# non wear reported by students
######################

meta_leerlingen = data.table(haven::read_spss(paste0(folder_adm, 'Dataset_Leerlingen.sav')))
AT_sec[, nonwear_reported := 0]

for(i in unique(meta_leerlingen[, ID])){
  # during observation period
  start_nonwear = meta_leerlingen[ID == i, ymd_hms(paste(Datum_Start_Nonwear, Startuur_Nonwear), tz = tz_local)]
  stopp_nonwear = meta_leerlingen[ID == i, ymd_hms(paste(Datum_Stop_Nonwear,  Einduur_Nonwear), tz = tz_local)]
  
  for(j in 1:length(start_nonwear)){
    if(!is.na(start_nonwear[j]) & !is.na(stopp_nonwear[j])){
      AT_sec[pid == i & timestamp >= start_nonwear[j] & timestamp < stopp_nonwear[j], nonwear_reported := 1]
    }
  }
}

######################
# non wear detected by GGIR (per minute)
######################

# read nonwear

enmo_nonwear_min = read_rds(paste0(folder_enm, 'enmo_nonwear_per_minute.Rds'))
enmo_nonwear_min[nonwearscore > 1, nonwearscore := 1]

# merge

AT_sec[, timestamp_minute := floor_date(timestamp, unit = '1 min')]
setnames(enmo_nonwear_min, c( 'nonwearscore'), c('nonwear_detected'))
# enmo_nonwear_min[, time := substr(pid, 5, 7)]
enmo_nonwear_min[, pid := substr(pid, 1, 3)]

AT_sec = merge(AT_sec, enmo_nonwear_min, by = c('pid', 'timestamp_minute'), all = TRUE)

######################
# It's possible that at the start and end of a person's data, there are some minutes not recognized as valid
# data by GGIR. I assume there is a good reason for this (calibration or other), and delete also the activity type data. 

AT_sec[is.na(ENMO), ':=' (activity_type = NA,
                          activity_type_original = NA)]

######################
# nonwear changes
# if sleep Axivity, no non-wear detected or reported

AT_sec[activity_type == 'Sleeping', ':=' (nonwear_detected = 0,
                                          nonwear_reported = 0)]

# unique nonwear indicator 

AT_sec[, nonwear_unique := nonwear_detected + nonwear_reported]
AT_sec[is.na(nonwear_detected) & nonwear_reported == 1, nonwear_unique := 1]

AT_sec[nonwear_unique > 1, nonwear_unique := 1]

# delete all data from 'activity_type' that is not during observation time, or during nonwear

AT_sec[nonwear_unique == 1 | during_observation == 0, activity_type := NA]

##############
# where was the activity

AT_sec[,at_school_activity := 0]
AT_sec[nonwear_unique == 0 & during_observation == 1 & during_school_hours == 1 & absent == 0, 
       at_school_activity := 1]

AT_sec[,in_class_activity := 0]
AT_sec[nonwear_unique == 0 & during_observation == 1 & during_school_hours == 1 & absent == 0 &
         (during_class_1 == 1 | during_class_2 == 1 | during_class_3 == 1 | during_class_4 == 1 | 
            during_class_5 == 1 | during_class_6 == 1 | during_class_7 == 1), 
       in_class_activity := 1]

AT_sec[,out_class_activity := 0]
AT_sec[nonwear_unique == 0 & during_observation == 1 & during_school_hours == 1 & absent == 0 &
         (during_class_1 == 0 & during_class_2 == 0 & during_class_3 == 0 & during_class_4 == 0 & 
            during_class_5 == 0 & during_class_6 == 0 & during_class_7 == 0), 
       out_class_activity := 1]

AT_sec[,out_school_activity := 0]
AT_sec[(nonwear_unique == 0 & during_observation == 1 & during_school_hours == 0) | 
         (nonwear_unique == 0 & during_observation == 1 & during_school_hours == 1 
          & absent == 1), out_school_activity := 1]

# table(AT_sec[, .( in_class_activity, out_class_activity, at_school_activity)], useNA = 'ifany')

######################
# sitting/lying bouts detection, outside of sleeptime
# however, if non-sitting is below 30 seconds, we set this also as sitting time since
# the bout is not interrupted for long enough

# just to be sure, order the data correctly

setkey(AT_sec, pid, time, timestamp)

# first: recognize non-sitting bouts 

AT_sec[, bout_nummer_no_sitting := 0]
AT_sec[!activity_type %in% c('Sitting', 'Lying'), bout_nummer_no_sitting := 1]
AT_sec[shift(bout_nummer_no_sitting) == 1, bout_nummer_no_sitting := 0]
AT_sec[, bout_nummer_no_sitting := cumsum(bout_nummer_no_sitting), by = c('pid', 'time')]
AT_sec[activity_type %in% c('Sitting', 'Lying'), bout_nummer_no_sitting := 0]
AT_sec[is.na(activity_type), bout_nummer_no_sitting := NA]

# calculate time of non-sitting bouts (i.e. time between 2 sitting bouts)

AT_sec[, bout_time_no_sitting := .N, by = c('pid', 'time', 'bout_nummer_no_sitting')]
AT_sec[activity_type %in% c('Sitting', 'Lying'), bout_time_no_sitting := 0]
AT_sec[is.na(activity_type), bout_time_no_sitting := NA]

## before, an interruption of 30 sec was needed to get a new bout 
## now interruption of 5 sec is enough 

AT_sec[, sitting := 0]
AT_sec[activity_type %in% c('Sitting', 'Lying'), sitting := 1]
# AT_sec[bout_time_no_sitting < 6, sitting := 1]
# AT_sec[bout_time_no_sitting < 3, sitting := 1]
AT_sec[is.na(activity_type), sitting := NA]

# recognize sitting bouts with new variable

AT_sec[, bout_nummer_sitting := 0]
AT_sec[sitting == 1, bout_nummer_sitting := 1]
AT_sec[shift(bout_nummer_sitting) == 1, bout_nummer_sitting := 0]
AT_sec[, bout_nummer_sitting := cumsum(bout_nummer_sitting), by = c('pid', 'time')]
AT_sec[sitting != 1, bout_nummer_sitting := 0]
AT_sec[is.na(activity_type), bout_nummer_sitting := NA]

# calculate time (in min) of sitting bouts

AT_sec[, bout_time_sitting := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]
AT_sec[sitting == 0, bout_time_sitting := 0]
AT_sec[is.na(activity_type), bout_time_sitting := NA]

##########
# !!!!!!
# split up some bouts that overlap start/end of school hours and in/out class hours
# per regular bout, how much during school/class and how much outside 

AT_sec[at_school_activity == 1, bout_time_sitting_exclusive_school := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]

AT_sec[at_school_activity == 1 & in_class_activity == 1, bout_time_sitting_in_class := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]
AT_sec[at_school_activity == 1 & in_class_activity == 1 & bout_nummer_sitting !=0, bout_time_sitting_exclusive_in_class := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]

AT_sec[at_school_activity == 1 & out_class_activity == 1, bout_time_sitting_out_class := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]
AT_sec[at_school_activity == 1 & out_class_activity == 1 & bout_nummer_sitting !=0, bout_time_sitting_exclusive_out_class := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]

AT_sec[out_school_activity == 1, bout_time_sitting_exclusive_outside := round(.N/12, 4), by = c('pid', 'time', 'bout_nummer_sitting')]

vars_max = c("bout_time_sitting_exclusive_school", "bout_time_sitting_in_class", "bout_time_sitting_exclusive_in_class",
             "bout_time_sitting_out_class", "bout_time_sitting_exclusive_out_class", "bout_time_sitting_exclusive_outside")

max_inf = function(x){
  temp = max(x, na.rm = TRUE)
  if(length(is.infinite(temp)) > 0){temp[is.infinite(temp)] <- 0}
  temp
}
AT_sec[, (vars_max) := lapply(.SD, max_inf), .SDcols = vars_max, by = c('pid', 'time', 'bout_nummer_sitting')]

AT_sec[sitting == 0, ':=' (bout_time_sitting_exclusive_school = 0,
                           bout_time_sitting_in_class = 0,
                           bout_time_sitting_exclusive_in_class = 0,
                           bout_time_sitting_out_class = 0,
                           bout_time_sitting_exclusive_out_class = 0,
                           bout_time_sitting_exclusive_outside = 0)]
AT_sec[is.na(activity_type), ':=' (bout_time_sitting_exclusive_school = NA,
                                   bout_time_sitting_in_class = NA,
                                   bout_time_sitting_exclusive_in_class = NA,
                                   bout_time_sitting_out_class = NA,
                                   bout_time_sitting_exclusive_out_class = NA,
                                   bout_time_sitting_exclusive_outside = NA)]

###################################
# daily summary of bouts
# bout duration 
# Indicators of bout time, easy to aggregate to 1 minute, 
# while still keeping 5 sec as lowest detection level (i.e. decimals per minute are allowed).
# write_rds(AT_sec, paste0(folder_bout, 'Activity_type_bout_per_5s_temp.Rds'), compress = 'gz')
# AT_sec = read_rds(paste0(folder_bout, 'Activity_type_bout_per_5s_temp.Rds'))

AT_bout = unique(AT_sec[during_observation == 1 & sitting == 1 & 
                          bout_nummer_sitting != 0 & nonwear_unique == 0, 
                        .(pid, time, timestamp, obs_day, Schoolnummer, 
                          during_school_hours, 
                          absent, nonwear_reported, nonwear_detected,
                          at_school_activity, out_school_activity,
                          in_class_activity, out_class_activity,
                          bout_nummer_sitting, bout_time_sitting, 
                          bout_time_sitting_exclusive_school, 
                          bout_time_sitting_in_class,
                          bout_time_sitting_exclusive_in_class,
                          bout_time_sitting_out_class,
                          bout_time_sitting_exclusive_out_class,
                          bout_time_sitting_exclusive_outside)], by = c('pid', 'time', 'bout_nummer_sitting'))

# type of bout    

AT_bout[, ':=' (bout_0_1 = 0, bout_1_4 = 0, bout_5_9 = 0, bout_10_19 = 0, bout_20_29 = 0, bout_30 = 0)]
AT_bout[bout_time_sitting <  1                          , bout_0_1   := 1]
AT_bout[bout_time_sitting >= 1  & bout_time_sitting <  5, bout_1_4   := 1]
AT_bout[bout_time_sitting >= 5  & bout_time_sitting < 10, bout_5_9   := 1]
AT_bout[bout_time_sitting >= 10 & bout_time_sitting < 20, bout_10_19 := 1]
AT_bout[bout_time_sitting >= 20 & bout_time_sitting < 30, bout_20_29 := 1]
AT_bout[bout_time_sitting >= 30                         , bout_30    := 1]

# total time = during observation time, no nonwear or sleep reported
# at school = activity during observation time, school time, while attending, no nonwear 
# elsewhere = activity during observation time, outside school time unless non-attendance is reported, no nonwear 

# calculate number of bouts + time during those bouts
# number of bouts total 

AT_bout[, ':=' (n_bout_0_1_total = 0, 
                n_bout_1_4_total = 0, 
                n_bout_5_9_total = 0, 
                n_bout_10_19_total = 0, 
                n_bout_20_29_total = 0, 
                n_bout_30_total = 0)]

AT_bout[bout_time_sitting <  1                          , 
        n_bout_0_1_total   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 1  & bout_time_sitting <  5, 
        n_bout_1_4_total   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 5  & bout_time_sitting < 10, 
        n_bout_5_9_total   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 10 & bout_time_sitting < 20, 
        n_bout_10_19_total := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 20 & bout_time_sitting < 30, 
        n_bout_20_29_total := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 30                         , 
        n_bout_30_total    := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]

AT_bout[bout_time_sitting <  1                          , 
        time_bout_0_1_total   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 1  & bout_time_sitting <  5, 
        time_bout_1_4_total   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 5  & bout_time_sitting < 10, 
        time_bout_5_9_total   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 10 & bout_time_sitting < 20, 
        time_bout_10_19_total := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 20 & bout_time_sitting < 30, 
        time_bout_20_29_total := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 30                         , 
        time_bout_30_total    := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]

# number of bouts at school 

AT_bout[, ':=' (n_bout_0_1_at_school = 0, 
                n_bout_1_4_at_school = 0, 
                n_bout_5_9_at_school = 0, 
                n_bout_10_19_at_school = 0, 
                n_bout_20_29_at_school = 0, 
                n_bout_30_at_school = 0)]

AT_bout[at_school_activity  == 1 & bout_time_sitting <  1                          , 
        n_bout_0_1_at_school   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        n_bout_1_4_at_school   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        n_bout_5_9_at_school   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        n_bout_10_19_at_school := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        n_bout_20_29_at_school := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 30                         , 
        n_bout_30_at_school    := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]

AT_bout[at_school_activity  == 1 & bout_time_sitting <  1                          , 
        time_bout_0_1_at_school   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        time_bout_1_4_at_school   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        time_bout_5_9_at_school   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        time_bout_10_19_at_school := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        time_bout_20_29_at_school := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[at_school_activity  == 1 & bout_time_sitting >= 30                         , 
        time_bout_30_at_school    := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]

# bouts in class 

AT_bout[, ':=' (n_bout_0_1_in_class = 0, 
                n_bout_1_4_in_class = 0, 
                n_bout_5_9_in_class = 0, 
                n_bout_10_19_in_class = 0, 
                n_bout_20_29_in_class = 0, 
                n_bout_30_in_class = 0)]

AT_bout[in_class_activity  == 1 & bout_time_sitting <  1                          , 
        n_bout_0_1_in_class   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        n_bout_1_4_in_class   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        n_bout_5_9_in_class   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        n_bout_10_19_in_class := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        n_bout_20_29_in_class := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 30                         , 
        n_bout_30_in_class    := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]

AT_bout[in_class_activity  == 1 & bout_time_sitting <  1                          , 
        time_bout_0_1_in_class   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        time_bout_1_4_in_class   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        time_bout_5_9_in_class   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        time_bout_10_19_in_class := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        time_bout_20_29_in_class := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[in_class_activity  == 1 & bout_time_sitting >= 30                         , 
        time_bout_30_in_class    := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]

# bouts out class 

AT_bout[, ':=' (n_bout_0_1_out_class = 0, 
                n_bout_1_4_out_class = 0, 
                n_bout_5_9_out_class = 0, 
                n_bout_10_19_out_class = 0, 
                n_bout_20_29_out_class = 0, 
                n_bout_30_out_class = 0)]

AT_bout[out_class_activity  == 1 & bout_time_sitting <  1                          , 
        n_bout_0_1_out_class   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        n_bout_1_4_out_class   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        n_bout_5_9_out_class   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        n_bout_10_19_out_class := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        n_bout_20_29_out_class := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 30                         , 
        n_bout_30_out_class    := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]

AT_bout[out_class_activity  == 1 & bout_time_sitting <  1                          , 
        time_bout_0_1_out_class   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        time_bout_1_4_out_class   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        time_bout_5_9_out_class   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        time_bout_10_19_out_class := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        time_bout_20_29_out_class := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_class_activity  == 1 & bout_time_sitting >= 30                         , 
        time_bout_30_out_class    := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]

# number of bouts elsewhere 

AT_bout[, ':=' (n_bout_0_1_elsewhere = 0, 
                n_bout_1_4_elsewhere = 0, 
                n_bout_5_9_elsewhere = 0, 
                n_bout_10_19_elsewhere = 0, 
                n_bout_20_29_elsewhere = 0, 
                n_bout_30_elsewhere = 0)]

AT_bout[out_school_activity == 1 & bout_time_sitting <  1                          , 
        n_bout_0_1_elsewhere   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        n_bout_1_4_elsewhere   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        n_bout_5_9_elsewhere   := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        n_bout_10_19_elsewhere := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        n_bout_20_29_elsewhere := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity == 1 & bout_time_sitting >= 30                         , 
        n_bout_30_elsewhere    := uniqueN(bout_nummer_sitting), by = c('pid', 'time', 'obs_day')]

AT_bout[out_school_activity  == 1 & bout_time_sitting <  1                          , 
        time_bout_0_1_elsewhere   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity  == 1 & bout_time_sitting >= 1  & bout_time_sitting <  5, 
        time_bout_1_4_elsewhere   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity  == 1 & bout_time_sitting >= 5  & bout_time_sitting < 10, 
        time_bout_5_9_elsewhere   := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity  == 1 & bout_time_sitting >= 10 & bout_time_sitting < 20, 
        time_bout_10_19_elsewhere := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity  == 1 & bout_time_sitting >= 20 & bout_time_sitting < 30, 
        time_bout_20_29_elsewhere := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[out_school_activity  == 1 & bout_time_sitting >= 30                         , 
        time_bout_30_elsewhere    := sum(bout_time_sitting, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]

# alternative bout_30: splitting some bouts if overlap with school hours

AT_bout[bout_time_sitting >= 30                         , 
        time_bout_30_exclusive_school    := sum(bout_time_sitting_exclusive_school, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 30                         , 
        time_bout_30_exclusive_elsewhere := sum(bout_time_sitting_exclusive_outside, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 30                         , 
        time_bout_30_exclusive_in_class  := sum(bout_time_sitting_exclusive_in_class, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]
AT_bout[bout_time_sitting >= 30                         , 
        time_bout_30_exclusive_out_class := sum(bout_time_sitting_exclusive_out_class, na.rm = TRUE), by = c('pid', 'time', 'obs_day')]

# take maximum, so that missing values get overwritten 

vars_max = c("n_bout_0_1_total", "n_bout_1_4_total", "n_bout_5_9_total", 
             "n_bout_10_19_total", "n_bout_20_29_total", "n_bout_30_total", 
             "time_bout_0_1_total", "time_bout_1_4_total", "time_bout_5_9_total", 
             "time_bout_10_19_total", "time_bout_20_29_total", "time_bout_30_total", 
             "n_bout_0_1_at_school",  "n_bout_1_4_at_school",  "n_bout_5_9_at_school",  
             "n_bout_10_19_at_school", "n_bout_20_29_at_school", "n_bout_30_at_school", 
             "time_bout_0_1_at_school", "time_bout_1_4_at_school", "time_bout_5_9_at_school", 
             "time_bout_10_19_at_school", "time_bout_20_29_at_school", "time_bout_30_at_school", 
             
             "n_bout_0_1_in_class",  "n_bout_1_4_in_class",  "n_bout_5_9_in_class",  
             "n_bout_10_19_in_class", "n_bout_20_29_in_class", "n_bout_30_in_class", 
             "time_bout_0_1_in_class", "time_bout_1_4_in_class", "time_bout_5_9_in_class", 
             "time_bout_10_19_in_class", "time_bout_20_29_in_class", "time_bout_30_in_class", 
             
             "n_bout_0_1_out_class",  "n_bout_1_4_out_class",  "n_bout_5_9_out_class",  
             "n_bout_10_19_out_class", "n_bout_20_29_out_class", "n_bout_30_out_class", 
             "time_bout_0_1_out_class", "time_bout_1_4_out_class", "time_bout_5_9_out_class", 
             "time_bout_10_19_out_class", "time_bout_20_29_out_class", "time_bout_30_out_class", 
             
             "n_bout_0_1_elsewhere", "n_bout_1_4_elsewhere", "n_bout_5_9_elsewhere", 
             "n_bout_10_19_elsewhere", "n_bout_20_29_elsewhere", "n_bout_30_elsewhere", 
             "time_bout_0_1_elsewhere", "time_bout_1_4_elsewhere", "time_bout_5_9_elsewhere", 
             "time_bout_10_19_elsewhere", "time_bout_20_29_elsewhere", "time_bout_30_elsewhere",
             "time_bout_30_exclusive_school", "time_bout_30_exclusive_in_class", "time_bout_30_exclusive_out_class", "time_bout_30_exclusive_elsewhere")
AT_bout[, (vars_max) := lapply(.SD, max_inf), .SDcols = vars_max, by = c('pid', 'time', 'obs_day')]

##############################
# aggregate to day level
# summary variables per day
# total

AT_sec[, ':=' (during_in_class = 0, during_out_class = 0)]
AT_sec[during_class_1 == 1 | during_class_2 == 1 | during_class_3 == 1 | during_class_4 == 1 | 
         during_class_5 == 1 | during_class_6 == 1 | during_class_7 == 1, during_in_class := 1]

AT_sec[during_in_class == 0 &
         during_observation == 1 & during_school_hours == 1, during_out_class := 1]

# sum_miss_total = AT_sec[during_observation == 1 & is.na(nonwear_unique),
#                         .(missing_time_total = .N/12), 
#                         by = c('pid', 'time', 'obs_day')]
# 
# sum_miss_at_school = AT_sec[during_observation == 1 & during_school_hours == 1 & is.na(nonwear_unique)  & absent == 0,
#                             .(missing_time_at_school = .N/12), 
#                             by = c('pid', 'time', 'obs_day')]
# 
# sum_miss_in_class = AT_sec[during_observation == 1 & during_school_hours == 1 & is.na(nonwear_unique)  & absent == 0
#                            & during_in_class == 1,
#                             .(missing_time_at_school = .N/12), 
#                             by = c('pid', 'time', 'obs_day')]
# 
# sum_miss_out_class = AT_sec[during_observation == 1 & during_school_hours == 1 & is.na(nonwear_unique)  & absent == 0 
#                             & during_out_class == 1,
#                             .(missing_time_at_school = .N/12), 
#                             by = c('pid', 'time', 'obs_day')]
# 
# sum_miss_elsewhere = AT_sec[during_observation == 1 & 
#                               ((during_school_hours == 0 & is.na(nonwear_unique)) | 
#                                  (during_school_hours == 1 & absent == 1 & is.na(nonwear_unique))),
#                             .(missing_time_elsewhere = .N/12), 
#                             by = c('pid', 'time', 'obs_day')]

sum_total = AT_sec[during_observation == 1 & nonwear_unique == 0, 
                   .(time_observed_total = .N/12,
                     ENMOmg_total = mean(ENMO, na.rm=TRUE)*1000,
                     Sitting_Lying_total = sum(activity_type %in% 
                                                 c('Sitting', 'Lying'), na.rm=TRUE)/12, 
                     # Sitting_Lying_30sec_break_total = sum(sitting, na.rm=TRUE)/12,  
                     Sitting_total  = sum(activity_type == 'Sitting', na.rm=TRUE)/12, 
                     Lying_total    = sum(activity_type == 'Lying', na.rm=TRUE)/12, 
                     Standing_total = sum(activity_type == 'Standing', na.rm=TRUE)/12, 
                     Walking_total  = sum(activity_type == 'Walking', na.rm=TRUE)/12, 
                     Running_total  = sum(activity_type == 'Running', na.rm=TRUE)/12, 
                     Cycling_total  = sum(activity_type == 'Cycling', na.rm=TRUE)/12, 
                     Sleeping_total = sum(activity_type == 'Sleeping', na.rm=TRUE)/12), 
                   by = c('pid', 'time', 'obs_day')]

# at school

sum_at_school = AT_sec[at_school_activity == 1, 
                       .(time_observed_at_school = .N/12,
                         ENMOmg_at_school = mean(ENMO, na.rm = TRUE)*1000,
                         Sitting_Lying_at_school = sum(activity_type %in% 
                                                         c('Sitting', 'Lying'), na.rm=TRUE)/12, 
                         # Sitting_Lying_30sec_break_at_school = sum(sitting, na.rm=TRUE)/12, 
                         Sitting_at_school = sum(activity_type == 'Sitting', na.rm=TRUE)/12, 
                         Lying_at_school = sum(activity_type == 'Lying', na.rm=TRUE)/12, 
                         Standing_at_school = sum(activity_type == 'Standing', na.rm=TRUE)/12, 
                         Walking_at_school = sum(activity_type == 'Walking', na.rm=TRUE)/12, 
                         Running_at_school = sum(activity_type == 'Running', na.rm=TRUE)/12, 
                         Cycling_at_school = sum(activity_type == 'Cycling', na.rm=TRUE)/12), 
                       by = c('pid', 'time', 'obs_day')]

# in class

sum_in_class = AT_sec[in_class_activity == 1, 
                       .(time_observed_in_class = .N/12,
                         ENMOmg_in_class = mean(ENMO, na.rm = TRUE)*1000,
                         Sitting_Lying_in_class = sum(activity_type %in% 
                                                         c('Sitting', 'Lying'), na.rm=TRUE)/12, 
                         # Sitting_Lying_30sec_break_in_class = sum(sitting, na.rm=TRUE)/12, 
                         Sitting_in_class = sum(activity_type == 'Sitting', na.rm=TRUE)/12, 
                         Lying_in_class = sum(activity_type == 'Lying', na.rm=TRUE)/12, 
                         Standing_in_class = sum(activity_type == 'Standing', na.rm=TRUE)/12, 
                         Walking_in_class = sum(activity_type == 'Walking', na.rm=TRUE)/12, 
                         Running_in_class = sum(activity_type == 'Running', na.rm=TRUE)/12, 
                         Cycling_in_class = sum(activity_type == 'Cycling', na.rm=TRUE)/12), 
                       by = c('pid', 'time', 'obs_day')]

# out class

sum_out_class = AT_sec[out_class_activity == 1, 
                      .(time_observed_out_class = .N/12,
                        ENMOmg_out_class = mean(ENMO, na.rm = TRUE)*1000,
                        Sitting_Lying_out_class = sum(activity_type %in% 
                                                       c('Sitting', 'Lying'), na.rm=TRUE)/12, 
                        # Sitting_Lying_30sec_break_out_class = sum(sitting, na.rm=TRUE)/12, 
                        Sitting_out_class = sum(activity_type == 'Sitting', na.rm=TRUE)/12, 
                        Lying_out_class = sum(activity_type == 'Lying', na.rm=TRUE)/12, 
                        Standing_out_class = sum(activity_type == 'Standing', na.rm=TRUE)/12, 
                        Walking_out_class = sum(activity_type == 'Walking', na.rm=TRUE)/12, 
                        Running_out_class = sum(activity_type == 'Running', na.rm=TRUE)/12, 
                        Cycling_out_class = sum(activity_type == 'Cycling', na.rm=TRUE)/12), 
                      by = c('pid', 'time', 'obs_day')]

# elsewhere

sum_elsewhere = AT_sec[out_school_activity == 1, 
                       .(time_observed_elsewhere = .N/12,
                         ENMOmg_elsewhere = mean(ENMO, na.rm = TRUE)*1000,
                         Sitting_Lying_elsewhere = sum(activity_type %in% 
                                                         c('Sitting', 'Lying'), na.rm=TRUE)/12, 
                         # Sitting_Lying_30sec_break_elsewhere = sum(sitting, na.rm=TRUE)/12, 
                         Sitting_elsewhere = sum(activity_type == 'Sitting', na.rm=TRUE)/12, 
                         Lying_elsewhere = sum(activity_type == 'Lying', na.rm=TRUE)/12, 
                         Standing_elsewhere = sum(activity_type == 'Standing', na.rm=TRUE)/12, 
                         Walking_elsewhere = sum(activity_type == 'Walking', na.rm=TRUE)/12, 
                         Running_elsewhere = sum(activity_type == 'Running', na.rm=TRUE)/12, 
                         Cycling_elsewhere = sum(activity_type == 'Cycling', na.rm=TRUE)/12, 
                         Sleeping_elsewhere = sum(activity_type == 'Sleeping', na.rm=TRUE)/12), 
                       by = c('pid', 'time', 'obs_day')]

# bouts

sum_bout = unique(AT_bout[, c('pid', 'time', 'obs_day', vars_max), with = FALSE], 
                  by = c('pid', 'time', 'obs_day'))


# sleep, absence, nonwear and out_of_boundary per day

sum_time_total = AT_sec[during_observation == 1, 
                        lapply(.SD, function(x){sum(x, na.rm = TRUE)/12}), 
                        .SDcols = c('nonwear_detected', 'nonwear_reported', 
                                    'nonwear_unique'), by = c('pid', 'time', 'obs_day')]

sum_time_at_school = AT_sec[during_observation == 1 & during_school_hours == 1 & absent == 0, 
                            lapply(.SD, function(x){sum(x, na.rm = TRUE)/12}), 
                            .SDcols = c('nonwear_detected', 'nonwear_reported', 
                                        'nonwear_unique'), by = c('pid', 'time', 'obs_day')]

sum_absent_at_school = AT_sec[during_observation == 1 & during_school_hours == 1 & absent == 1, 
                              .(absent_at_school = .N/12), by = c('pid', 'time', 'obs_day')]

sum_time_in_class = AT_sec[during_observation == 1 & during_school_hours == 1 & absent == 0 & during_in_class == 1, 
                           lapply(.SD, function(x){sum(x, na.rm = TRUE)/12}), 
                           .SDcols = c('nonwear_detected', 'nonwear_reported', 
                                       'nonwear_unique'), by = c('pid', 'time', 'obs_day')]

sum_absent_in_class = AT_sec[during_observation == 1 & during_school_hours == 1 & absent == 1 & during_in_class == 1, 
                             .(absent_at_school = .N/12), by = c('pid', 'time', 'obs_day')]


sum_time_out_class = AT_sec[during_observation == 1 & during_school_hours == 1 & absent == 0 & during_out_class == 1, 
                            lapply(.SD, function(x){sum(x, na.rm = TRUE)/12}), 
                            .SDcols = c('nonwear_detected', 'nonwear_reported', 
                                        'nonwear_unique'), by = c('pid', 'time', 'obs_day')]

sum_absent_out_class = AT_sec[during_observation == 1 & during_school_hours == 1 & absent == 1 & during_out_class == 1, 
                              .(absent_at_school = .N/12), by = c('pid', 'time', 'obs_day')]

sum_time_elsewhere = AT_sec[during_observation == 1 & 
                              (during_school_hours == 0 | (during_school_hours == 1 & absent == 1)), 
                            lapply(.SD, function(x){sum(x, na.rm = TRUE)/12}), 
                            .SDcols = c('nonwear_detected', 'nonwear_reported', 
                                        'nonwear_unique'), by = c('pid', 'time', 'obs_day')]

setnames(sum_time_total, names(sum_time_total)[4:ncol(sum_time_total)], 
         paste0(names(sum_time_total)[4:ncol(sum_time_total)], '_total'))
setnames(sum_time_at_school, names(sum_time_at_school)[4:ncol(sum_time_at_school)], 
         paste0(names(sum_time_at_school)[4:ncol(sum_time_at_school)], '_at_school'))
setnames(sum_time_in_class, names(sum_time_in_class)[4:ncol(sum_time_in_class)], 
         paste0(names(sum_time_in_class)[4:ncol(sum_time_in_class)], '_in_class'))
setnames(sum_time_out_class, names(sum_time_out_class)[4:ncol(sum_time_out_class)], 
         paste0(names(sum_time_out_class)[4:ncol(sum_time_out_class)], '_out_class'))
setnames(sum_time_elsewhere, names(sum_time_elsewhere)[4:ncol(sum_time_elsewhere)], 
         paste0(names(sum_time_elsewhere)[4:ncol(sum_time_elsewhere)], '_elsewhere'))

sum_time2_total     = AT_sec[, 
                             .(observation_time_total = sum(during_observation)/12), by = c('pid', 'time', 'obs_day')]
sum_time2_at_school = AT_sec[during_observation == 1, 
                             .(observation_time_at_school = sum(during_school_hours == 1)/12), by = c('pid', 'time', 'obs_day')]
sum_time2_in_class = AT_sec[during_observation == 1 & during_school_hours == 1, 
                            .(observation_time_in_class = sum(during_in_class == 1)/12), by = c('pid', 'time', 'obs_day')]
sum_time2_out_class = AT_sec[during_observation == 1 & during_school_hours == 1, 
                             .(observation_time_out_class = sum(during_out_class == 1)/12), by = c('pid', 'time', 'obs_day')]
sum_time2_elsewhere = AT_sec[during_observation == 1, 
                             .(observation_time_elsewhere = sum(during_school_hours == 0)/12), by = c('pid', 'time', 'obs_day')]

# some extra variable in sec data, for SPSS cannot code the timestamps correctly

AT_sec[, weekday := weekdays(start_obs_day)]
AT_sec[, timestamp_UTC := as.character(with_tz(timestamp, tzone = 'UTC'))]
AT_sec[, timestamp_CET := as.character(with_tz(timestamp, tzone = tz_local))]
AT_sec[, start_obs_day_CET := as.character(with_tz(start_obs_day, tzone = tz_local))]
AT_sec[, end_obs_day_CET := as.character(with_tz(end_obs_day, tzone = tz_local))]

# clean up

AT_sec[, ':=' (bout_nummer_no_sitting = NULL, bout_time_no_sitting = NULL)]

# time variables for day level data

id_time_var = unique(AT_sec[, .(pid, time, date = date(start_obs_day), obs_day, 
                                start_obs_day_CET, end_obs_day_CET)])
id_time_var[, weekday := weekdays(date)]

sum_act_per_day = merge(id_time_var, sum_time2_total, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_time_total, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_total, by = c('pid', 'time', 'obs_day'), all = TRUE)

sum_act_per_day = merge(sum_act_per_day, sum_time2_at_school, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_time_at_school, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_at_school, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_absent_at_school, by = c('pid', 'time', 'obs_day'), all = TRUE)

sum_act_per_day = merge(sum_act_per_day, sum_time2_in_class, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_time_in_class, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_in_class, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_absent_in_class, by = c('pid', 'time', 'obs_day'), all = TRUE)

sum_act_per_day = merge(sum_act_per_day, sum_time2_out_class, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_time_out_class, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_out_class, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_absent_out_class, by = c('pid', 'time', 'obs_day'), all = TRUE)

sum_act_per_day = merge(sum_act_per_day, sum_time2_elsewhere, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_time_elsewhere, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_elsewhere, by = c('pid', 'time', 'obs_day'), all = TRUE)
sum_act_per_day = merge(sum_act_per_day, sum_bout, by = c('pid', 'time', 'obs_day'), all = TRUE)

# if missing_time is missing, there is no missing_time

var_NA0 = names(sum_act_per_day)[7:ncol(sum_act_per_day)]
sum_act_per_day[, (var_NA0) := lapply(.SD, function(x){x <- replace(x, which(is.na(x)), 0)}), 
                .SDcols = var_NA0]

#########################################
# write data sets to .rds, .sav and .csv

# day-level data

readr::write_rds(sum_act_per_day, paste0(folder_agg, 'activity_per_schoolday.Rds'), compress = 'gz')
haven::write_sav(sum_act_per_day, paste0(folder_agg, 'activity_per_schoolday.sav'), compress = FALSE)

# 5 second level data

readr::write_rds(AT_sec, paste0(folder_sec_all, 'PA_per_5sec.Rds'), compress = 'gz')
haven::write_sav(AT_sec, paste0(folder_sec_all, 'PA_per_5sec.sav'), compress = FALSE)
readr::write_csv(AT_sec, paste0(folder_sec_all, 'PA_per_5sec.csv'))

# op bout niveau

AT_bout_agg = AT_bout[, .(pid, timestamp, obs_day, Schoolnummer, 
                          during_school_hours, absent,  nonwear_reported, nonwear_detected,
                          at_school_activity, out_school_activity, 
                          bout_nummer_sitting, bout_time_sitting, 
                          bout_time_sitting_exclusive_school, bout_time_sitting_exclusive_in_class, bout_time_sitting_exclusive_out_class, bout_time_sitting_exclusive_outside)]

readr::write_rds(AT_bout, paste0(folder_agg_bout, 'PA_per_bout.Rds'), compress = 'gz')
haven::write_sav(AT_bout, paste0(folder_agg_bout, 'PA_per_minute.sav'), compress = FALSE)
