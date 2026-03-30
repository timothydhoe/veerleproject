fft_f <- function(v){
  s <- signal::specgram(v, n=length(v), Fs=100)
  S <- abs(s$S)
  f <- S / max(S)
  
  f1 <- f[s$f >= 0.1]
  freq1 <- s$f[s$f >= 0.1]
  d <- ifelse(length(freq1[which.max(f1)])==0, 0, freq1[which.max(f1)])
  p <- ifelse(length(f1)==0, 0, max(f1))
  
  list(dominant=d, power=p, entropy=sum(f * log(f)))
}


find_peaks <- function(v, mindistance, minheight){
  p <- pracma::findpeaks(v, minpeakdistance = mindistance, minpeakheight = minheight)
  ifelse(is.null(p), 0, nrow(p))
}


# ' generates activity features
# part = '101'
# folder_inn = folder_axi
# folder_out = folder_fea
generate_activity_features <- function (part, folder_inn, folder_out) {
  
  # assign filters 
  f_noise <- signal::butter(4, 0.5,type = "low")
  f_g <- signal::butter(4, 0.02, type= "low")
  f_peak <- signal::butter(4, 0.06, type = "low")
  
  dat_orig =  read_rds(paste0(folder_inn, part, '.Rds'))
  dat_long = data.table(dat_orig[['data']])

  setnames(dat_long, old = c('x', 'y', 'z'), new = c('t_x', 't_y', 't_z'))

  # resample to 100 hz (original sample rate might have some impact on the results, but resample is a patch for this problem)
  if(dat_orig$header$frequency != 100){
    
    # make new time variable, dropping (incomplete) first and last second
    start_time = ceiling(dat_long[1,time])
    end_time = floor(dat_long[.N,time])
    new_time = seq(start_time, end_time, 0.01)
    new_time = new_time[-length(new_time)]
    
    # linear resampling
    dat = data.table(time = new_time, 
                     t_x = approx(x = dat_long[, time], y = dat_long[, t_x], xout = new_time, method = "linear", rule = 2)$y,
                     t_y = approx(x = dat_long[, time], y = dat_long[, t_y], xout = new_time, method = "linear", rule = 2)$y,
                     t_z = approx(x = dat_long[, time], y = dat_long[, t_z], xout = new_time, method = "linear", rule = 2)$y,
                     temp = approx(x = dat_long[, time], y = dat_long[, temp], xout = new_time, method = "linear", rule = 2)$y,
                     battery = approx(x = dat_long[, time], y = dat_long[, battery], xout = new_time, method = "linear", rule = 2)$y,
                     light = approx(x = dat_long[, time], y = dat_long[, light], xout = new_time, method = "linear", rule = 2)$y)
  }else{
    dat = dat_long
  }
  
    
  dat[, ':=' (time = as.POSIXct(time, origin = "1970-01-01"),
              t_vm = sqrt(t_x^2 + t_y^2 + t_z^2))]
  dat[, ':=' (group =  cut(time, "5 sec", labels = F))]

  
  # filter data before calculating features
  dat[, ':=' (t_x = signal::filtfilt(f_noise, t_x),
              t_y = signal::filtfilt(f_noise, t_y),
              t_z = signal::filtfilt(f_noise, t_z),
              t_vm_filt = signal::filtfilt(f_noise, t_vm),
              t_x_g = signal::filtfilt(f_g, t_x),
              t_y_g = signal::filtfilt(f_g, t_y),
              t_z_g = signal::filtfilt(f_g, t_z),
              t_vm_g = signal::filtfilt(f_g, t_vm),
              t_x_peak = signal::filtfilt(f_peak, t_x),
              t_y_peak = signal::filtfilt(f_peak, t_y),
              t_z_peak = signal::filtfilt(f_peak, t_z),
              t_vm_peak = signal::filtfilt(f_peak, t_vm))]
  
  # features for each 5 seconds window
  # test = dat[1:100000]
  dat_fea = dat[, .(pid = part,

                    temp_mean = mean(temp),
                    batt_mean = mean(battery),
                    light_mean = mean(light),
                    
                     timestamp =  dplyr::first(time),
                     t_count = sum(t_vm >= 1.2 | t_vm <= 0.8),
                     
                     t_mean_x = mean(t_x_g),
                     t_mean_y = mean(t_y_g),
                     t_mean_z = mean(t_z_g),
                     t_mag_mean = mean(t_vm_g),
                     
                     t_sd_x = sd(t_x),
                     t_sd_y = sd(t_y),
                     t_sd_z = sd(t_z),
                     t_mag_sd = sd(t_vm_filt),
                     
                     t_quan_25_x = quantile(t_x_g, 0.25),
                     t_quan_25_y = quantile(t_y_g, 0.25),
                     t_quan_25_z = quantile(t_z_g, 0.25),
                     t_mag_quan_25 = quantile(t_vm_g, 0.25),
                     
                     t_quan_50_x = quantile(t_x_g, 0.50),
                     t_quan_50_y = quantile(t_y_g, 0.50),
                     t_quan_50_z = quantile(t_z_g, 0.50),
                     t_mag_quan_50 = quantile(t_vm_g, 0.50),
                     
                     t_quan_75_x = quantile(t_x_g, 0.75),
                     t_quan_75_y = quantile(t_y_g, 0.75),
                     t_quan_75_z = quantile(t_z_g, 0.75),
                     t_mag_quan_75 = quantile(t_vm_g, 0.75),
                     
                     t_min_x = min(t_x_g),
                     t_min_y = min(t_y_g),
                     t_min_z = min(t_z_g),
                     t_mag_min = min(t_vm_g),
                     
                     t_max_x = max(t_x_g),
                     t_max_y = max(t_y_g),
                     t_max_z = max(t_z_g),
                     t_mag_max = max(t_vm_g),
                     
                     t_roll_mean = mean(atan2(t_y_g, t_x_g)),
                     t_pitch_mean = mean(atan2(t_x_g, t_z_g)),
                     t_yaw_mean = mean(atan2(t_y_g, t_z_g)),
                     
                     t_roll_sd = sd(atan2(t_y_g, t_x_g)),
                     t_pitch_sd = sd(atan2(t_x_g, t_z_g)),
                     t_yaw_sd = sd(atan2(t_y_g, t_z_g)),
                     
                     t_mean_g_x = mean(t_x_g),
                     t_mean_g_y = mean(t_y_g),
                     t_mean_g_z = mean(t_z_g),
                     t_mag_g_mean = mean(t_vm_g),
                     
                     t_fft_freq_x = as.double(fft_f(t_x_peak)$dominant),
                     t_fft_freq_y = as.double(fft_f(t_y_peak)$dominant),
                     t_fft_freq_z = as.double(fft_f(t_z_peak)$dominant),
                     t_fft_pow_x = as.double(fft_f(t_x_peak)$power),
                     t_fft_pow_y = as.double(fft_f(t_y_peak)$power),
                     t_fft_pow_z = as.double(fft_f(t_z_peak)$power),
                     t_fft_mag_freq = as.double(fft_f(t_vm_peak)$dominant),
                     t_fft_mag_pow = as.double(fft_f(t_vm_peak)$power),
                     
                     t_peaks = as.double(min(find_peaks(t_x_peak, 20, 0.02), find_peaks(t_y_peak, 20, 0.02), find_peaks(t_z_peak, 20, 0.02))),
                     
                     t_kurtosis_x = e1071::kurtosis(t_x_g),
                     t_kurtosis_y = e1071::kurtosis(t_y_g),
                     t_kurtosis_z = e1071::kurtosis(t_z_g),
                     
                     t_skew_x = e1071::skewness(t_x_g),
                     t_skew_y = e1071::skewness(t_y_g),
                     t_skew_z = e1071::skewness(t_z_g),
                     
                     corr_xTyT = cor(t_x, t_y),
                     corr_xTzT = cor(t_x, t_z),
                     corr_yTzT = cor(t_y, t_z)), by = group]
  
  dat_fea[, ':=' (t_coef_x = ifelse(t_mean_x > 0, t_sd_x / t_mean_x, 0),
                  t_coef_y = ifelse(t_mean_y > 0, t_sd_y / t_mean_y, 0),
                  t_coef_z = ifelse(t_mean_z > 0, t_sd_z / t_mean_z, 0),
                  t_mag_coef = ifelse(t_mag_mean > 0, t_mag_sd/ t_mag_mean, 0),
                  
                  t_kurtosis_x = ifelse(!is.na(t_kurtosis_x), t_kurtosis_x, 0),
                  t_kurtosis_y = ifelse(!is.na(t_kurtosis_y), t_kurtosis_y, 0),
                  t_kurtosis_z = ifelse(!is.na(t_kurtosis_z), t_kurtosis_z, 0),
                  
                  t_skew_x = ifelse(!is.na(t_skew_x), t_skew_x, 0),
                  t_skew_y = ifelse(!is.na(t_skew_y), t_skew_y, 0),
                  t_skew_z = ifelse(!is.na(t_skew_z), t_skew_z, 0),
                  
                  corr_xTyT = ifelse(t_sd_x>0 & t_sd_y>0, corr_xTyT, 0),
                  corr_xTzT = ifelse(t_sd_x>0 & t_sd_z>0, corr_xTzT, 0),
                  corr_yTzT = ifelse(t_sd_y>0 & t_sd_z>0, corr_yTzT, 0),
                  
                  group = NULL)]
  
  
  write_rds(dat_fea, paste0(folder_out, part, '.rds'))
}





