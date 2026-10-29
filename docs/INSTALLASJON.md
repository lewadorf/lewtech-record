# Kom i gang med Lewtech Record

[Til hovedsiden](../README.md) · [Slik tar du opp](BRUKERVEILEDNING.md#ta-opp-en-video) · [Få hjelp](../SUPPORT.md)

Ta opp skjermen, ansiktet og stemmen din, og lagre videoen på Mac-en. Du trenger ingen konto hos Lewtech.

> **Status akkurat nå:** Vi har publisert en tidlig testversjon. Den er ikke signert med Apple Developer ID eller kontrollert gjennom Apples notarising. En anbefalt nedlasting for brukere uten teknisk erfaring er derfor **ikke klar ennå**. Vent på denne før du følger installasjonstrinnene nedenfor. Vi oppdaterer veiledningen når den er tilgjengelig.

## 1. Sjekk hvilken Mac du har

Klikk på ** → Om denne maskinen** øverst til venstre på skjermen.

| Se etter | Du trenger |
| --- | --- |
| Chip | Apple M1, M2, M3 eller en nyere M-chip |
| macOS | Versjon 15 eller nyere |

Står det **Intel**, passer ikke den tilgjengelige app-pakken til maskinen din. Det finnes foreløpig ingen ferdig nedlasting for Intel, Windows, iPhone eller iPad.

## 2. Last ned fra riktig sted

Gå til [Lewtech Records offisielle nedlastingsside på GitHub](https://github.com/lewadorf/lewtech-record/releases).

Velg en utgave som uttrykkelig er merket **Developer ID signed and Apple notarized**. Ingen slik utgave er publisert ennå. Utgaver merket **Preview** eller **Pre-release** er testversjoner.

Du trenger selve **app-nedlastingen**. Filene **Source code (zip)** og **Source code (tar.gz)** er kode for utviklere. En fil som slutter på `.sha256` er en kontrollsum, ikke et program du skal åpne. Du trenger ikke en GitHub-konto for å laste ned en offentlig utgave.

## 3. Legg appen i Programmer

Når en signert og notarisert utgave er tilgjengelig:

1. Åpne **Nedlastinger** i Finder.
2. Dobbeltklikk på nedlastingen. En ZIP pakkes ut; en DMG åpner et installasjonsvindu.
3. Dra **Lewtech Record.app** til **Programmer** i Finder, eller til Programmer-snarveien i installasjonsvinduet hvis den finnes.
4. Åpne **Programmer**, og dobbeltklikk på **Lewtech Record**.

macOS kan spørre om du vil åpne en app lastet ned fra internett. Det er en vanlig førstegangsmelding. Meldinger om **ukjent utvikler**, at **Apple ikke kan kontrollere appen**, eller at den **er skadet / vil skade maskinen**, er noe annet: Stopp og [be om hjelp](../SUPPORT.md). Ikke slå av sikkerhetsfunksjoner eller lim inn kommandoer i Terminal for å komme videre.

Du skal ikke behøve Xcode, Git, Terminal eller andre utviklerverktøy for å installere brukerversjonen.

## 4. Gi appen tillatelsene den trenger

| Tillatelse | Hvorfor appen spør |
| --- | --- |
| Skjermopptak | For å ta opp valgt skjerm eller vindu |
| Kamera | For å vise deg i videoen når du velger kamera |
| Mikrofon | For å ta opp stemmen din når mikrofonen er slått på |

Godkjenn bare funksjonene du ønsker å bruke. Kontroller at forespørselen gjelder **Lewtech Record**. Tilgangene kan senere endres under **Systeminnstillinger → Personvern og sikkerhet**. Hvis macOS ber deg avslutte og åpne appen igjen etter en endring, gjør det.

## 5. Lag et kort prøveopptak

Velg **Nytt opptak**, kontroller forhåndsvisningen og klikk **Start opptak**. Snakk i noen sekunder, velg **Stopp og lagre**, og spill av videoen. Kontroller både bilde og lyd før du starter et viktig opptak.

Videoene lagres på Mac-en i **Filmer → Lewtech Record**. Appen laster dem ikke automatisk opp til internett. Bruk **Eksporter MP4** når du vil lagre en kopi som kan deles.

## Oppdatere eller fjerne appen

**Oppdatere:** Avslutt Lewtech Record helt, også fra menylinjen. Last ned en ny signert utgave fra samme offisielle side og erstatt appen i Programmer. Opptakene ligger i en egen mappe og skal beholdes. Ta gjerne sikkerhetskopi av viktige videoer først.

**Fjerne:** Avslutt appen og flytt den fra Programmer til papirkurven. Videoene dine blir liggende i Filmer → Lewtech Record. Slett denne mappen bare hvis du også ønsker å fjerne opptakene.

## Noe fungerer ikke?

Se [brukerveiledningen](BRUKERVEILEDNING.md) eller [kontakt oss gjennom GitHub Issues](https://github.com/lewadorf/lewtech-record/issues). Det krever en GitHub-konto å opprette en sak. Oppgi Mac-modell, macOS-versjon og hva som skjedde. Ikke legg ved private opptak eller bilder av sensitivt skjerminnhold.

Mer om Mac-ens sikkerhetsmeldinger: [Apples veiledning](https://support.apple.com/en-us/102445).
