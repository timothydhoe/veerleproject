
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


#' Generates activity features
#' 
#' @description 
#'
#' @param data_files
#' @param do_parallel
#' @param verbose 
#'
#' @return
#' @examples
#' 
#' @export
generate_activity_features <- function (data_files, do_parallel = TRUE, verbose = TRUE) {
  
  if(do_parallel) {
    closeAllConnections() 
    cl <- parallel::makeCluster(parallel::detectCores() - 1)
    doParallel::registerDoParallel(cl)
    `%doloop%` <- foreach::`%dopar%`
  } else {
    `%doloop%` <- foreach::`%do%`
  }

  # Assign filters 
  f_noise <- signal::butter(4, 0.5,type = "low")
  f_g <- signal::butter(4, 0.02, type= "low")
  f_peak <- signal::butter(4, 0.06, type = "low")
  
  
  tictoc::tic('Calculating activity features')
  
    result <- foreach::foreach(i = data_files,
                               .packages = c('dplyr', 'readr','signal'),
                               .export = c('fft_f', 'find_peaks'),
                               .combine = rbind,
                               .verbose = TRUE) %doloop% {

    read_rds(i)%>% 
        dplyr::mutate(group =  cut(time, "5 sec", labels = F),
                      b_vm = sqrt(b_x^2 + b_y^2 + b_z^2),
                      t_vm = sqrt(t_x^2 + t_y^2 + t_z^2),	
                    
                      # Filter data before calculating features
                      b_x = signal::filtfilt(f_noise, b_x),	
                      b_y = signal::filtfilt(f_noise, b_y),	
                      b_z = signal::filtfilt(f_noise, b_z),	
                      b_vm_filt = signal::filtfilt(f_noise, b_vm),	
                      b_x_g = signal::filtfilt(f_g, b_x),	
                      b_y_g = signal::filtfilt(f_g, b_y),	
                      b_z_g = signal::filtfilt(f_g, b_z),	
                      b_vm_g = signal::filtfilt(f_g, b_vm),	
                      b_x_peak = signal::filtfilt(f_peak, b_x),	
                      b_y_peak = signal::filtfilt(f_peak, b_y),	
                      b_z_peak = signal::filtfilt(f_peak, b_z),	
                      b_vm_peak =signal:: filtfilt(f_peak, b_vm),	
                      
                      t_x = signal::filtfilt(f_noise, t_x),	
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
                      t_vm_peak = signal::filtfilt(f_peak, t_vm)) %>% 
                
                      # Features for each 5s window
                      dplyr::group_by(group) %>% 
                      summarise(
                        
                        timestamp =  dplyr::first(time),
                        b_count = sum(b_vm >= 1.2 | b_vm <= 0.8),
                        t_count = sum(t_vm >= 1.2 | t_vm <= 0.8),
                        
                        b_mean_x = mean(b_x_g),
                        b_mean_y = mean(b_y_g),
                        b_mean_z = mean(b_z_g),
                        t_mean_x = mean(t_x_g),
                        t_mean_y = mean(t_y_g),
                        t_mean_z = mean(t_z_g),
                        b_mag_mean = mean(b_vm_g),
                        t_mag_mean = mean(t_vm_g),
                        
                        b_sd_x = sd(b_x),
                        b_sd_y = sd(b_y),
                        b_sd_z = sd(b_z),
                        t_sd_x = sd(t_x),
                        t_sd_y = sd(t_y),
                        t_sd_z = sd(t_z),
                        b_mag_sd = sd(b_vm_filt),
                        t_mag_sd = sd(t_vm_filt),
                        
                        b_coef_x = ifelse(b_mean_x > 0, b_sd_x / b_mean_x, 0),
                        b_coef_y = ifelse(b_mean_y > 0, b_sd_y / b_mean_y, 0),
                        b_coef_z = ifelse(b_mean_z > 0, b_sd_z / b_mean_z, 0),
                        b_mag_coef = ifelse(b_mag_mean > 0, b_mag_sd/ b_mag_mean, 0),
                        t_coef_x = ifelse(t_mean_x > 0, t_sd_x / t_mean_x, 0),
                        t_coef_y = ifelse(t_mean_y > 0, t_sd_y / t_mean_y, 0),
                        t_coef_z = ifelse(t_mean_z > 0, t_sd_z / t_mean_z, 0),
                        t_mag_coef = ifelse(t_mag_mean > 0, t_mag_sd/ t_mag_mean, 0),
                        
                        b_quan_25_x = quantile(b_x_g, 0.25),
                        b_quan_25_y = quantile(b_y_g, 0.25),
                        b_quan_25_z = quantile(b_z_g, 0.25),
                        t_quan_25_x = quantile(t_x_g, 0.25),
                        t_quan_25_y = quantile(t_y_g, 0.25),
                        t_quan_25_z = quantile(t_z_g, 0.25),
                        b_mag_quan_25 = quantile(b_vm_g, 0.25),
                        t_mag_quan_25 = quantile(t_vm_g, 0.25),
                        
                        b_quan_50_x = quantile(b_x_g, 0.50),
                        b_quan_50_y = quantile(b_y_g, 0.50),
                        b_quan_50_z = quantile(b_z_g, 0.50),
                        t_quan_50_x = quantile(t_x_g, 0.50),
                        t_quan_50_y = quantile(t_y_g, 0.50),
                        t_quan_50_z = quantile(t_z_g, 0.50),
                        b_mag_quan_50 = quantile(b_vm_g, 0.50),
                        t_mag_quan_50 = quantile(t_vm_g, 0.50),
                        
                        b_quan_75_x = quantile(b_x_g, 0.75),
                        b_quan_75_y = quantile(b_y_g, 0.75),
                        b_quan_75_z = quantile(b_z_g, 0.75),
                        t_quan_75_x = quantile(t_x_g, 0.75),
                        t_quan_75_y = quantile(t_y_g, 0.75),
                        t_quan_75_z = quantile(t_z_g, 0.75),
                        b_mag_quan_75 = quantile(b_vm_g, 0.75),
                        t_mag_quan_75 = quantile(t_vm_g, 0.75),
                        
                        b_min_x = min(b_x_g),
                        b_min_y = min(b_y_g),
                        b_min_z = min(b_z_g),
                        t_min_x = min(t_x_g),
                        t_min_y = min(t_y_g),
                        t_min_z = min(t_z_g),
                        b_mag_min = min(b_vm_g),
                        t_mag_min = min(t_vm_g),
                        
                        b_max_x = max(b_x_g),
                        b_max_y = max(b_y_g),
                        b_max_z = max(b_z_g),
                        t_max_x = max(t_x_g),
                        t_max_y = max(t_y_g),
                        t_max_z = max(t_z_g),
                        b_mag_max = max(b_vm_g),
                        t_mag_max = max(t_vm_g),
                        
                        corr_xTyT = ifelse(t_sd_x>0 & t_sd_y>0, cor(t_x, t_y),0),
                        corr_xTzT = ifelse(t_sd_x>0 & t_sd_z>0, cor(t_x, t_z),0),
                        corr_yTzT = ifelse(t_sd_y>0 & t_sd_z>0, cor(t_y, t_z),0),
                        corr_xByB = ifelse(b_sd_x>0 & b_sd_y>0, cor(b_x, b_y),0),
                        corr_xBzB = ifelse(b_sd_x>0 & b_sd_z>0, cor(b_x, b_z),0),
                        corr_yBzB = ifelse(b_sd_y>0 & b_sd_z>0, cor(b_z, b_y),0),
                        corr_xTxB = ifelse(t_sd_x>0 & b_sd_x>0, cor(t_x, b_x),0),
                        corr_xTyB = ifelse(t_sd_x>0 & b_sd_y>0, cor(t_x, b_y),0),
                        corr_xTzB = ifelse(t_sd_x>0 & b_sd_z>0, cor(t_x, b_z),0),
                        corr_yTxB = ifelse(t_sd_y>0 & b_sd_x>0, cor(t_y, b_x),0),
                        corr_yTyB = ifelse(t_sd_y>0 & b_sd_y>0, cor(t_y, b_y),0),
                        corr_yTzB = ifelse(t_sd_y>0 & b_sd_z>0, cor(t_y, b_z),0),
                        corr_zTxB = ifelse(t_sd_z>0 & b_sd_x>0, cor(t_z, b_x),0),
                        corr_zTyB = ifelse(t_sd_z>0 & b_sd_y>0, cor(t_z, b_y),0),
                        corr_zTzB = ifelse(t_sd_z>0 & b_sd_z>0, cor(t_z, b_z),0),
                        corr_mTmB = ifelse(t_mag_sd>0 & b_mag_sd>0,cor(b_vm, t_vm),0),
                        
                        mean_xBxT = sum(t_mean_x, b_mean_x),
                        mean_yByT = sum(t_mean_y, b_mean_y),
                        mean_zBzT = sum(t_mean_z, b_mean_z),
                        mean_xByT = sum(t_mean_y, b_mean_x),
                        mean_xBzT = sum(t_mean_z, b_mean_x),
                        mean_yBzT = sum(t_mean_z, b_mean_y),
                        mean_yBxT = sum(t_mean_x, b_mean_y),
                        mean_zBxT = sum(t_mean_x, b_mean_z),
                        mean_zByT = sum(t_mean_y, b_mean_z),
                        
                        t_roll_mean = mean(atan2(t_y_g, t_x_g)),
                        b_roll_mean = mean(atan2(b_y_g, b_x_g)),
                        t_pitch_mean = mean(atan2(t_x_g, t_z_g)),
                        b_pitch_mean = mean(atan2(b_x_g, b_z_g)),
                        t_yaw_mean = mean(atan2(t_y_g, t_z_g)),
                        b_yaw_mean = mean(atan2(b_y_g, b_z_g)),
                        
                        t_roll_sd = sd(atan2(t_y_g, t_x_g)),
                        b_roll_sd = sd(atan2(b_y_g, b_x_g)),
                        t_pitch_sd = sd(atan2(t_x_g, t_z_g)),
                        b_pitch_sd = sd(atan2(b_x_g, b_z_g)),
                        t_yaw_sd = sd(atan2(t_y_g, t_z_g)),
                        b_yaw_sd = sd(atan2(b_y_g, b_z_g)),
                        
                        t_mean_g_x = mean(t_x_g),
                        t_mean_g_y = mean(t_y_g),
                        t_mean_g_z = mean(t_z_g),
                        b_mean_g_x = mean(b_x_g),
                        b_mean_g_y = mean(b_y_g),
                        b_mean_g_z = mean(b_z_g),
                        t_mag_g_mean = mean(t_vm_g),
                        b_mag_g_mean = mean(b_vm_g),
                        
                        t_fft_freq_x = fft_f(t_x_peak)$dominant,
                        t_fft_freq_y = fft_f(t_y_peak)$dominant,
                        t_fft_freq_z = fft_f(t_z_peak)$dominant,
                        t_fft_pow_x = fft_f(t_x_peak)$power,
                        t_fft_pow_y = fft_f(t_y_peak)$power,
                        t_fft_pow_z = fft_f(t_z_peak)$power,
                        t_fft_mag_freq = fft_f(t_vm_peak)$dominant,
                        t_fft_mag_pow = fft_f(t_vm_peak)$power,
                        
                        b_fft_freq_x = fft_f(b_x_peak)$dominant,
                        b_fft_freq_y = fft_f(b_y_peak)$dominant,
                        b_fft_freq_z = fft_f(b_z_peak)$dominant,
                        b_fft_pow_x = fft_f(b_x_peak)$power,
                        b_fft_pow_y = fft_f(b_y_peak)$power,
                        b_fft_pow_z = fft_f(b_z_peak)$power,
                        b_fft_mag_freq = fft_f(b_vm_peak)$dominant,
                        b_fft_mag_pow = fft_f(b_vm_peak)$power,
                        
                        t_peaks = min (find_peaks(t_x_peak, 20, 0.02), find_peaks(t_y_peak, 20, 0.02), find_peaks(t_z_peak, 20, 0.02)),
                        b_peaks = min (find_peaks(b_x_peak, 20, 0.02), find_peaks(b_y_peak, 20, 0.02), find_peaks(b_z_peak, 20, 0.02)),
                        
                        t_kurtosis_x = e1071::kurtosis(t_x_g),
                        t_kurtosis_y = e1071::kurtosis(t_y_g),
                        t_kurtosis_z = e1071::kurtosis(t_z_g),
                        b_kurtosis_x = e1071::kurtosis(b_x_g),
                        b_kurtosis_y = e1071::kurtosis(b_y_g),
                        b_kurtosis_z = e1071::kurtosis(b_z_g),
                        
                        t_skew_x = e1071::skewness(t_x_g),
                        t_skew_y = e1071::skewness(t_y_g),
                        t_skew_z = e1071::skewness(t_z_g),
                        b_skew_x = e1071::skewness(b_x_g),
                        b_skew_y = e1071::skewness(b_y_g),
                        b_skew_z = e1071::skewness(b_z_g))
  }
  
  tictoc::toc(quiet = !verbose)
  
  on.exit(parallel::stopCluster(cl))
  
  na.omit(arrange(result, timestamp))
}
