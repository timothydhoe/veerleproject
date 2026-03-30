library(data.table)

AT_min = readr::read_rds(paste0(folder_min_all, 'PA_per_minute.Rds'))


average_day = copy(AT_min)


average_day[, group_time := ymd_hms(paste('2020-01-01 ', substr(timestamp_CET, 12, 19)), tz = 'Europe/Brussels')]


break_hist = seq(ymd_hms('2020-01-01 00:00:00', tz = 'Europe/Brussels'), ymd_hms('2020-01-01 23:59:00', tz = 'Europe/Brussels')+60, by = 3600)
average_day[, hist(group_time, breaks = break_hist)]
average_day[activity_type_min == 'Sleeping', hist(group_time, breaks = break_hist, freq = TRUE)]
average_day[activity_type_min == 'Cycling', hist(group_time, breaks = break_hist, freq = TRUE)]
average_day[activity_type_min == 'Lying', hist(group_time, breaks = break_hist, freq = TRUE)]
average_day[activity_type_min == 'Running', hist(group_time, breaks = break_hist, freq = TRUE)]
average_day[activity_type_min == 'Sitting', hist(group_time, breaks = break_hist, freq = TRUE)]
average_day[activity_type_min == 'Standing', hist(group_time, breaks = break_hist, freq = TRUE)]
average_day[activity_type_min == 'Walking', hist(group_time, breaks = break_hist, freq = TRUE)]


average_day[activity_type_min %in% c('Lying', 'Sitting'), hist(group_time, breaks = break_hist, freq = TRUE)]


test = average_day[weekday != 'woensdag', .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]

break_plot = seq(ymd_hms('2020-01-01 00:00:00', tz = 'Europe/Brussels'), ymd_hms('2020-01-01 23:59:00', tz = 'Europe/Brussels')+60, by = 3600)
plot(test[, group_time], test[, ENMO], axes = F, type = 'l')
axis(1, at = break_hist, c(0:23,0))
axis(2)

average_day[activity_type_min != 'Sleeping', hist(group_time, breaks = break_hist, freq = TRUE)]




test  = average_day[weekday != 'woensdag', .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]
test1 = average_day[weekday != 'woensdag' & Schoolnummer == 1, .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]
test2 = average_day[weekday != 'woensdag' & Schoolnummer == 2, .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]
test3 = average_day[weekday != 'woensdag' & Schoolnummer == 3, .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]
test4 = average_day[weekday != 'woensdag' & Schoolnummer == 4, .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]
test5 = average_day[weekday != 'woensdag' & Schoolnummer == 5, .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]
test6 = average_day[weekday != 'woensdag' & Schoolnummer == 6, .(ENMO = mean(ENMO, na.rm=TRUE)), by = group_time]


test [ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]
test1[ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]
test2[ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]
test3[ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]
test4[ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]
test5[ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]
test6[ , timeNumeric := as.numeric(difftime(group_time, ymd("2020-01-01", tz = 'Europe/Brussels'), units = 'hours'))]

test[,  smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]
test1[, smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]
test2[, smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]
test3[, smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]
test4[, smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]
test5[, smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]
test6[, smoothed := predict(loess(ENMO ~ timeNumeric, span=0.05))]


break_plot = seq(ymd_hms('2020-01-01 00:00:00'), ymd_hms('2020-01-01 23:59:00')+60, by = 3600)
plot(  test[, timeNumeric],  test[, smoothed], axes = F, lwd = 3, type = 'l', ylim = c(0, 0.15), xlab = "ENMO", ylab = 'Time')
lines(test1[, timeNumeric], test1[, smoothed], col = 2)
lines(test2[, timeNumeric], test2[, smoothed], col = 3)
lines(test3[, timeNumeric], test3[, smoothed], col = 4)
lines(test4[, timeNumeric], test4[, smoothed], col = 5)
lines(test5[, timeNumeric], test5[, smoothed], col = 6)
lines(test6[, timeNumeric], test6[, smoothed], col = 7)

axis(1, at = 0:24, c(0:23,0))
axis(2)

school1 = average_day[Schoolnummer == 1]; interaction.plot(school1$group_time, school1$pid, school1$ENMO, col = 1:length(unique(school1$pid)))

average_day[ , timeNumeric := as.numeric(group_time - ymd("2020-01-01", tz = 'Europe/Brussels'))]

average_day[Schoolnummer == 1, interaction.plot(timeNumeric, pid, ENMO, col = 1:uniqueN(pid))]
average_day[Schoolnummer == 2, interaction.plot(timeNumeric, pid, ENMO, col = 1:uniqueN(pid))]
average_day[Schoolnummer == 3, interaction.plot(timeNumeric, pid, ENMO, col = 1:uniqueN(pid))]
average_day[Schoolnummer == 4, interaction.plot(timeNumeric, pid, ENMO, col = 1:uniqueN(pid))]
average_day[Schoolnummer == 5, interaction.plot(timeNumeric, pid, ENMO, col = 1:uniqueN(pid))]
average_day[Schoolnummer == 6, interaction.plot(timeNumeric, pid, ENMO, col = 1:uniqueN(pid))]

average_day
