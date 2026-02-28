# UniVROrari (iOS)

App iOS SwiftUI per la gestione orari lezioni UniVR.

## Cosa include questo MVP

- Selezione livello corso: `Triennale` / `Magistrale`.
- Selezione corso di studi (caricato live dai dati UniVR).
- Ricerca rapida corsi con barra dedicata.
- Vista orario settimanale con:
  - data
  - orario
  - aula
  - professore
  - edificio
- Sezione aule con:
  - corsi programmati nella giornata per edificio selezionato
  - aule libere con fascia oraria
- Ricerca rapida aule/corsi/docenti con barra dedicata.
- Persistenza preferenze utente su `UserDefaults`:
  - livello
  - corso
  - anno corso
  - edificio
- Cache offline locale degli ultimi dati:
  - corsi
  - edifici
  - orari lezioni (per corso/anno/settimana)
  - disponibilita aule (per edificio/data)

## Sorgente dati (pull diretto da UniVR)

L'app usa endpoint del portale ufficiale UniVR (EasyAcademy):

- `https://logistica.univr.it/PortaleStudentiUnivr/combo_call.php`
- `https://logistica.univr.it/PortaleStudentiUnivr/call.php`
- `https://logistica.univr.it/PortaleStudentiUnivr/rooms_call.php`

## Struttura progetto

- `UniVROrari/Sources/App`
  - entrypoint app + stato globale
- `UniVROrari/Sources/Data`
  - client HTTP + parsing risposte UniVR
- `UniVROrari/Sources/Domain`
  - modelli e helper data
- `UniVROrari/Sources/Features/WeeklySchedule`
  - schermata orario settimanale
- `UniVROrari/Sources/Features/Rooms`
  - schermata aule/occupazione/libere

## Build da terminale

```bash
xcodebuild -project UniVROrari.xcodeproj \
  -scheme UniVROrari \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./.derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Note attuali

- Il filtro `Triennale/Magistrale` usa matching sul nome del corso (euristiche), quindi in alcuni casi può richiedere un raffinamento con naming reale UniVR.
- Le richieste sono live (nessun backend intermedio), con fallback automatico alla cache offline se la rete non e disponibile.
