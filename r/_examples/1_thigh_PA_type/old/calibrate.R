read_and_calibrate <- function(cwa, start = 0, end = 0, timezone = "UTC", progress_bar = TRUE) {
  
  # Read the header to get serial number and max blocks
  df <- GGIR::g.cwaread(cwa, 
                        start = 0,
                        end = 0, 
                        desiredtz = timezone)
  
  sid <- df$header$uniqueSerialCode
  nblocks <- df$header$blocks
  
  # Create 'calibration' folder in working directory
  if (!dir.exists('calibration')) 
    dir.create('calibration')
  
  # If calibration file does not exist, calibrate and save file
  if (file.exists(paste0('calibration/c', sid, '.rds'))) {
    C <- read_rds(paste0('calibration/c', sid, '.rds'))
  } else {
    cat('\nCalculating calibration string...\n')
    C <- GGIR::g.calibrate(datafile = cwa, desiredtz = timezone)
    write_rds(C, paste0('calibration/c', sid, '.rds'))
  }
  
  # Read in data and scale with calibration factor
  df <- GGIR::g.cwaread(cwa, 
                        start = start,
                        end = min(end, nblocks), 
                        progressBar = progress_bar, 
                        desiredtz = timezone)
  cat('\n')
  
  df[["data"]][, 2:4] <- data.frame(scale(df[["data"]][, 2:4], 
                                          center = -C$offset, 
                                          scale = 1/C$scale))
  df
}


# e.g.

cwa_back <- 'D:/A001_24641.cwa'

start_block <- 0 * 28800 # Day 1
end_block <- 7 * 28800 # Day 7

back <- read_and_calibrate(cwa = cwa_back, start = start_block, end = end_block, progress_bar = T)




