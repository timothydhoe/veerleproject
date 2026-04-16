# SchoolMove — Live-demoscript voor de promotor

> **Totale duur:** ~45 minuten  
> **Publiek:** promotor van het project — interesse in zowel methodologie/pipeline als resultaten  
> **Taal van de presentatie:** Nederlands

---

## Hoe dit script gebruiken

Elk blok heeft vier onderdelen:

| Label | Wat staat er |
|---|---|
| **Wat tonen** | Welk bestand of tabblad je op het scherm hebt |
| **Zeg dit** | De kern van de uitleg — geen letterlijk script, wel de essentie |
| **Wijs aan** | Concrete UI-elementen, bestandsnamen of regels code die je aanwijst |
| **Verwachte vragen** | Standaardvragen die waarschijnlijk opkomen, met een kort antwoord |

**Vooraf openzetten:**
- RStudio met `r/SchoolMove.Rproj` geladen
- `config.yaml` open in de editor
- Terminal klaar in de `r/` map
- Shiny-app draaiend: `shiny::runApp("shiny")` in de R-console

---

## Deel 1 — Context & onderzoeksvraag

> *~5 min — geen scherm nodig, praat vrij*

**Wat tonen:** niets, of eventueel `docs/planning/plan_of_attack_v2.md` als kapstok

**Zeg dit:**

> "Het startpunt is eenvoudig: ~400 Belgische schoolkinderen droegen een polssensor gedurende één week, twee keer per schooljaar. Zes scholen, twee metingen. Elk kind leverde één groot CSV-bestand per meetperiode op.
>
> De centrale vraag van het onderzoek is: hoeveel bewegen kinderen op school, en wanneer? Niet alleen het totaal, maar ook: is er meer beweging tijdens de speeltijd dan tijdens de les? En hoe vergelijken scholen onderling? Slapen kinderen genoeg?
>
> Op zich is dat een heel redelijke vraag. Maar de ruwe sensordata geeft daar geen antwoord op — die meet gewoon beweging, seconde per seconde, zonder te weten of een kind in de klas zit of buiten speelt. Daarvoor heb je een pipeline nodig die de data verwerkt, en een manier om schoolcontext toe te voegen.
>
> Dat is wat dit project doet. Het eindresultaat is een volledig reproduceerbaar systeem: één keer draaien, en Veerle krijgt een interactief dashboard waar ze alles kan verkennen zonder een regel code aan te raken."

**Verwachte vragen:**

- *"Wat voor sensor is dat?"*  
  → GENEActiv polshorloge van Activinsights. Meet x/y/z-versnelling aan 100 Hz. De bestanden zijn pre-converted CSV's — niet de ruwe binaire sensor output.

- *"Wat is de schaalgrootte in tijd?"*  
  → ~400 leerlingen × 2 metingen × ~7 dagen = zo'n 5.000 dag-observaties.

---

## Deel 2 — De data

> *~3 min*

**Wat tonen:** `config.yaml` — sectie `measurements`

**Zeg dit:**

> "De metadata over de metingen staat centraal in één configuratiebestand: config.yaml. Hier zie je de zes scholen, het aantal leerlingen per school, en de datums waarop de sensoren werden uitgedeeld en teruggebracht. Dit zijn de twee meetvensters per school — meting 1 in de winter/lente, meting 2 later in het jaar.
>
> De bestanden zijn benoemd met een viercijferige code. Het eerste cijfer is het schoolnummer, de rest het leerlingnummer. Dus leerling 063 van school 2 heet '2063'. Meting 1 en meting 2 hebben dezelfde bestandsnaam maar zitten in aparte mappen — GGIR verwerkt ze ook volledig apart.
>
> Eén technisch punt dat ik meteen wil vermelden: de sensor sloeg op als CSV, niet als ruwe .bin-bestanden. Dat heeft een gevolg: GGIR kan geen autokalibratie doen. Autokalibratie corrigeert kleine sensordrift via sphere-fitting op stiltemomentjes — bij binaire bestanden standaard. Bij CSV-bestanden is die informatie weg. Dat is een bewuste trade-off: de data is er zo, en de impact is klein bij deze populatie en deze onderzoeksvragen."

**Wijs aan:**
- `measurements:` sectie in config.yaml — school_1 t/m school_6, `n_pupils`, `meting_1.start/end`

**Verwachte vragen:**

- *"Hoe groot zijn die bestanden?"*  
  → Eén leerling × 7 dagen × 100 Hz = ~60 miljoen rijen ruwe data. De CSV-bestanden bevatten al per-seconde gemiddelden — zo'n 600.000 rijen per leerling.

- *"Waarom CSV en niet .bin?"*  
  → Dat is hoe de bestanden zijn aangeleverd. Als Veerle later toch .bin-bestanden kan aanleveren, kan autokalibratie worden ingeschakeld met één config-change (`do.cal: true`).

---

## Deel 3 — Architectuur & pipeline

> *~12 min*

### 3a — config.yaml als centrale stuurknop

**Wat tonen:** `config.yaml` volledig, scroll langzaam door

**Zeg dit:**

> "Dit is de enige plek die Veerle ooit hoeft aan te raken. Alle parameters die het gedrag van de pipeline bepalen, staan hier: de GGIR-instellingen, de cut-points voor activiteitsintensiteit, de geldigheidsdrempels, de uurroosters van de scholen, en een dev-sectie voor testen met neppdata.
>
> Het idee is simpel: als Veerle morgen besluit dat de geldigheidsdrempel van 16 uur naar 14 uur moet, verandert ze één regel hier. Geen enkel R-script hoeft ze aan te raken. Dat is ook een garantie voor reproduceerbaarheid: dezelfde config.yaml geeft altijd hetzelfde resultaat."

**Wijs aan:**
- `cut_points_mg:` — Hildebrand-waarden (56.3 / 191.6 / 695.8 mg)
- `validity:` — `min_wear_hours_per_day: 16`, `min_valid_days: 3`, `require_weekend_day: true`
- `schedules:` — school_1 volledig (start, einde, pauzes met label en tijdstip)
- `dev:` — `example_mode: true`, `includedaycrit: 5` (versoepeld voor testen)

**Verwachte vragen:**

- *"Waarom 16 uur geldigheid? Dat lijkt streng."*  
  → Het is inderdaad aan de hoge kant — de standaard in de literatuur is eerder 10 uur. Maar dit is de drempel die bepaalt of een dag 'geldig' is voor de sedentair-analyse. De werkelijke inclusiedrempel (≥3 geldige dagen) biedt wat ruimte. Dit is een parameter die Veerle kan aanpassen als ze de literatuur opnieuw wil afwegen.

- *"Wat zijn die Hildebrand cut-points?"*  
  → Drempelwaarden voor activiteitsintensiteit in mg ENMO (Euclidean Norm Minus One — een versnellingsmaat). Hildebrand et al. 2014/2017 valideerden specifiek voor pols-GENEActiv bij kinderen: onder 56.3 mg is sedentair, 56.3–191.6 mg licht, 191.6–695.8 mg matig, boven 695.8 mg intensief.

---

### 3b — Pipeline stap voor stap

**Wat tonen:** `r/pipeline/` folder in RStudio, open `run_all.R`

**Zeg dit:**

> "De pipeline heeft drie stappen. `run_all.R` is het startpunt voor de onderzoeker — dit bronbestand voert de drie stappen na elkaar uit. In de praktijk kan Veerle dit gewoon draaien als alle data er is."

Open `01_run_ggir.R`:

> "Stap 1 is GGIR. Dit is de internationale standaard R-package voor polsversnellingsdata. Eén functieaanroep — `GGIR()` — voert vijf delen uit in volgorde.
>
> **Deel 1:** leest elk CSV-bestand, berekent ENMO en armhoek per seconde.  
> **Deel 2:** niet-draagtijddetectie (SD en range < drempel op twee assen over 60-minuutblokken), activiteitsclassificatie op dagsniveau.  
> **Delen 3 en 4:** slaapdetectie via het HDCZA-algoritme — specifiek gevalideerd voor kinderen met een polssensor. Dit kijkt naar langdurige stilstand van de arm.  
> **Deel 5:** volledig tijdsgebruiksoverzicht per persoon: minuten sedentair, licht, matig-intensief, intensief, sedentaire bouts.
>
> Alle parameters komen uit config.yaml. De qwindow-parameter — die net is toegevoegd — vertelt GGIR om ook per tijdsvenster te rapporteren, zodat stap 2 nauwkeuriger kan werken."

Open `02_label_segments.R`:

> "Stap 2 voegt schoolcontext toe. GGIR weet niet dat 10:05 speeltijd is bij school 1 — dat weten wij, via het uurrooster in config.yaml. Dit script leest de GGIR-output en distribueert activiteitstijd over de contextsegmenten: voor school, les, speeltijd, middagpauze, na school, weekend.
>
> Als GGIR draaide met qwindow (wat nu het geval is na de laatste update), gebruikt dit script de per-tijdsvenster kolommen uit GGIR voor nauwkeurige overlap. Zonder qwindow is het een proportionele schatting — dan zeg je eigenlijk 'als een kind 30% van de dag les heeft, dan was 30% van zijn sedentaire tijd tijdens de les'. Dat is een benadering. Met qwindow is het veel dichter bij de werkelijkheid."

**Wijs aan in 02_label_segments.R:**
- `use_qwindow`-blok (~regel 185) — detecteert of de qwindow-kolommen aanwezig zijn
- `distribute_qwindow_cols()` helper
- `fallback_schools`-vlag en de bijbehorende `WARNING`-melding

Open `03_build_summaries.R`:

> "Stap 3 bouwt de analysetabellen. Het combineert GGIR part2 (dag-niveau), part4 (slaap), part5 (persoonsgemiddelden), en de segmentsamenvatting in één breed analysebestand per leerling per meting. Hier worden ook de geldigheidsflags bepaald — wie voldoet aan de drempels, en wie niet en waarom."

**Wijs aan:** het outputsblok onderaan `03_build_summaries.R` — `analysis_ready.csv`, `validity_summary.csv`

Toon `qc/qc_01_ggir.R` kort:

> "Na elke stap is er een QC-script. Dit controleert of de verwachte bestanden bestaan, of de kolommen kloppen, hoeveel deelnemers er zijn verwerkt, en of de geldigheidspercentages in een redelijke range vallen. Het eindigt met PASS/WARN/FAIL per meting. Zo weet je direct of er iets mis ging voordat je verdergaat."

**Verwachte vragen:**

- *"Hoe lang duurt stap 1 op de echte data?"*  
  → GGIR is intensief. Op een normale laptop: ~400 leerlingen × 2 metingen kan meerdere uren duren. GGIR sloeg voortgang op in tussenbestanden, dus een crash of herstart verliest geen werk. Op een server gaat het uiteraard sneller.

- *"Kan je de stappen apart draaien?"*  
  → Ja. Elk script staat op zichzelf. `run_all.R` is alleen gemak. Als GGIR al klaar is, kun je stap 2 en 3 apart draaien zonder stap 1 opnieuw te doen.

---

### 3c — Methodologische keuzes verantwoorden

**Wat tonen:** `config.yaml` open houden

**Zeg dit:**

> "Een paar keuzes die een promotor terecht zal bevragen:
>
> **GGIR als tool:** dit is de de facto standaard in de literatuur voor verwerking van polsversnellingsdata. Internationaal gevalideerd, open source, gepubliceerd door het onderzoeksteam van Van Hees. De keuze voor GGIR is metodologisch niet controversieel.
>
> **Cut-points:** Hildebrand et al. 2014 en 2017, specifiek voor pols-GENEActiv bij kinderen. Dit zijn de meest geciteerde waarden voor deze sensor/populatiecombinatie. Ze staan in config.yaml zodat Veerle ze eenvoudig kan aanpassen als haar protocol andere waarden specificeert.
>
> **HDCZA voor slaap:** gevalideerd voor kinderen met een polssensor (van Hees 2015), gebaseerd op armhoek (anglez). Twee parameters: arm moet minder dan 5 graden bewegen over 5 minuten om als slaapkandidaat te tellen. Dit zijn Veerle's protocolwaarden.
>
> **Geldigheidscriterium sedentair:** minstens 16 uur draag per dag, minstens 3 geldige dagen, waarvan minstens 1 weekend. Dit is streng maar bepaalt wie meegenomen wordt in de analyse. Aanpasbaar in config.yaml."

**Verwachte vragen:**

- *"Zijn de cut-points al bevestigd door Veerle?"*  
  → Hildebrand is de standaard voor deze sensor/populatie. Veerle's eigen eerdere GGIR-runs gebruikten waarschijnlijk dezelfde waarden — maar dat is nog een open verificatiepunt. Als ze een `config.csv` van een eerdere GGIR-run heeft, kunnen we de waarden vergelijken.

---

## Deel 4 — Dashboard live demo

> *~20 min — Shiny-app draait in de browser*

**Start:** `shiny::runApp("shiny")` in de R-console vanuit de `r/` map

---

### Tab 1 — Overzicht

**Wat tonen:** tabblad Overzicht

**Zeg dit:**

> "Dit is het beginscherm. Bovenaan een KPI-ribbon: het totaal aantal deelnemers, hoeveel procent geldig zijn voor de sedentaire analyse, gemiddelde MVPA per dag, het percentage dat de WHO-norm haalt, en gemiddelde slaap. Klikken op een KPI navigeert rechtstreeks naar het bijbehorende tabblad.
>
> Het hoofdgrafiek is een dumbbell-plot: per school zie je het gemiddelde MVPA van meting 1 en meting 2, met een 95%-betrouwbaarheidsinterval. Zo zie je in één oogopslag of scholen zijn verbeterd, verslechterd, of stabiel zijn tussen de twee metingen.
>
> Onderaan is een automatisch gegenereerde narratieve samenvatting — een paragraaf die de cijfers in gewone taal beschrijft. Dat is handig als Veerle iets wil kopiëren voor een rapport."

**Wijs aan:**
- KPI-ribbon (klik één KPI om te laten zien dat het navigeert)
- Dumbbell-plot — wijs op de pijl per school (M1 → M2)
- Narratief tekstvak + kopieerknop

**Verwachte vragen:**

- *"Wat is MVPA precies?"*  
  → Matig-tot-intensieve fysieke activiteit (Moderate-to-Vigorous Physical Activity). Alles boven 191.6 mg ENMO op de pols. De WHO-richtlijn voor kinderen is minstens 60 minuten MVPA per dag.

- *"Wat betekent 95%-betrouwbaarheidsinterval hier?"*  
  → Het interval rond het schoolgemiddelde — geeft een idee van de spreiding binnen de school. Brede intervallen = grote individuele variatie.

---

### Tab 2 — Deelnemers

**Wat tonen:** tabblad Deelnemers

**Zeg dit:**

> "Dit tabblad gaat naar het niveau van de individuele leerling. Rechts de inclusietabel: wie voldoet aan de geldigheidsdrempels, wie niet, en waarom niet — 'slechts 2 geldige dagen' of 'geen geldig weekenddag'. Dat maakt de exclusies transparant en navolgbaar.
>
> Als je een leerling selecteert — of op een rij klikt — zie je links een drieluik: de MVPA per dag voor meting 1 en 2 naast elkaar, de activiteitstijd per schoolsegment als gestapelde balk, en een draagkalender die per dag met kleur aangeeft of de drempel gehaald werd. Dat laatste is handig om te zien of een leerling structureel te weinig droeg of alleen op een specifieke dag."

**Wijs aan:**
- Dropdown of tabelrij om een leerling te selecteren
- Draagkalender — wijs op het kleurcodesysteem (groen = geldig, rood/grijs = ongeldig)
- Exclusiereden in de tabel

**Verwachte vragen:**

- *"Wat als een leerling net één dag tekortkomt?"*  
  → Dan valt hij uit de sedentaire analyse, maar zijn data is niet weg. De geldigheidsdrempel is instelbaar in config.yaml. Als Veerle 2 geldige dagen voldoende vindt, is dat één regelwijziging.

---

### Tab 3 — Schooldag

> ← *Dit is de kernvraag van het onderzoek*

**Wat tonen:** tabblad Schooldag

**Zeg dit:**

> "Dit is de tab waar het onderzoek eigenlijk om draait. Je ziet per schoolsegment — voor school, les, speeltijd, middagpauze, na school — hoeveel gemiddelde activiteitstijd per dag. Dit per school, zodat je direct kunt vergelijken.
>
> Het patroon dat je typisch verwacht: de meeste beweging tijdens speeltijd, de langste sedentaire blok tijdens de les. Maar de vraag is hoe groot dat verschil is, en of het varieert tussen scholen.
>
> Daaronder: sedentaire bouts van minstens 30 minuten per dag — dat zijn de langdurige zittende periodes die beleidsmatig interessant zijn. En een weekdagprofiel dat toont op welke dag van de week kinderen het meest actief zijn."

**Wijs aan:**
- Segmentgrafiek — wijs de vijf segmentkleuren aan
- Schoolfilter in de navigatiebalk bovenaan — laat zien dat je kan filteren op één school
- Fallback-banner (als zichtbaar) — "Scholen 3 en 4 gebruiken een geschatte uurrooster"
- Bouts-grafiek onderaan

**Verwachte vragen:**

- *"Waarom zijn scholen 3 en 4 gestippeld / met een waarschuwing?"*  
  → Hun uurrooster is nog niet bevestigd — we hebben een benadering gebruikt op basis van de Belgische standaard schooldag. De resultaten voor deze scholen moeten met voorbehoud worden geïnterpreteerd totdat Veerle het exacte uurrooster doorstuurt. Dat is één update in config.yaml.

- *"Hoe nauwkeurig zijn die segmentwaarden?"*  
  → De pipeline gebruikt nu qwindow in GGIR, waardoor we per tijdsvenster gerapporteerde activiteitsminuten hebben. Die worden gewogen overlapt met het uurrooster. Dat is nauwkeuriger dan de proportionele benadering van vroeger — maar pas na een nieuwe GGIR-run. Op dummy data is de verbetering al zichtbaar.

---

### Tab 4 — Slaap

**Wat tonen:** tabblad Slaap

**Zeg dit:**

> "Dit tabblad rapporteert over slaap. Bovenaan drie KPI's: gemiddelde slaapduur, de verandering van meting 1 naar 2, en het percentage kinderen dat de WHO-norm van 8 uur per nacht niet haalt.
>
> Het violinplot toont de verdeling van slaapduur per school voor beide metingen naast elkaar. Je ziet zo niet alleen het gemiddelde maar ook de spreiding — zijn er uitschieters? Is de verdeling scheef?
>
> Het Bland-Altman-plot toont de overeenkomst tussen meting 1 en meting 2. De x-as is het gemiddelde van de twee metingen, de y-as het verschil. Als punten systematisch boven of onder nul liggen, is er een structurele verandering tussen meting 1 en 2. De stippellijnen zijn de 95%-limieten van overeenkomst."

**Wijs aan:**
- Violinplot — wijs op school-voor-school vergelijking
- Bland-Altman — wijs op de nul-lijn en de 95%-grenzen
- Infobox (i-icoontje) — uitleg van het Bland-Altman-principe

**Verwachte vragen:**

- *"Hoe wordt slaap gedetecteerd?"*  
  → Via het HDCZA-algoritme in GGIR. Dat detecteert periodes van langdurige lage armbeweging (anglez-variatie < 5 graden over 5 minuten). Dit is gevalideerd voor kinderen met een polssensor, met polysomnografie als goudstandaard.

- *"Is 8 uur de juiste norm?"*  
  → Dat is de WHO/AAP-aanbeveling voor kinderen van 6–12 jaar. Aanpasbaar in `global.R` (`WHO_SLEEP_MIN_H`), of we kunnen het naar config.yaml verplaatsen als Veerle een andere grens wil hanteren.

---

### Tab 5 — Vergelijking

**Wat tonen:** tabblad Vergelijking → sub-tab Longitudinaal

**Zeg dit:**

> "Dit tabblad beantwoordt de vraag: veranderde er iets tussen meting 1 en meting 2? Per leerling als individuele lijn in de slopegraph, en als schoolgemiddelde als gekleurde pijl. Je kiest zelf de metriek: MVPA, sedentaire tijd, sedentaire bouts, lichte activiteit, of slaap.
>
> De effectgrootte-grafiek rechts toont het gemiddeld verschil per school met 95%-betrouwbaarheidsinterval. Als het interval de nul niet snijdt, is er statistisch bewijs voor een verschil.
>
> Onderaan de statistische tabel: Wilcoxon signed-rank test per school — dit is een niet-parametrische toets, gepast voor distributies die niet normaal zijn. De effectgrootte is de rank-biseriale correlatie, met een verbale interpretatie (klein / matig / groot)."

Klik door naar sub-tab **Correlaties**:

> "Dit sub-tabblad toont de samenhang tussen activiteit en slaap. X-as is instelbaar: MVPA, sedentaire tijd, of bouts. Y-as is altijd slaapduur. Per school een aparte kleur, met regressielijn en 95%-band."

**Wijs aan:**
- Slopegraph — wijs op één individuele leerling die omhoog of omlaag gaat
- Effectgrootte-balk die de nul wel/niet snijdt
- Statistische tabel — wijs op de verbale interpretatie (bijv. "matig effect")

**Verwachte vragen:**

- *"Waarom Wilcoxon en niet een t-toets?"*  
  → Activiteitsdata bij kinderen is doorgaans scheef verdeeld. De Wilcoxon signed-rank toets maakt geen aanname over normaliteit en is robuuster voor deze data.

- *"Is de steekproef groot genoeg voor schoolvergelijkingen?"*  
  → Scholen hebben 55–80 leerlingen, maar na inclusiecriteria kan dat lager uitvallen. De effectgrootte en het 95%-interval geven een eerlijk beeld van de zekerheid. Als de steekproef te klein is per school, wordt dat zichtbaar in brede intervallen.

---

### Tab 6 — Export

**Wat tonen:** tabblad Export

**Zeg dit:**

> "Het laatste tabblad is puur praktisch. Alle outputbestanden zijn hier downloadbaar: de GGIR-dagsamenvatting, het analysebestand, de segmentsamenvatting, het geldigheidsoverzicht. Handig als Veerle de data zelf wil meenemen naar SPSS of R voor aanvullende analyses.
>
> Reproduceerbaar betekent ook: als Veerle de pipeline morgen op een andere laptop draait met dezelfde config.yaml, krijgt ze bit-voor-bit hetzelfde resultaat. Dat garandeert `renv` — een package manager die de exacte versies van alle R-packages vastlegt."

**Verwachte vragen:**

- *"Kan Veerle dit zelf draaien na overdracht?"*  
  → Ja, dat is het doel. Ze opent `SchoolMove.Rproj` in RStudio, zet `example_mode: false` in config.yaml, en draait `run_all.R`. Er komt nog een gebruikershandleiding bij.

---

## Deel 5 — Beperkingen & open punten

> *~5 min*

**Wat tonen:** `config.yaml` → sectie `schedules`, scholen 3 en 4

**Zeg dit:**

> "Een eerlijk beeld van wat er nog niet klopt of nog openstaat:
>
> **Scholen 3 en 4:** hun uurrooster is een benadering. School 3 is nooit aangeleverd. School 4 was beschikbaar als afbeelding en kon niet volledig worden geparsed. Zodra Veerle de exacte roosters doorstuurt, is het één update in config.yaml. De code is er al klaar voor.
>
> **qwindow en GGIR herdraaien:** de qwindow-parameter is pas recent toegevoegd. Bestaande GGIR-output heeft die per-tijdsvenster kolommen nog niet. Dat betekent dat stap 2 voor nu nog terugvalt op proportionele schatting. Na één herrun van stap 1 op de echte data is dat opgelost.
>
> **Autokalibratie:** niet mogelijk met CSV-bestanden. Als er ooit .bin-bestanden beschikbaar komen, is dit één config-switch. De impact op de resultaten is naar verwachting klein bij deze studie.
>
> **Cut-points verificatie:** Hildebrand is de standaard, maar we hebben Veerle's eigen eerdere GGIR-configuratie nog niet vergeleken. Als zij een `config.csv` van een eerdere run heeft, kunnen we de parameters naast elkaar leggen."

**Verwachte vragen:**

- *"Wat is de impact van de proportionele benadering?"*  
  → Ze kan de segmentwaarden vertekenen als activiteit sterk ongelijk verdeeld is over de dag. In de praktijk geldt: speeltijden zijn kort maar intensief — proportionele schatting zou de speeltijaactiviteit onderschatten. Precies de reden waarom qwindow belangrijk is.

---

## Deel 6 — Volgende stappen

> *~2 min*

**Zeg dit:**

> "De concrete volgende stappen zijn:
>
> 1. **Pipeline draaien op echte data** — zodra de CSV-bestanden beschikbaar zijn, draait de pipeline meteen. config.yaml staat klaar.
> 2. **Uurrooster scholen 3 en 4 aanleveren** — één update, dan zijn die scholen niet meer gemarkeerd als 'schatting'.
> 3. **Gebruikershandleiding voor Veerle** — zodat ze het dashboard zelfstandig kan bedienen en interpreteren.
> 4. **Overdracht** — gepland voor voor einde juni 2026, inclusief een walkthrough-sessie."

---

## Bijlage — Woordenlijst & veelgestelde vragen

### Begrippen

| Term | Uitleg |
|---|---|
| **ENMO** | Euclidean Norm Minus One — een versnellingsmaat (in mg) waarbij de zwaartekracht is afgetrokken. De basismeting van GGIR. |
| **MVPA** | Matig-tot-intensieve fysieke activiteit — alles boven 191.6 mg ENMO op de pols. |
| **SB / LPA** | Sedentair gedrag (< 56.3 mg) en lichte activiteit (56.3–191.6 mg). |
| **GGIR** | De R-package voor verwerking van polsversnellingsdata. Parts 1–5 dekken alles van ruwe data tot slaapdetectie. |
| **HDCZA** | Het slaapdetectie-algoritme in GGIR, gebaseerd op langdurige lage armbeweging. |
| **qwindow** | GGIR-parameter die de dag opdeelt in tijdsvensters. Geeft per venster apart activiteitscijfers. |
| **Meting** | Eén meetperiode van ~7 dagen. Meting 1 en meting 2 zijn twee golven per school. |
| **Segment** | Schoolcontextlabel: voor school, les, speeltijd, middagpauze, na school, weekend. |

### Aanvullende vragen

- *"Waarom geen Python?"*  
  → R is de taal van GGIR en van de meeste versnellingsonderzoeksgroepen. Alles in één taal houdt het onderhoudbaar. Python kan later worden toegevoegd voor specifieke noden, maar is nu niet nodig.

- *"Wat als Veerle een andere parameter wil proberen?"*  
  → Ze past config.yaml aan en draait `run_all.R` opnieuw. GGIR-output die al bestaat, wordt niet opnieuw berekend tenzij `overwrite: true` staat. Stap 2 en 3 zijn snel (seconden tot minuten).

- *"Hoe reproduceerbaar is dit echt?"*  
  → `renv.lock` legt de exacte versies van alle R-packages vast — inclusief GGIR, data.table, Shiny, ggplot2. Op elke machine met R ≥ 4.1 geeft `renv::restore()` exact dezelfde omgeving terug.

- *"Hoe lang duurt de volledige pipeline op de echte data?"*  
  → Schatting: stap 1 (GGIR) ~2–6 uur op een gewone laptop voor 400 leerlingen × 2 metingen, afhankelijk van hardware. Stap 2 en 3 zijn seconden. GGIR slaat tussenresultaten op, dus een onderbroken run verliest geen werk.
