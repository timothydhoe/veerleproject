# rf_model = model_AT
# folder_inn = folder_fea
# folder_out = folder_pre

predict_AT = function(parts, folder_inn, folder_out, rf_model){
  dat =  read_rds(paste0(folder_inn, part, '.Rds'))
  
  dat[, activity_type := predict(rf_model, dat)]
  
  write_rds(dat, paste0(folder_out, part, '.Rds'), compress = 'gz') 
  
  
}