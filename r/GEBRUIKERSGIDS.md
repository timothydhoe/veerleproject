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

Alle uitvoerbestanden staan in `data/processed/`:

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
→ Controleer of de pipeline volledig is doorgelopen (`run_all.R`) en dat `analysis_ready.csv` bestaat in `data/processed/`.

**De QC meldt "part4 nightsummary not found"**
→ GGIR heeft stap 4 (slaapdetectie) niet doorlopen of de outputmap heeft een andere naam. Controleer of `data/processed/ggir/meting_1/` de verwachte mapstructuur bevat.

**School 4 toont een waarschuwing over "fallback schedule"**
→ Het bevestigde lesrooster voor school 4 is nog niet ontvangen. Resultaten voor deze school zijn benaderingen. Stuur het rooster naar de ontwikkelaar om de fallback te verwijderen.

**"No valid days" voor alle deelnemers**
→ Waarschijnlijk is `dev.example_mode` op `false` terwijl de `data/raw/`-map leeg is, of andersom. Controleer de instelling in `config.yaml`.

**Pipeline loopt erg lang**
→ GGIR stap 1 kan uren duren op de volledige dataset. Verhoog `ggir.maxNcores` in `config.yaml` als je op een werkstation werkt (bijv. 4 of 8 cores). Op een laptop is 1 veilig.

**Ik wil opnieuw verwerken maar GGIR slaat stappen over**
→ Zet `ggir.overwrite: true` in `config.yaml` en draai `run_all.R` opnieuw. Vergeet achteraf niet terug te zetten op `false`.
