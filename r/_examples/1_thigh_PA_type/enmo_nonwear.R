# folder_enmo_sec = folder_ggi

enmo_nonwear_to_min = function(part, folder_enmo_sec, tz_local){
  
  # read data
  ggir_path = 'output_1_raw/meta/basic/'
  folder_inn = paste0(folder_enmo_sec, ggir_path)
  file_enmo = paste0(folder_inn, dir(folder_inn)[grep(part, dir(folder_inn))])
  load(file_enmo)
  
  # extract enmo at 1 sec epochs
  count_second = data.table(M[['metashort']])
  count_second[, timestamp := with_tz(ymd_hms(timestamp, tz = 'Europe/Brussels'), tz='Europe/Brussels')]
  
  #  
  count_second[, ':=' (timestamp_minute = floor_date(timestamp, unit = 'mins'))] 
  
  enmo_nonwear = count_second[, lapply(.SD, mean), .SDcols = c('ENMO'), by = timestamp_minute]
  
  # add nonwear
  nonwear = data.table(M[['metalong']])[, .(timestamp, nonwearscore)]
  nonwear[, timestamp := with_tz(lubridate::ymd_hms(timestamp), tz_local)]
  start = nonwear[1,timestamp]
  stopp = nonwear[.N,timestamp]+ minutes(15)
  
  nonwear[, ':=' (start_bout = timestamp, stop_bout = c(nonwear[2:.N,timestamp], stopp))]
  
  # nonwear_minute = data.table(timestamp_minute = seq(start, stopp-60, 'min'))
  
  for(i in 1:nonwear[,.N]){
    enmo_nonwear[timestamp_minute >= nonwear[i, start_bout] & timestamp_minute < nonwear[i, stop_bout], 
                 nonwearscore := nonwear[i, nonwearscore] ]
  }
  
  # order variables
  enmo_nonwear[, pid := part]
  enmo_nonwear[, .(pid, timestamp_minute, ENMO, nonwearscore)]
}
