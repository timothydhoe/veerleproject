# SchoolMove — Rehearsal script voor Veerle

> **Doelpubliek:** Veerle Van Oeckel — UGent kinesioloog, kent GGIR goed, geen ontwikkelaar  
> **Totale duur:** 15–20 minuten + discussie  
> **Taal:** Nederlands  
> **Voorbereiding:** Shiny-app draaiend op voorbeelddata, `config.yaml` open in editor

---

## Deel 1 — Opening (1–2 minuten)

**Kernzin om te onthouden:**

> "We hebben een volledig reproduceerbaar systeem gebouwd dat jouw GGIR-workflow automatiseert, schoolcontext toevoegt die GGIR niet kan zien, en alles presenteert in een dashboard zodat je geen code meer nodig hebt."

**Talking points:**

- **Input:** de CSV-bestanden van de GENEActiv-sensoren, per leerling per meting, zoals ze zijn aangeleverd
- **Output:** een interactief dashboard met activiteitstotalen per schoolsegment, slaapstatistieken, geldigheidsoverzicht, en exportklare tabellen — voor alle 6 scholen en beide metingen
- De pipeline draait met één klik. `config.yaml` is de enige plek waar ze ooit iets hoeft aan te passen — geen R-scripts

[PAUSE — vraag aan Veerle: "Voor we beginnen: zijn er specifieke vragen of analyses die je zeker wilt zien?"]

---

## Deel 2 — Pipeline-overzicht (3–5 minuten)

> *Je hoeft GGIR niet uitleggen — ze kent het. Focus op de keuzes die wij gemaakt hebben voor haar studie.*

**Talking points:**

- **GGIR Parts 1–5**, geen Part 6 (circadiaan ritme is buiten scope)
- **`do.cal = FALSE`** — autokalibratie is uitgeschakeld omdat de data als CSV werd aangeleverd, niet als .bin-bestanden. De sensordata is al gecorrigeerd door de GENEActiv-software. Als er later .bin-bestanden beschikbaar komen, is dit één config-switch

  [TECHNISCH BEGRIP — als ze vraagt wat autokalibratie is: "Dat is de sphere-fitting correctie voor sensordrift — GGIR past dit normaal toe op statische momenten in de ruwe sensordata. Bij CSV-bestanden is die ruwe data weg."]

- **Cut-points (Hildebrand 2014/2017):** SB < 56.3 mg, LPA 56.3–191.6 mg, MPA 191.6–695.8 mg, VPA > 695.8 mg — wrist-worn GENEActiv voor kinderen. Dit zijn de standaardwaarden voor haar sensor/populatiecombinatie

  [PAUSE — vraag aan Veerle: "Zijn dit de cut-points die je in je eerdere GGIR-runs gebruikt? En heb je toevallig nog een `config.csv` van een eerdere run? Dan kunnen we de parameters naast elkaar leggen."]

- **Geldigheid:** ≥ 16 uur draag per dag, ≥ 3 geldige dagen, waarvan ≥ 1 weekend. Dit is configureerbaar — als ze een andere drempel wil, is het één getal in config.yaml

- **`qwindow` = [0, 8.5, 10.0, 12.0, 13.0, 15.5, 24]** — dit is de uitbreiding bovenop een standaard GGIR-run. Het vertelt GGIR om per tijdsvenster apart activiteitscijfers te berekenen, zodat stap 2 nauwkeurig schoolcontext kan toewijzen. Dit is nieuw t.o.v. wat GGIR standaard doet

- **Stap 2 — schoolcontext:** GGIR weet niet of 10:05 speeltijd is. Dat weten wij, via de uurroosters in config.yaml. Dit script koppelt die informatie: elk minuut activiteit krijgt een label — `voor_school`, `les`, `speeltijd`, `middagpauze`, `na_school`, `weekend`

- **Stap 3 — samenvattingen:** combineert GGIR's dagoutput, nachtoutput en persoonsoutput in één analysebestand per leerling per meting, inclusief geldigheidsflags

  [SHOW: `config.yaml` — scroll kort langs de `cut_points_mg`, `validity`, en `schedules`-secties om te tonen dat alles op één plek staat]

---

## Deel 3 — De app (5 minuten)

> *Dit is het hoofdevenement. Alles hieronder staat open voor discussie — Veerle bepaalt wat ze wil zien en hoe.*

[SHOW: Shiny-app openen in de browser — startscherm Tab 1 Overzicht]

---


### Tab 1 — Overzicht

**Wat het toont:**
- KPI-ribbon bovenaan: totaal deelnemers, % geldig voor analyse, gemiddelde MVPA, % dat de WHO-norm (60 min/dag) haalt, gemiddelde slaapduur
- Dumbbell-plot: per school het gemiddelde MVPA van meting 1 én meting 2 naast elkaar — je ziet meteen of een school verbeterde of verslechterde
- Automatisch gegenereerde tekstsamenvatting die de cijfers in gewone taal beschrijft

**Waarom het ertoe doet:**
- Geeft haar in één oogopslag een antwoord op de hoofdvraag van het onderzoek — veranderde er iets tussen de twee metingen?
- Handig als startpunt voor rapporten of presentaties: ze kan de tekstsamenvatting kopiëren

[SHOW: klik op een KPI om te tonen dat het doorlinkt naar het juiste tabblad]

[PAUSE — vraag aan Veerle: "Is dit het soort overzicht dat je als startpunt zou willen? Of zijn er andere kerncijfers die hier bovenaan moeten staan?"]

---

### Tab 2 — Deelnemers

**Wat het toont:**
- Inclusietabel: per leerling of ze geldig zijn voor sedentaire analyse en slaapanalyse, en zo niet, waarom niet ("slechts 2 geldige dagen", "geen geldig weekenddag")
- Klik op een leerling: MVPA per dag voor beide metingen, activiteit per schoolsegment gestapeld, draagkalender die met kleur aangeeft op welke dag de drempel gehaald werd

**Waarom het ertoe doet:**
- Maakt exclusies transparant en methodologisch navolgbaar — ze kan dit direct rapporteren
- De draagkalender maakt zichtbaar of een leerling structureel te weinig droeg of alleen op één dag

[SHOW: klik op een leerling in de tabel — toon de drie grafieken die verschijnen]

[PAUSE — vraag aan Veerle: "Als jij een leerling bekijkt, wat is de eerste vraag die je dan hebt? Draagt die leerling het zien hier?"]

---

### Tab 3 — Schooldag

> *Dit is de tab die de kernvraag van het onderzoek beantwoordt.*

**Wat het toont:**
- Per schoolsegment (voor school / les / speeltijd / middagpauze / na school): gemiddelde activiteitsminuten per dag, per school vergelijkbaar
- Sedentaire bouts van ≥ 30 minuten per dag — de langdurige zittende periodes die beleidsmatig interessant zijn
- Weekdagprofiel: op welke dag van de week zijn kinderen het meest actief?

**Waarom het ertoe doet:**
- Dit is het antwoord op RQ1 en RQ2: hoeveel bewegen kinderen per schoolcontext, en hoe lang zitten ze aaneengesloten?
- Direct vergelijkbaar tussen scholen — het verschil in uurroosterstructuur is al verrekend

[SHOW: schakel tussen scholen via het schoolfilter — wijs op het patroon speeltijd vs. les]

[SHOW: als scholen 3 of 4 zichtbaar zijn, wijs op de fallback-banner — "Geschat rooster"]

[PAUSE — vraag aan Veerle: "De segmenten zijn gebaseerd op de uurroosters die we via de documenten konden reconstrueren. Kloppen de tijden voor jouw scholen? Ik heb scholen 3 en 4 nog niet volledig kunnen invullen."]

---

### Tab 4 — Slaap

**Wat het toont:**
- KPI's: gemiddelde slaapduur, verandering M1→M2, % onder de WHO-norm van 8 uur
- Violinplot: verdeling slaapduur per school voor beide metingen — je ziet spreiding én gemiddelde
- Bland-Altman-plot: meet-tot-meet overeenkomst — systematische verandering versus toevallige variatie

**Waarom het ertoe doet:**
- Slaap is een secundaire uitkomst in haar studie — dit geeft het compleet beeld zonder extra analyses
- Het Bland-Altman-plot is methodologisch sterk voor een voor/na-vergelijking

[SHOW: wijs op de nul-lijn in het Bland-Altman-plot en leg de 95%-grenzen uit in één zin]

[PAUSE — vraag aan Veerle: "Is 8 uur de grens die jij wilt hanteren voor de WHO-norm? En wil je de slaapduur per nacht zien, of liever gemiddeld over de week?"]

---

### Tab 5 — Meting 1 vs 2

**Wat het toont:**
- **Sub-tab Longitudinaal:** slopegraph met één lijn per leerling (M1 → M2), schoolgemiddelde als gekleurde pijl, effectgrootte per school met 95%-betrouwbaarheidsinterval, en een Wilcoxon signed-rank tabel met verbale interpretatie (klein / matig / groot effect)
- **Sub-tab Correlaties:** verband tussen activiteit (MVPA, sedentaire tijd, bouts) en slaapduur, per school een aparte kleur

**Waarom het ertoe doet:**
- Dit beantwoordt RQ6: veranderde er iets tussen de twee metingen?
- De effectgrootte zegt meer dan een p-waarde bij kleine schoolsteekproeven
- De correlatie-tab is een bonus: geeft een eerste kijk op de relatie slaap–beweging

[SHOW: kies één metriek (bijv. MVPA), toon de slopegraph, wijs op een leerling die sterk verschuift]

[PAUSE — vraag aan Veerle: "Zijn er specifieke schoolvergelijkingen die voor jou het meest interessant zijn? Of wil je ook vergelijkingen per klas of leerjaar als we die data ooit hebben?"]

---

### Tab 6 — Export

**Wat het toont:**
- Alle outputbestanden als downloadknop: GGIR-dagsamenvatting, segmentsamenvatting, analysebestand, geldigheidsoverzicht — CSV-formaat

**Waarom het ertoe doet:**
- Ze kan de data meenemen naar SPSS, Stata, of haar eigen R-analyses zonder enige extra stap
- Reproduceerbaar: dezelfde config.yaml op dezelfde data geeft altijd hetzelfde bestand terug (`renv` legt alle package-versies vast)

---

### Tab 7 — Instellingen

**Wat het toont:**
- Profielbeheer: namedop parametersets opslaan en laden (geldigheidsdrempels, cut-points, boutduur) — handig als ze verschillende sensitiviteitsanalyses wil vergelijken
- Actief profiel wordt bij opstart geladen vanuit `profiles/`

[PAUSE — vraag aan Veerle: "Is er iets dat je hier niet ziet, maar wel zou willen hebben? Denk aan grafiektypen, filters, of analyses die voor jou essentieel zijn."]

---

## Deel 4 — Live demo talking points

**Aanbevolen demovolgorde:**

1. **Start op Tab 1 (Overzicht)** — geeft meteen een indruk van de data, zelfs op dummydata. Klik op de MVPA-KPI om te tonen hoe de tabs gelinkt zijn.

2. **Ga naar Tab 3 (Schooldag)** — dit is de kernvraag. Toon het schoolsegmentgrafiek, schakel tussen scholen. Wijs op de fallback-banner voor scholen 3 en 4. Dit is een natuurlijk moment om het uurrooster te vragen.

3. **Ga naar Tab 2 (Deelnemers)** — klik op een leerling met een interessant patroon (zoek vooraf één op die duidelijke variatie toont). Toon de draagkalender.

4. **Ga naar Tab 5 (Vergelijking)** — toon de slopegraph, wijs op een leerling die opvalt. Schakel naar de correlatie-sub-tab.

5. **Eindig op Tab 6 (Export)** — sluit af met het praktische verhaal: "De data staat voor je klaar, je kan er meteen mee aan de slag."

**Bekende beperkingen — proactief benoemen:**

- De demo draait op **fictieve testdata** — de patronen zijn realistisch maar de getallen zijn nep. Na een run op echte data is alles hetzelfde, met echte resultaten.
- **Scholen 3 en 4** hebben een geschat uurrooster — segmentresultaten voor deze scholen zijn benaderingen totdat de echte roosters worden aangeleverd.
- **GGIR moet opnieuw draaien** met de nieuwe `qwindow`-parameter voordat de segmentwaarden precies zijn. Momenteel gebruikt stap 2 een proportionele benadering als fallback.
- **Autokalibratie** is uitgeschakeld (CSV-bestanden). Impact naar verwachting klein; reviseerbaar als .bin-bestanden beschikbaar komen.

---

## Deel 5 — Volgende stappen / discussie (2–3 minuten)

**Wat we nog van Veerle nodig hebben:**

- [ ] **Uurroosters scholen 3 en 4** — een bevestigd rooster is één update in config.yaml, dan verdwijnen de fallback-banners
- [ ] **Verificatie cut-points** — kloppen de Hildebrand-waarden met haar protocol? Als ze een `config.csv` van een eerdere GGIR-run heeft, kunnen we het precies verifiëren
- [ ] **Geldigheidsdrempels** — zijn 16 uur/dag en 3 geldige dagen de grenzen die ze wil hanteren? (Aanpasbaar in config.yaml)

**Wat gepland maar nog niet gebouwd is:**

- Aanwezigheidsdetectie (automatisch afwezig-zijn afleiden uit het sensorpatroon) — staat in de planning maar is niet in scope voor de huidige versie
- Regressie- en HLM-analyses als R-uitbreidingsmodule — in overleg met Veerle

**Bestandsformaat — open vraag:**

[PAUSE — vraag aan Veerle: "De pipeline werkt nu met CSV-bestanden. Heb je ook .bin-bestanden beschikbaar? Met .bin-bestanden kan GGIR autokalibratie uitvoeren, wat de nauwkeurigheid verbetert. Als die er zijn, is het één configuratiewijziging om ze te activeren."]

**Testen met echte data:**

[PAUSE — vraag aan Veerle: "Zou het nuttig zijn om de app een keer samen bij jou op kantoor te testen met echte bestanden? Dan kunnen we meteen kijken of de output klopt met wat je verwacht op basis van je eerdere GGIR-runs."]

**Gebruik op langere termijn:**

- Ze kan de pipeline zelfstandig draaien: `config.yaml` aanpassen → `run_all.R` in RStudio starten → dashboard openen
- Er komt nog een gebruikershandleiding bij (in het Nederlands)
- Overdracht gepland voor vóór einde juni 2026

---

## Bijlage — Cheatsheet: snelle antwoorden op verwachte vragen

| Vraag | Antwoord |
|---|---|
| **"Wat is MVPA?"** | Matig-tot-intensieve fysieke activiteit — alles boven 191.6 mg ENMO. De WHO-richtlijn voor kinderen van 6–12 jaar is ≥ 60 minuten per dag. |
| **"Wat is ENMO?"** | Euclidean Norm Minus One — een versnellingsmaat in mg waarbij de zwaartekracht is afgetrokken. GGIR's basismeting. |
| **"Waarom werken we met CSV en niet .bin?"** | Zo zijn de bestanden aangeleverd. .bin biedt autokalibratie (sensorcorrectie), maar de impact is klein bij deze studie. Als .bin beschikbaar komt: één config-switch. |
| **"Hoe lang duurt de pipeline op de echte data?"** | Stap 1 (GGIR) ~2–6 uur op laptop voor ~400 leerlingen × 2 metingen. Stap 2 en 3: seconden. GGIR slaat tussenresultaten op — een onderbroken run verliest geen werk. |
| **"Waarom Hildebrand cut-points?"** | Gevalideerd voor wrist-worn GENEActiv bij kinderen (Hildebrand et al. 2014/2017) — de meest geciteerde waarden voor precies deze sensor/populatie. Aanpasbaar als haar protocol andere waarden specificeert. |
| **"Klopt het uurrooster voor mijn school?"** | Scholen 1, 2, 5, 6 zijn ingevoerd op basis van de aangeleverde documenten. Scholen 3 en 4 zijn benaderingen — we hebben het exacte rooster nog nodig. |
| **"Kan ik een parameter zelf aanpassen?"** | Ja — alles staat in `config.yaml`. Ze past de waarde aan, draait `run_all.R`, en het dashboard toont de nieuwe resultaten. |
| **"Is dit reproduceerbaar?"** | `renv.lock` legt de exacte versies van alle R-packages vast. Dezelfde config.yaml + dezelfde data = identiek resultaat op elke machine, ook over jaren. |
| **"Hoe wordt slaap gedetecteerd?"** | Via GGIR's HDCZA-algoritme: detecteert periodes van langdurige lage armbeweging (arm beweegt < 5 graden over 5 minuten). Gevalideerd voor kinderen met polssensor tegen polysomnografie. |
| **"Kan ik een schoolklas apart bekijken?"** | Momenteel niet — de data is op leerlingniveau zonder klassenindeling. Als klasseninformatie beschikbaar is, kan dit worden toegevoegd als filter. |
| **"Waarom Wilcoxon en geen t-toets?"** | Activiteitsdata bij kinderen is doorgaans scheef verdeeld. Wilcoxon signed-rank maakt geen normaliteitsaanname en is robuuster voor deze data. |
| **"Hoe staat het met GDPR?"** | De ruwe leerlingdata staat nooit in het dashboard — alleen geaggregeerde resultaten. De CSV-bestanden blijven lokaal op haar machine, worden nergens naartoe gestuurd. |
| **"Kan iemand anders dit ook gebruiken?"** | Ja — met de gebruikershandleiding en `renv::restore()` kan elke R-gebruiker de pipeline draaien. Voor andere scholen of studies: config.yaml aanpassen. |
