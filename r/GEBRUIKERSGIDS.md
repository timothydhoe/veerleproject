# SchoolMove — Gebruikersgids

Dit document beschrijft alles wat je nodig hebt om de pipeline te draaien, het dashboard te gebruiken en de resultaten te exporteren.

---

## 1. Eenmalige installatie

Open het project in RStudio door dubbel te klikken op `r/SchoolMove.Rproj`.

Voer daarna eenmalig uit in de R-console:

```r
source("install.R")
```

Dit installeert alle benodigde R-pakketten (via `renv`). Dit kan 5–10 minuten duren bij de eerste keer.

**Let op:** voor elke nieuwe medewerker die het project opent, volstaat:
```r
renv::restore()
```

Dit hoef je maar **één keer per machine** te doen. Daarna worden de pakketten automatisch geactiveerd via `.Rprofile` elke keer dat je het project opent — je hoeft `renv::restore()` niet opnieuw uit te voeren tenzij `renv.lock` is bijgewerkt (bijv. na een `git pull` waarbij nieuwe pakketten zijn toegevoegd).

---

## 2. Pipeline draaien

### 2a. Config instellen

Open `config.yaml` in de projectroot (één niveau boven `r/`). Dit is het enige bestand dat je aanpast; de R-scripts hoef je niet aan te raken.

Controleer minimaal:

| Instelling | Betekenis |
|-----------|-----------|
| `dev.example_mode` | `true` = gebruik fictieve testdata; `false` = gebruik échte data in `data/raw/` |
| `validity.min_wear_hours_per_day` | Minimum draaguren per dag (standaard: 16) |
| `validity.min_valid_days` | Minimum geldige dagen per deelnemer (standaard: 3) |
| `ggir.cut_points_mg` | ENMO-grenswaarden voor intensiteitsklassen (Hildebrand 2014/2017) |

### 2b. Pipeline uitvoeren

Zorg dat RStudio's werkdirectory ingesteld is op `r/` (dit is automatisch zo als je het `.Rproj`-bestand hebt geopend).

Voer de volledige pipeline uit:

```r
source("pipeline/run_all.R")
```

Dit doorloopt drie stappen:
1. **GGIR verwerking** — verwerkt de versnellingsmeterdata (duur: minuten tot uren afhankelijk van datagrootte)
2. **Schoolcontext labels** — koppelt schoolsegmenten (les, speeltijd, pauze) aan elke dag
3. **Samenvattingstabellen** — maakt `analysis_ready.csv` en `validity_summary.csv`

### 2c. QC-scripts

Na elke stap kun je de kwaliteit controleren:

```r
source("qc/qc_01_ggir.R")      # na stap 1
source("qc/qc_02_segments.R")  # na stap 2
source("qc/qc_03_summaries.R") # na stap 3
```

Elke QC-script toont `[PASS]`, `[WARN]`, en `[FAIL]` berichten in de console.

---

## 3. Dashboard starten

Start het Shiny-dashboard vanuit RStudio:

```r
shiny::runApp("shiny")
```

Het dashboard opent in je browser. Je kunt ook klikken op de **Run App**-knop die RStudio bovenaan de editor toont als je een Shiny-bestand open hebt.

---

## 4. Tabbladen uitleg

Het dashboard heeft een navigatiebalk bovenaan met globale filters (school en meting) die op alle tabbladen van toepassing zijn.

### Overzicht
Startscherm met vijf klikbare KPI-kaarten (klikken navigeert naar het bijbehorende tabblad):
- **Deelnemers** — totaal aantal verwerkte deelnemers
- **Geldig voor analyse** — % dat voldoet aan de draagcriteria
- **Gem. MVPA** — gemiddelde matig-tot-intensieve beweging per dag
- **WHO-richtlijn gehaald** — % deelnemers met ≥60 min MVPA/dag
- **Gem. slaap** — geschatte slaapduur per nacht (SPT)

Eronder: een grafiek met de MVPA-verandering per school (M1 → M2) en een schooloverzichttabel. Onderaan staat een automatisch gegenereerde **samenvatting voor rapport** die je kunt kopiëren.

Bovenaan staat ook een **Pipeline uitvoeren**-knop. Die opent een dialoogvenster met de terminalopdracht om de pipeline te starten — de pipeline draait niet automatisch vanuit het dashboard zelf (GGIR kan 30–60 minuten duren en blokkeert anders de hele app).

### Deelnemers
Individuele deelnemerverkenner. Selecteer een deelnemer via het dropdown-menu of door op een rij in de inclusietabel te klikken. Toont:
- MVPA per dag (tijdlijn)
- Activiteit per schoolsegment, M1 vs M2 (staafgrafiek)
- Draagduuroverzicht (heatmap per dag: groen = geldig, rood = onvoldoende)
- Inclusie/exclusie-tabel met filtermogelijkheid (alle / inbegrepen / uitgesloten)

### Schooldag
Analyse van activiteit per schooldagsegment (voor school, les, speeltijd, middagpauze, na school). Bevat:
- **Hoofdgrafiek** — schakelaar tussen "Één zone" (kies SB / LPA / MVPA) of "Alle zones" (volledig activiteitsbudget gestapeld)
- **MVPA tijdens pauze** per school
- **Weekdag activiteitsprofiel** — gemiddelde MVPA per dag met schakelaar schooldagen vs. weekend
- **Sedentaire bouten** — gemiddeld aantal aaneengesloten sedentaire perioden (≥30 min) per dag
- **Detailtabel** per segment

> Scholen met een geschat rooster tonen een gele waarschuwingsbanner bovenaan.

### Slaap
Drie KPI-kaarten (gem. slaap, Δ M1→M2, % onder 8 uur per nacht) gevolgd door:
- **Slaapverdeling per school** — vioolplot met mediaan, te wisselen tussen slaapduur en slaapefficiëntie
- **Bland-Altman M1 vs M2** — meet de overeenstemming tussen de twee metingen; bias ≈ 0 en meeste punten binnen de rode stippellijnen betekent goede reproduceerbaarheid

### Meting 1 vs 2
Vergelijkt de twee meetmomenten op twee sub-tabbladen:

**Longitudinaal**
- Slopegraph: individuele deelnemers als punten, schoolgemiddelde als pijl (interactief, hover = ID + waarden)
- Statistisch overzicht: Wilcoxon signed-rank test per school met Δ, 95%-BI en rang-biseriële effectgrootte (r)
- Effectgrootte-grafiek per school

**Correlaties**
- Correlatiescatter (x-as kiesbaar: MVPA / SB / SB-bouts; y-as = slaapduur) met Pearson r
- Schoolvergelijkingstabel
- Deelnemersvergelijkingstabel M1 vs M2 (sorteerbaar op verandering, met CSV-download)

### Export
Downloadknoppen voor alle verwerkte uitvoerbestanden:
- **GGIR Part 2** — ruwe dagsamenvattingen (draagduur, activiteitsminuten per dag)
- **GGIR Part 5** — persoonsamenvattingen (MVPA-bouten, sedentaire bouten)
- **Segmentoverzicht** — activiteit per schoolsegment (volledige en gefilterde versie)
- **Analysis ready** — brede analysetabel, één rij per deelnemer × meting (volledige en gefilterde versie)
- **Geldigheidsoverzicht** — inclusie/exclusieflags per deelnemer
- **Input manifest** — overzicht van verwerkte invoerbestanden (voor reproduceerbaarheid)
- **Pipeline-run log** — tijdstempel, R-versie en GGIR-versie per run

### Instellingen
Beheer configuratieprofielen en pas parameters aan zonder `config.yaml` te bewerken. Drie secties:

**Profielbeheer** — laad, sla op, en activeer benoemde parametersets (zie sectie 5).

**Geldigheidsparameters** — pas aan wanneer een dag/nacht/meting als geldig telt:
- Min. draaguren per dag (standaard: 16)
- Min. geldige dagen per meting (standaard: 3)
- Weekenddag vereist (aan/uit)
- Min. geldige nachten voor slaapanalyse (standaard: 5)
- Min. % geldige slaap per nacht (standaard: 50%)

**Activiteitsdrempels (ENMO, mg)** — ENMO-grenswaarden voor SB/LPA/MPA/VPA en boutinstellingen. Pas alleen aan als je de wetenschappelijke referentie hebt gecontroleerd (standaard: Hildebrand et al. 2014/2017).

---

## 5. Parameters aanpassen via Instellingen

Het tabblad **Instellingen** laat je de validiteitsdrempels, ENMO-grenswaarden en boutduur aanpassen zonder `config.yaml` handmatig te bewerken.

**Werkwijze:**
1. Pas de velden aan naar wens
2. Klik **Opslaan als…** en geef het een naam (bijv. `gevoeligheidsanalyse_1`)
3. Selecteer het profiel in het dropdown-menu en klik **Activeer**
4. Herstart de pipeline (`run_all.R`) om de nieuwe instellingen toe te passen

Profielen worden opgeslagen in `r/profiles/`. Het actieve profiel wordt bij de volgende start van het dashboard automatisch geladen.

---

## 6. Data exporteren

Alle uitvoerbestanden staan in `data/` (één map boven `data/processed/`):

| Bestand | Inhoud |
|---------|--------|
| `analysis_ready.csv` | Brede tabel: één rij per deelnemer × meting, met gemiddelde MVPA, slaap, activiteitsminuten per segment, en geldigheidsflags |
| `validity_summary.csv` | Inclusie/exclusieoverzicht: voldoet aan sedentair- en slaapcriterium |
| `segment_summary.csv` | Activiteit per schoolsegment (dag-niveau) |

Download knopen zijn ook beschikbaar op het tabblad **Export** in het dashboard.

De `logs/`-map bevat per pipeline-run een logboek en een kopie van de GGIR-configuratie voor reproduceerbaarheid.

---

## 7. Afwezigheden registreren

Als een leerling op een schooldag afwezig was, wil je dat de schooluren van die dag niet meegeteld worden in de analyse (de leerling had geen normaal schoolgedrag).

### Via het dashboard (aanbevolen)

1. Ga naar het tabblad **Instellingen** → sectie **Afwezigheden**
2. Kies de leerling (4-cijferige code), de datum en eventueel een reden (bijv. "ziek")
3. Klik **Toevoegen** — de afwezigheid wordt opgeslagen in `data/absences.csv`
4. Herstart de pipeline (`run_all.R`) om de afwezigheid toe te passen

De schoolsegmenten (les, speeltijd, middagpauze) van die dag worden dan als **"afwezig"** gemarkeerd en uitgesloten uit de activiteitsanalyse.

### Handmatig (gevorderde gebruikers)

Je kunt `data/absences.csv` ook rechtstreeks bewerken in Excel of een teksteditor. Het formaat is:

```csv
pupil_id,date,reason
3025,2026-01-21,ziek
3026,2026-01-22,schooluitstap
```

- `pupil_id`: 4-cijferige leerlingcode (bijv. 3025)
- `date`: datum in formaat `JJJJ-MM-DD`
- `reason`: optionele toelichting

Sla het bestand op en herstart de pipeline.

---

## 8. Veelgestelde vragen en probleemoplossing

**Het dashboard laadt geen data**
→ Controleer of de pipeline volledig is doorgelopen (`run_all.R`) en dat `analysis_ready.csv` bestaat in `data/` (één map boven `data/processed/`).

**De QC meldt "part4 nightsummary not found"**
→ GGIR heeft stap 4 (slaapdetectie) niet doorlopen of de outputmap heeft een andere naam. Controleer of `data/processed/meting_1/output_meting_1/results/` de verwachte mapstructuur bevat.

**School 4 toont een waarschuwing over "geschat rooster"**
→ Het bevestigde lesrooster voor school 4 is nog niet ontvangen. Resultaten voor deze school zijn benaderingen. Stuur het rooster naar de ontwikkelaar om de fallback te verwijderen.

**"No valid days" voor alle deelnemers**
→ Waarschijnlijk is `dev.example_mode` op `false` terwijl de `data/raw/`-map leeg is, of andersom. Controleer de instelling in `config.yaml`.

**Schoolfilter bovenaan het dashboard werkt niet (alle data verdwijnt)**
→ Dit is een bekende bug (zichtbaar als het filter een code toont als `school_1` in plaats van "School 1"). De developer moet `ui.R` updaten voor dit werkt. Gebruik in de tussentijd het filter op "Alle scholen".

**Foutmelding rood in de Deelnemers-tabel**
→ Als de tabel "Error: 'no' is of type logical..." toont, is er een typeconflict in de geldigheidsdata. Dit treedt op als alle deelnemers geldig zijn (lege `exclusion_reason`-kolom in dummy data). De developer moet `mod_participants.R:244` aanpassen.

**Het dashboard start niet / scherm blijft leeg**
→ Dit is een bekende bug: module-bestanden worden geladen op het verkeerde moment. Vraag de developer om de module-bronbestanden naar `global.R` te verplaatsen (zie UX_REVIEW.md U0).

**Pipeline loopt erg lang**
→ GGIR stap 1 kan **30–60 minuten** duren op de volledige dataset van ~400 deelnemers. Dit is normaal. Verhoog `ggir.maxNcores` in `config.yaml` als je op een werkstation werkt (bijv. 4 of 8 cores). Op een laptop is 1 veilig.

**Ik wil opnieuw verwerken maar GGIR slaat stappen over**
→ Zet `ggir.overwrite: true` in `config.yaml` en draai `run_all.R` opnieuw. Vergeet achteraf niet terug te zetten op `false`.

**De "Pipeline uitvoeren"-knop doet niets**
→ Dit is zo ontworpen: de knop toont een venster met de terminalopdracht. De pipeline draait nooit automatisch vanuit het dashboard (GGIR zou de app 30–60 minuten blokkeren). Voer de opdracht uit in een apart terminalvenster en herlaad de app daarna.

---

## 9. Wat doet elke pipelinestap?

De pipeline bestaat uit vijf interne GGIR-stappen en drie R-scripts. Hier is wat er in de praktijk gebeurt.

### GGIR-stap 1 — Inladen en berekenen

GGIR laadt de ruwe versnellingsgegevens uit de CSV-bestanden. Voor elke seconde berekent het de totale bewegingsintensiteit op basis van de x-, y- en z-assen van het horloge. Dit getal — ENMO genaamd — wordt uitgedrukt in mg (milli-g) en is de basis voor alle latere analyses.

**Waarom ENMO en niet de SVMgs uit het CSV-bestand?** De GENEActiv berekent een eigen som (SVMgs) die in het CSV-bestand staat. GGIR herberekent dit cijfer zelf vanuit de ruwe assensignalen. De twee waarden zijn niet identiek: GGIR heeft zijn eigen correctiestap. We gebruiken altijd de GGIR-ENMO.

### GGIR-stap 2 — Kwaliteitscontrole en classificatie

GGIR detecteert automatisch wanneer het horloge *niet* gedragen werd (non-wear) en markeert die perioden. Vervolgens deelt het elke seconde in een intensiteitsklasse in:

| Klasse | ENMO-grens | Betekenis |
|--------|-----------|-----------|
| SB (sedentair) | < 56,3 mg | Stilzitten of liggen |
| LPA (licht) | 56,3 – 191,6 mg | Rustige activiteit (stappen, staand) |
| MPA (matig) | 191,6 – 695,8 mg | Stevig bewegen |
| VPA (intensief) | > 695,8 mg | Intensief sporten |

Dit zijn de Hildebrand-grenswaarden voor polshorloge bij kinderen (2014/2017) en zijn ook ingesteld in `config.yaml`. GGIR maakt dagsamenvattingen per deelnemer (`part2_daysummary.csv`).

### GGIR-stap 3 en 4 — Slaapdetectie

GGIR schat voor elke nacht het slaapperiodevenster (SPT — Sleep Period Time). Het gebruikt hiervoor het HDCZA-algoritme: als de polsbeweging langer dan 5 minuten niet meer dan 5 graden kantelt, wordt aangenomen dat de drager slaapt. Dit algoritme is gevalideerd voor kinderen die een polshorloge dragen.

De nachtresultaten staan in `part4_nightsummary_sleep_cleaned.csv`. De kolom `SleepDurationInSpt` geeft de geschatte slaapduur in uren; `SleepEfficiencyInSpt` geeft het percentage van het slaapvenster dat daadwerkelijk geslapen werd.

### GGIR-stap 5 — Dagsamenvattingen per persoon

GGIR combineert alle vorige stappen tot een persoonssamenvatting: gemiddelde MVPA per dag, sedentaire tijd, bouten (aaneengesloten sedentaire perioden). De outputbestanden heten `part5_personsummary_WW_*.csv` (WW = Waking Window = de wakkere periode op basis van de slaapdetectie).

### Script 02 — Schoolcontext koppelen

Dit script koppelt de dagsamenvattingen van GGIR aan het schoolrooster. Voor elke deelnemer × dag wordt het dagdeel ingedeeld als `les`, `speeltijd`, `middagpauze`, `voor school`, of `na school`. In het weekend wordt de dag als `weekend` gelabeld.

De koppeling is een benadering: GGIR geeft dagsamenvattingen per tijdsblok (via de `qwindow`-instelling). De activiteitsminuten worden proportioneel verdeeld over de segmenten op basis van tijdsoverlap.

### Script 03 — Analyse-tabel en geldigheidsflags

Het derde script voegt alle outputs samen tot één rij per deelnemer × meting. Het berekent ook of een deelnemer voldoet aan de geldigheidsdrempels:

- **Sedentaire geldigheid**: minimaal X draaguren per dag, op minimaal Y geldige dagen (optioneel inclusief een weekenddag)
- **Slaapgeldigheid**: minimaal Z nachten met ≥ 50% slaapefficiëntie

---

## 10. Uitvoerbestanden en interpretatie

Na een succesvolle pipeline-run staan de volgende bestanden in `data/`:

| Bestand | Inhoud | Gebruik |
|---------|--------|---------|
| `data/analysis_ready.csv` | Eén rij per deelnemer × meting. Bevat gem. MVPA/dag, sedentaire tijd, slaap, geldigheidsflags, activiteitsminuten per schoolsegment | Primaire dataset voor statistische analyse |
| `data/validity_summary.csv` | Inclusie/exclusieoverzicht. Welke deelnemer voldoet aan de sedentaire en slaapcriterium, met reden bij exclusie | Rapportage over steekproef |
| `data/segment_summary.csv` | Eén rij per deelnemer × dag × schoolsegment. Activiteitsminuten per context (les, speeltijd enz.) | Verdiepende analyse op segmentniveau |
| `data/processed/meting_N/output_meting_N/results/part2_daysummary.csv` | Dagsamenvattingen direct uit GGIR. Draagduur, intensiteitsminuten per dag | Ruwe controle en heatmap in dashboard |
| `data/processed/meting_N/output_meting_N/results/part4_nightsummary_*.csv` | Nachtresultaten: slaapduur, slaapefficiëntie per nacht | Slaaptabblad in dashboard |
| `data/processed/meting_N/output_meting_N/results/part5_personsummary_WW_*.csv` | Persoonssamenvatting over alle gemeten dagen | Bron voor MVPA en SB in analysis_ready |

**Kolomnamen om te kennen in `analysis_ready.csv`:**

| Kolom | Betekenis |
|-------|-----------|
| `mvpa_min_day_avg` | Gemiddelde MVPA-minuten per dag (matig + intensief) |
| `sb_min_day` | Gemiddelde sedentaire minuten per dag |
| `sleep_duration_h` | Gemiddelde geschatte slaapduur per nacht (uur) |
| `sleep_efficiency_pct` | Gemiddelde slaapefficiëntie (%) |
| `n_valid_days` | Aantal dagen met voldoende draagduur |
| `meets_sedentary_criteria` | TRUE/FALSE — voldoet aan bewegingsgeldigheidscriteria |
| `meets_sleep_criteria` | TRUE/FALSE — voldoet aan slaapgeldigheidscriteria |
| `exclusion_reason` | Reden van uitsluiting als niet geldig |

---

## 11. Bekende beperkingen

**Verwerkingstijd**
GGIR-stap 1 kan 30–60 minuten duren voor de volledige dataset van ~400 deelnemers. Dit is normaal. Het dashboard start je pas na afloop van de pipeline.

**Geheugengebruik**
De pipeline verwerkt één bestand tegelijk; het piekgeheugenverbruik is laag (< 2 GB). Het dashboard laadt alle samenvattingsbestanden in geheugen bij opstarten — voor 400 deelnemers is dit probleemloos op een gewone laptop.

**Geen autokalibratie**
De GENEActiv-CSV-bestanden bevatten pre-berekende epochen, niet de ruwe 100 Hz-signalen. Daardoor kan GGIR geen autokalibratie uitvoeren (sphere-fitting). Kleine sensorafwijkingen worden dus niet gecorrigeerd. Dit is een geaccepteerde beperking zolang er geen .bin-bestanden beschikbaar zijn.

**Slaapefficiëntie-schaal**
GGIR-versies rapporteren slaapefficiëntie soms als percentage (0–100) en soms als fractie (0–1). De pipeline detecteert dit automatisch op basis van de maximale waarde. Controleer bij een eerste echte run of `sleep_efficiency_pct` in het dashboard realistische waarden toont (typisch 80–95% voor schoolkinderen).

**Schoolcontext is een benadering**
De verdeling van activiteitsminuten over segmenten (les, speeltijd enz.) is proportioneel op basis van de tijdsduur van het segment. Een exacte verdeling per seconde vereist GGIR epoch-level uitvoer gekoppeld aan de schoolsegmenten — dit is nog niet geïmplementeerd.

**School 3 — klassenrooster-correctie (tijdelijk beperkt)**
Leerlingen in de klassen 2Aa, 2Ab, 2Ba en 2Bb van school 3 hebben op bepaalde dagen een lesdag tot 16:25 in plaats van 15:35. Door een technische fout in de code worden deze correcties momenteel nog niet toegepast. De segmentgrenzen voor deze 13 leerlingen zijn iets te vroeg. Dit wordt gecorrigeerd voor de eerste echte datarun.

**Dashboard laadt geen nieuwe data zonder herstart**
Het dashboard laadt alle gegevens eenmalig bij opstarten. Als je de pipeline opnieuw draait terwijl het dashboard open staat, moet je de Shiny-app herstarten (`Ctrl+C` in de terminal, dan `shiny::runApp("shiny")`) om de nieuwe resultaten te zien.
