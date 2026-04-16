# SchoolMove — Gebruikersgids

Geschreven voor Veerle Van Oeckel (UGent). Dit document beschrijft alles wat je nodig hebt om de pipeline te draaien, het dashboard te gebruiken en de resultaten te exporteren.

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

### Overzicht
Toont hoeveel deelnemers geldig zijn (voldoen aan de draagcriteria), verdeeld per school en meting. Bevat een draaguren-heatmap per deelnemer.

### Deelnemers
Detailtabel per deelnemer: geldige dagen, gemiddelde draaguren, of er een weekenddag is, geldigheidscriterium gehaald (ja/nee).

### Schooldag
Gemiddelde MVPA-minuten per schoolsegment (voor school, les, speeltijd, middagpauze, na school). Filter op school en meting. Gebruik dit tabblad voor de schoolcontextanalyse.

### Slaap
Gemiddelde slaapduur en slaapefficiëntie per school, op basis van de GGIR Part 4 nacht-samenvatting (HDCZA-algoritme).

### Vergelijking
Vergelijkt meting 1 en meting 2 op deelnemersniveau (scatter- of boxplots). Handig voor het bekijken van veranderingen tussen de twee meetmomenten.

### Export
Download knoppen voor de uitvoerbestanden:
- `analysis_ready.csv` — brede tabel, één rij per deelnemer × meting
- `validity_summary.csv` — geldigheidsflags per deelnemer
- `segment_summary.csv` — activiteit per schoolsegment

### Instellingen
Beheer configuratieprofielen (zie sectie 5).

---

## 5. Parameters aanpassen via Instellingen

Het tabblad **Instellingen** laat je de validiteitsdrempels, ENMO-grenswaarden en boutduur aanpassen zonder `config.yaml` handmatig te bewerken.

**Werkwijze:**
1. Pas de schuifregelaars en velden aan naar wens
2. Klik **Opslaan als profiel** en geef het een naam (bijv. `gevoeligheidsanalyse_1`)
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

## 7. Veelgestelde vragen en probleemoplossing

**Het dashboard laadt geen data**
→ Controleer of de pipeline volledig is doorgelopen (`run_all.R`) en dat `analysis_ready.csv` bestaat in `data/processed/`.

**De QC meldt "part4 nightsummary not found"**
→ GGIR heeft stap 4 (slaapdetectie) niet doorlopen of de outputmap heeft een andere naam. Controleer of `data/processed/ggir/meting_1/` de verwachte mapstructuur bevat.

**School 3 of 4 toont een waarschuwing over "fallback schedule"**
→ De bevestigde lesroosters voor deze scholen zijn nog niet ontvangen. Resultaten voor deze scholen zijn benaderingen. Stuur het rooster naar de ontwikkelaar om de fallback te verwijderen.

**"No valid days" voor alle deelnemers**
→ Waarschijnlijk is `dev.example_mode` op `false` terwijl de `data/raw/`-map leeg is, of andersom. Controleer de instelling in `config.yaml`.

**Pipeline loopt erg lang**
→ GGIR stap 1 kan uren duren op de volledige dataset. Verhoog `ggir.maxNcores` in `config.yaml` als je op een werkstation werkt (bijv. 4 of 8 cores). Op een laptop is 1 veilig.

**Ik wil opnieuw verwerken maar GGIR slaat stappen over**
→ Zet `ggir.overwrite: true` in `config.yaml` en draai `run_all.R` opnieuw. Vergeet achteraf niet terug te zetten op `false`.
