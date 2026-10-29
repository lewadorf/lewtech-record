# Lewtech Record — norsk brukerveiledning

[Til hovedsiden](../README.md) · [Nedlastinger](https://github.com/lewadorf/lewtech-record/releases)

En lokal Mac-app for skjerm, kamera og mikrofon. Loom-inspirert opptaksflyt med Lewtechs farger, Manrope-typografi og egen app-identitet. Ingen konto eller nettforbindelse er nødvendig for å bruke appen.

## Installer og åpne

Krever macOS 15 eller nyere og Apples Command Line Tools for å bygge. Full Xcode er ikke nødvendig. Kjør fra prosjektmappen i Terminal:

```sh
./scripts/install.sh
open "$HOME/Applications/Lewtech Record.app"
```

Installeringsskriptet bygger appen, kontrollerer signaturen og legger den i `~/Applications/Lewtech Record.app`. Avslutt en eventuell åpen Lewtech Record først, også fra menylinjen. En tidligere installasjon beholdes i `~/Applications/.Lewtech Record backups/`. Opptaksmappen berøres ikke.

Appen kan deretter åpnes fra Finder uten Terminal. Bygget er lokalt signert; App Store-publisering og notariseringsoppsett inngår ikke.

## Ta opp en video

1. Velg **Nytt opptak**, og velg skjerm + kamera, kun skjerm eller kun kamera.
2. Velg skjerm eller vindu, kamera og mikrofon. Slå av mikrofonen for video uten stemmelyd.
3. Kontroller den levende forhåndsvisningen og mikrofonmåleren. Velg rund eller firkantet **Facecam**, dra i hjørnehåndtaket for å justere størrelsen og dra selve bildet til ønsket plassering. Forhåndsvisning lagrer ingen video eller lyd.
4. Velg **Start opptak**. Etter en nedtelling på tre sekunder starter opptaket.
5. Bruk det flytende kontrollpanelet eller menylinjeikonet for pause, fortsett og stopp. Kameraboblen kan flyttes under skjerm + kamera-opptak.
6. Velg **Stopp og lagre**. Videoen vises i biblioteket når lagringen er ferdig.

Opptakskontrollene holdes utenfor videoen. Kameraboblen kompositeres inn i selve videofilen. Pausetid tas bort fra både lyd- og videotidslinjen.

Snarveiene virker når Lewtech Record er aktiv; de er ikke globale:

| Handling | Snarvei |
| --- | --- |
| Nytt opptaksoppsett | ⌘N |
| Start opptak | ⇧⌘R |
| Pause / fortsett | ⇧⌘P |
| Stopp og lagre | ⇧⌘S |

Når du arbeider i andre apper, bruker du det flytende panelet eller menylinjeikonet.

## Tillatelser

macOS ber om **Skjermopptak**, **Kamera** og **Mikrofon** når de aktuelle funksjonene brukes. Godkjenn bare enhetene du vil bruke. Tilgangen kan endres under **Systeminnstillinger → Personvern og sikkerhet**; appens **Innstillinger** har direkte lenker dit.

Hvis skjermbildet mangler, bruk **Åpne skjermtilgang i macOS** i opptaksstudioet. Et nytt lokalt signert bygg kan kreve at tillatelsen gis på nytt. Hvis macOS ber om omstart etter skjermtilgang, avslutt og åpne appen igjen. Bruk **Oppdater enheter** hvis et kamera, en mikrofon eller et vindu mangler. Vinduoversikten krever skjermtilgang.

## Bibliotek, eksport og lagring

- Standardmappe: `~/Movies/Lewtech Record/`.
- Biblioteket har søk, sortering, navneendring, avspilling og **Vis i Finder**.
- **Eksporter MP4** lagrer en kopi i en mappe du velger. Filen kan åpnes i QuickTime og deles som en vanlig fil.
- Sletting flytter videoen til macOS-papirkurven.
- Avbrutte opptak undersøkes ved oppstart. Spillbare filer kan gjenopprettes; øvrige fragmenter beholdes i `.incomplete`. Gjenoppretting kan ikke garanteres etter et avbrudd.

Video lagres som MP4 med H.264 og, når mikrofon er aktiv, AAC-lyd. Oppløsningen tilpasses kilden med et tak på 1920 × 1080 og mål om 30 bilder per sekund. Små vinduer og andre sideforhold kan gi lavere oppløsning. Det finnes ingen innebygd varighetsgrense; ledig diskplass og maskinens kapasitet begrenser opptaket.

Denne versjonen tar ikke opp systemlyd og har ikke skydeling, transkripsjon, AI-funksjoner eller videoredigering.

## Bygg og verifiser

```sh
./scripts/build.sh
./scripts/verify.sh
```

Bygget ligger i `dist/Lewtech Record.app`. Kjør kodekverifikasjonen fra vanlig Terminal, uten en agents begrensede prosess-sandbox: macOS sine videokodektjenester må kunne nås. Verifikasjonen tester tidslinje/pause, bibliotek/persistens og mediepipeline med syntetiske video- og lyddata. Den rapporterer resultater som JSON og avslutter med feilstatus hvis en kontroll feiler.

Automatiske tester dekker syntetisk mediekoding, tidslinje og bibliotek. Full maskinvaretest med ekte kamera, mikrofon og lange opptak er ikke fullført. Prøv et kort opptak med egne enheter før viktige opptak. Se [utviklerveiledningen](DEVELOPMENT.md) for manuelle kontrollpunkter.

Start maskinvaretesten fra Finder. Direkte oppstart av appens kjørbare fil fra en agentterminal kan føre til at macOS tilskriver kamera-/mikrofonforespørselen terminalens vertsapp i stedet for Lewtech Record.

## Teknisk oversikt

SwiftUI og AppKit bygger grensesnittet. ScreenCaptureKit henter skjerm/vindu, AVFoundation håndterer enheter og videofiler, og Core Image kompositerer kameraet. Filer lagres fortløpende, og biblioteksmetadata skrives atomisk. Ressursene er pakket med appen og lastes ikke fra nettet under bruk.

`Sources/LewtechRecord/Resources/BrandSources.txt` dokumenterer brandkildene. Manrope-fontens lisens følger med i ressursmappen. Appikonet kan gjenskapes med `scripts/generate-icon.swift` og macOS `iconutil`.


### Skjermtilgang står på, men macOS avviser den

Lokale ad-hoc-signerte oppdateringer får en ny kodesignatur. En gammel skjermtillatelse kan derfor stå på i Systeminnstillinger selv om den gjelder et tidligere bygg. Avslutt Lewtech Record og nullstill bare appens skjermtillatelse:

```sh
tccutil reset ScreenCapture no.lewtech.record
```

Åpne den installerte appen fra Finder, gå til Opptaksstudio, og godkjenn skjermtilgang på nytt. Dette sletter ingen opptak. En stabil Apple Development/Developer ID-signatur bør brukes for oppdateringer som skal bevare tillatelser mellom bygg.
