# folder_inn = folder_pre


rbind_5s = function(parts, folder_inn, folder_bout){
  
  for(part in parts){
    dat =  read_rds(paste0(folder_inn, part, '.Rds'))
    
    # delete variables that are not needed
    dat = dat[, .(pid, timestamp, activity_type)]
    
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
    
    # merge all 5 second files
    flush.console()
    print(part)
    if(part == parts[1]){
      AT_5s = copy(dat)
    }else{
      AT_5s = rbindlist(list(AT_5s, dat))
    }
  }

  write_rds(AT_5s, paste0(folder_bout, 'Activity_type_bout_per_5s.Rds'))
}
