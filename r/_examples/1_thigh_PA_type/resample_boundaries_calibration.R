# this function only calibrates anymore
# resampling is done in generate_activity_features.R

# part = '102'
# tz = 'Europe/Brussels'

resam_bound_callib = function(part, folder_raw, folder_axi, folder_cal, tz){
  
  # read in .cwa file
  file_cwa = paste0(folder_raw, part, '.cwa')
  
  if(file.exists(file_cwa)){
    info <- GGIRread::readAxivity(file_cwa, start = 0, end = 0, desiredtz = 'Europe/Brussels')
    dat <- GGIRread::readAxivity(file_cwa, start = 0, end = info$header$blocks, desiredtz = 'Europe/Brussels')
    
  }else{
    return(warning(paste(part, 'has no Axivity data')))
  } 
  
  # if calibration file does not exist, calibrate and save file
  if (file.exists(paste0(folder_cal, part, '.rds'))) {
    C <- read_rds(paste0(folder_cal, part, '.rds'))
  } else {
    cat('\nCalculating calibration string...\n')
    C <- GGIR::g.calibrate(datafile = file_cwa, start = 0, end = info$header$blocks, desiredtz = 'Europe/Brussels')
    write_rds(C, paste0(folder_cal, part, '.rds'))
  }
  
  
  # scale with calibration factor

  dat[["data"]][, 2:4] <- data.frame(scale(dat[["data"]][, 2:4], 
                                          center = -C$offset, 
                                          scale = 1/C$scale))
  
  # define file name and write to folder_axi
  file_out = paste0(folder_axi, part)
  
  write_rds(dat, paste0(file_out, '.Rds'), compress = 'gz')  
  print('finished')
  
}



