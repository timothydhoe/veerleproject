# Technisch Verslag: Project "SchoolMove" (Update)

**Datum:** 23 maart 2026  
**Project:** Accelerometer Data Pipeline & Gedragsanalyse  
**Klant:** Veerle Van Oeckel – Vakgroep Volksgezondheid en Eerstelijnszorg (GE39)  
**Tijdlijn:** 7 – 10 weken  

---

## 1. Projectcontext & Doelstelling

In opdracht van de vakgroep GE39 wordt een systeem ontwikkeld om fysieke activiteit bij ~400 kinderen (6 scholen) te analyseren. De focus ligt op de vernieuwing van de bestaande workflow door middel van een robuuste data-pipeline die ruwe data omzet in bruikbare inzichten voor de evaluatie van bewegingsstimulering op school.

### extras:

MCP GGIR:
  - https://context7.com/wadpac/ggir?chat=b63c3ecb-0507-4810-a3f3-9383803f9480

---

## 2. Data-acquisitie & Hardware Specificaties

- **Sensoren:** Polsgedragen accelerometers (niet-dominante hand), 24/7 gedragen  
- **Bestandsformaat:** Ruwe `.bin` bestanden  

### Hardware Types
- **Type 1:** Automatische stopzetting na 7 dagen
- **Type 2:** Vooringestelde start/stop (of handmatige trigger)

- **Data-integriteit:**  
  Het systeem moet robuust omgaan met:
  - *Over-meting* (data buiten de relevante week)
  - *Onder-meting* (onvoldoende data voor validatie)

- **ID-Structuur:**  
  Elk kind krijgt een uniek ID waarbij:
  - Eerste cijfer = school
  - Volgende drie cijfers = volgnummer kind
  - Voorbeeld: `1001` → school 1, kind 1

---

## 3. Technische Architectuur & Pipeline

- **Software Stack:**  
  Transitie en integratie tussen **R (GGIR package)** en **Python**  
  - Kernanalyse: GGIR-logica  
  - Pipeline & UI: Python (voor schaalbaarheid)

- **Signaalverwerking:**
  - Omzetting van x-, y-, z-assen naar de **ENMO-getalswaarde**
  - Gebruik van **GGIR Part 5 thresholds** voor classificatie:
    - Sedentair  
    - Licht  
    - Matig  
    - Intensief  

- **MCP Server:**  
  Inzet van een Model Context Protocol server om technische documentatie  
  (bijv. Zenodo-records en GGIR-manuals) direct door AI-tools leesbaar te maken voor snelle probleemoplossing.

---

## 4. Functionele Analyse-eisen

De output moet specifiek inzicht geven in:

- **Activiteitsduur:**  
  Totaal aantal minuten per activiteitstype per dag  

- **Sedentair Gedrag:**  
  Identificatie van sedentaire *bouts* (periodes) langer dan 30 minuten  

- **Slaap-analyse:**  
  Implementatie van het *DetectSleep* algoritme (conform GGIR)  
  versus *non-wear* detectie (sensor afdoen)  

- **Contextuele Segmentatie:**  
  Onderscheid tussen:
  - Activiteiten op school (lessen vs. speeltijd)  
  - Activiteiten buiten schooluren  

---

## 5. Intelligent Attendance & UI

Een kritisch onderdeel van de opdracht is het omgaan met afwezigheden:

- **Absentie-detectie:**  
  Filteren van data voor leerlingen die op specifieke dagen afwezig waren  

- **Predictive Patterns:**  
  Onderzoek naar het voorspellen van afwezigheid via patronen, zoals:
  - Typische *pendeltijd* naar school  

- **UI Interface:**  
  Ontwikkeling van een dashboard dat:
  - Data uit een folder automatisch inleest  
  - Analyses visualiseert  
  - Een *manual check* biedt om voorspelde aanwezigheid te bevestigen of corrigeren  

---

## 6. Rework & AI Engineering Benefits

Het vernieuwde systeem biedt drie grote voordelen:

- **Systeeminformatie:**  
  Alles wordt samengebracht in één breed, aanpasbaar systeem  

- **Data-imputatie:**  
  Slimme afhandeling van:
  - NaN-waarden  
  - Ontbrekende data (bijv. te vroeg / te laat op school)  

- **Gebruiksvriendelijkheid ("RAGske"):**  
  Implementatie van een AI-handleiding via **RAG (Retrieval-Augmented Generation)**  
  → Directe antwoorden op vragen over data en methodiek zonder zware documentatie  

---

## Volgende stappen

- Start ontwikkeling van de UI die data uit een bronfolder kan inlezen  
- Script opstellen voor het genereren van dummy-datasets conform de nieuwe ID-structuur (1 + 3 cijfers)  
- Prototype bouwen voor de *pendel-detectie* om aanwezigheid te valideren  