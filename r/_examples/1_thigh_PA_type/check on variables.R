
sum_act_per_day = readr::read_rds(paste0(folder_agg, 'activity_per_schoolday.Rds'))




sum_act_per_day[, .(ENMO_total, ENMO_at_school, ENMO_elsewhere)]

sum_act_per_day[, test := Sitting_Lying_30sec_break_elsewhere  - 
                  (time_bout_0_1_elsewhere + time_bout_1_4_elsewhere + time_bout_5_9_elsewhere + 
                     time_bout_10_19_elsewhere + time_bout_20_29_elsewhere + time_bout_30_elsewhere)]

sum_act_per_day[abs(round(test)) > 60, 
                .(pid, obs_day, test, time_observed_elsewhere,time_observed_at_school, #missing_time_elsewhere, 
                  #Sitting_Lying_elsewhere, #nonwear_unique_total, nonwear_unique_elsewhere, 
                  Sitting_Lying_30sec_break_elsewhere, 
                  bouts_at_school = (time_bout_0_1_at_school + time_bout_1_4_at_school + time_bout_5_9_at_school + 
                                       time_bout_10_19_at_school + time_bout_20_29_at_school + time_bout_30_at_school), 
                  bouts_elsewhere = (time_bout_0_1_elsewhere + time_bout_1_4_elsewhere + time_bout_5_9_elsewhere + 
                             time_bout_10_19_elsewhere + time_bout_20_29_elsewhere + time_bout_30_elsewhere),
                  absent_at_school)]

 


AT_bout[pid == '102' & obs_day == '4']
AT_bout[pid == '102' & obs_day == '5']
AT_bout[pid == '102' & obs_day == '5']

AT_sec[pid == '102' & obs_day == '4'& bout_nummer_sitting == 166]
AT_sec[pid == '102' & obs_day == '4'& bout_nummer_sitting == 166, plot(timestamp, as.numeric(activity_type))]
AT_sec[pid == '102' & obs_day == '4'& bout_nummer_sitting == 166, summary(as.factor(sitting))]
names(sum_act_per_day)
