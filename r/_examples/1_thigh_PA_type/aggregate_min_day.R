# folder_inn = folder_pre


agg_5sec_min = function(parts, folder_inn, folder_min){
  
  for(part in parts){
    dat =  read_rds(paste0(folder_inn, part, '.Rds'))
    
    dat[, group_min := floor_date(timestamp, "1 min")]
    
    # Delete minutes with less than 12 obs (5 sec). Should be first and last minute, if any. 
    dat[, n_obs_min := .N, by = 'group_min']
    dat = dat[n_obs_min == 12]
    dat[, n_obs_min := NULL]
    
    # Observation day from 3 a.m. to 3 a.m. Also good cut for days with daylight saving.
    dat[, obs_day := 0]
    dat[1, obs_day := 1]
    dat[, timeMinLoc := with_tz(timestamp, tz = 'Europe/Brussels')]
    dat[hour(timeMinLoc) == 3, obs_day := 1]
    dat[shift(obs_day) == 1, obs_day := 0]
    dat[, obs_day := cumsum(obs_day)]
    dat[, timeMinLoc := NULL]
    
    # observation datetime
    dat[, start_obs_day := first(group_min), by = obs_day]
    dat[, end_obs_day := last(group_min)+59, by = obs_day]
    
    dat_min = dat[, .(pid = part, 
                      timestamp = first(group_min),
                      obs_day = first(obs_day),
                      start_obs_day = first(start_obs_day),
                      end_obs_day = first(end_obs_day),
                      activity_type_min = names(sort(table(activity_type), decreasing=TRUE)[1]),
                      Sitting_min = sum(activity_type == 'Sitting')/12,
                      Lying_min = sum(activity_type == 'Lying')/12,
                      Standing_min = sum(activity_type == 'Standing')/12,
                      Walking_min = sum(activity_type == 'Walking')/12,
                      Running_min = sum(activity_type == 'Running')/12,
                      Cycling_min = sum(activity_type == 'Cycling')/12,
                      temp_mean = mean(temp_mean),
                      batt_mean = mean(batt_mean),
                      light_mean = mean(light_mean)), by = group_min][, group_min := NULL]
    
    # dat_min[, activity_type_min := as.factor(activity_type_min)]
    # Hmisc::describe(dat_min)
    
    # randomly assing value in case of a tie
    # sitting ties 
    set.seed(04122019); dat_min[Sitting_min == Lying_min    & activity_type_min %in% c('Sitting', 'Lying'),    activity_type_min := sample(c('Sitting', 'Lying'),    replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Sitting_min == Standing_min & activity_type_min %in% c('Sitting', 'Standing'), activity_type_min := sample(c('Sitting', 'Standing'), replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Sitting_min == Walking_min  & activity_type_min %in% c('Sitting', 'Walking'),  activity_type_min := sample(c('Sitting', 'Walking'),  replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Sitting_min == Running_min  & activity_type_min %in% c('Sitting', 'Running'),  activity_type_min := sample(c('Sitting', 'Running'),  replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Sitting_min == Cycling_min  & activity_type_min %in% c('Sitting', 'Cycling'),  activity_type_min := sample(c('Sitting', 'Cycling'),  replace = TRUE, size = .N)]
    
    # lying ties 
    set.seed(04122019); dat_min[Lying_min == Standing_min & activity_type_min %in% c('Lying', 'Standing'), activity_type_min := sample(c('Lying', 'Standing'), replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Lying_min == Walking_min  & activity_type_min %in% c('Lying', 'Walking'),  activity_type_min := sample(c('Lying', 'Walking'),  replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Lying_min == Running_min  & activity_type_min %in% c('Lying', 'Running'),  activity_type_min := sample(c('Lying', 'Running'),  replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Lying_min == Cycling_min  & activity_type_min %in% c('Lying', 'Cycling'),  activity_type_min := sample(c('Lying', 'Cycling'),  replace = TRUE, size = .N)]
    
    # standing ties 
    set.seed(04122019); dat_min[Standing_min == Walking_min  & activity_type_min %in% c('Standing', 'Walking'), activity_type_min := sample(c('Standing', 'Walking'), replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Standing_min == Running_min  & activity_type_min %in% c('Standing', 'Running'), activity_type_min := sample(c('Standing', 'Running'), replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Standing_min == Cycling_min  & activity_type_min %in% c('Standing', 'Cycling'), activity_type_min := sample(c('Standing', 'Cycling'), replace = TRUE, size = .N)]
    
    # walking ties 
    set.seed(04122019); dat_min[Walking_min == Running_min  & activity_type_min %in% c('Walking', 'Running'), activity_type_min := sample(c('Walking', 'Running'), replace = TRUE, size = .N)]
    set.seed(04122019); dat_min[Walking_min == Cycling_min  & activity_type_min %in% c('Walking', 'Cycling'), activity_type_min := sample(c('Walking', 'Cycling'), replace = TRUE, size = .N)]
    
    # running ties
    set.seed(04122019); dat_min[Running_min == Cycling_min  & activity_type_min %in% c('Running', 'Cycling'), activity_type_min := sample(c('Running', 'Cycling'), replace = TRUE, size = .N)]
    
    # write_rds(dat_min, paste0(folder_min, part, '.Rds'))
    flush.console()
    print(part)
    if(part == parts[1]){
      AT_min = copy(dat_min)
    }else{
      AT_min = rbindlist(list(AT_min, dat_min))
    }
  }

  write_rds(AT_min, paste0(folder_min, 'Activity_type_per_min.Rds'))
}
