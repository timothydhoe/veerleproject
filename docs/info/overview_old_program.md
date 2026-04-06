Lines 1–16 — Imports & helper scripts
Lines 17–32 — Path configuration
Lines 34–67 — Commented-out preprocessing steps
Line 139 — Load pre-processed data (AT_sec : 5 sec epoch data)
Lines 147–199 — Load school schedule metadata
=> Dataset_Scholen.sav (SPSS file)
=> Bouwt observation_period (of researchers aanwezig waren) en school_hours (start/eind
schooluren, tot 7 individuele lesuren)
Lines 203–283 — Tag each 5s row with context flags
=> Voegt contextvlaggen (boolean) toe aan de kolommen (during_observation,
during_school_hours, during_class_1, ...)
Lines 291–304 — Mark absences
=> Dataset_Afwezigheden.sav (SPSS file)
=> absent = 1 bij afwezigheid
Lines 309–328 — Overlay sleep detection
=> sleep_axivity = 1 : overschrijft activity_type naar 'Sleeping'
Lines 333–347 — Student-reported non-wear
=> nonwear_reported = 1
Lines 352–390 — GGIR non-wear detection + merging
=> nonwear_unique = 1 : bij gedetecteerd of aangegeven nonwear, deze rijen krijgen
activity_type = NA (exclusie van analyse)
Lines 395–414 — Location flags
=> at_school_activity, in_class_activity, out_class_activity & out_school_activity
Lines 425–502 — Sedentary bout detection
=> Meest complex deel om na te gaan hoeveel tijd er lange periodes aaneensluitend (
sedentaire) activiteit is.
=> bout_nummer_no_sitting, bout_nummer_sitting
=> .N/12 bij 5s epochs. bouts worden in minuten berekend
Lines 512–715 — Bout-level summary table
=> rijen per bout aggregeren en classificeren in duration bins (<1 min, 1–4 min, 5–9
min, 10–19 min, 20–29 min, ≥30 min)
Lines 760–984 — Day-level aggregation
=> samenvatting per kind per dag per locatie
=> Totale observatietijd, gemiddelde ENMO, minuten zittend, liggend, staand, wandelend,
rennend, fietsend en slapend
=> sum_act_per_day: verzamelde individuele samenvattingen, missing values worden met 0
gevuld
Lines 988–1009 — Write outputs
=> Slaat drie datasets op :
- activity_per_schoolday (.Rds, .sav): één rij per kind per dag
- PA_per_5sec: een rij per 5 sec epoch (.Rds, .sav, .csv)
- PA_per_bout: één rij per zittende bout (.Rds, .sav)

Key takeaway for your project: This script is the analysis stage — it assumes the hard
work (calibration, feature extraction, RF prediction) was already done. For your
GENEActiv/GGIR pipeline, the equivalent is GGIR Parts 1–5, which you'd run first, and
this kind of school-context tagging and aggregation would come after.