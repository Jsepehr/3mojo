# Raen: bozza di informativa privacy (IT / EN)

> **Bozza tecnica, non consulenza legale.** Testo da rivedere con un consulente prima della pubblicazione. I campi **[tra parentesi quadre]** li compila il titolare (gli stessi segnaposto `TODO(privacy)` di `lib/core/config/privacy_policy_info.dart`). Ogni affermazione corrisponde al codice attuale (commit `4f7cae1` più le modifiche della [DPIA](dpia.md) 0.2): se il codice cambia, va aggiornata (vedi [dpia.md](dpia.md) §9). Acquisti e verifica del dispositivo sono scritti in forma condizionale ("Se acquisti…", "Quando è attiva…"), come nell'app: il testo resta vero con o senza pagamenti reali e attestazione accesi.
>
> **Nell'app c'è già** (`UiPrivacyPolicy`, dal menu, da "Informazioni", dal profilo e dai termini d'uso): i testi sono gli ARB `privacy_*` (`lib/l10n/app_*.arb`), che fanno da fonte; questa bozza va tenuta allineata a loro. Versione e data come in `PrivacyPolicyInfo` (`version`, `lastUpdated`). **Manca l'indirizzo web pubblico** (richiesto da App Store Connect e da Play Console): oggi `PrivacyPolicyInfo.publicUrl` è il segnaposto `https://raen.example/privacy` (vedi la checklist).

---

## Versione italiana

**Versione 1 · ultimo aggiornamento 23 ottobre 2026** **[data definitiva di pubblicazione: da aggiornare anche in `PrivacyPolicyInfo`]**

La trovi anche su **[URL pubblico]**.

### Chi siamo
Il titolare del trattamento è **[ragione sociale, sede, P.IVA]**. Per la privacy scrivi a **[privacy@…]**. Per la sicurezza e le segnalazioni scrivi a **[safety@…]**. **[Se nominato: il nostro Responsabile della protezione dei dati è raggiungibile a …]**

### In breve
- Raen **non ha account**: niente nome, email, numero di telefono né password.
- Sei visibile solo **mentre sei online**, tra **Start** e **Termina**.
- Il nostro server tiene i dati della sessione **solo in memoria** e li dimentica alla fine della sessione. L'unica eccezione sono i **record di moderazione** (vedi sotto), conservati al massimo 30 giorni.
- Non vendiamo dati, non facciamo pubblicità e non usiamo strumenti di analisi o di tracciamento.

### Cosa raccogliamo e perché

| Cosa | Perché | Chi lo vede |
|---|---|---|
| **Posizione precisa**, mentre sei online | Mostrarti chi è entro 100 metri (o nello stesso posto affollato) e mostrare te a loro | **Nessuno**: gli altri non ricevono mai la tua posizione né la distanza da te. Sanno solo che sei abbastanza vicino da comparire. Su Android resti visibile **anche con l'app in background**, finché premi Termina (lo indica una notifica fissa). Su iPhone la posizione si usa **solo mentre Raen è aperta sullo schermo** |
| **Selfie** della sessione | Farti riconoscere di persona | Le persone vicine compatibili, chi riceve o manda una tua richiesta, il tuo match. Togliamo dalla foto i metadati (per esempio il luogo dello scatto) |
| **Genere e chi vuoi incontrare** | Mostrarti solo persone compatibili, e mostrarti solo a loro (in entrambe le direzioni) | **Chi vuoi incontrare: nessuno.** Il genere solo se attivi "Mostra il mio genere agli altri". **Attenzione**: chi ti vede può intuire che rientra in ciò che cerchi |
| Intento, lingue (al massimo 2) | Far sapere cosa cerchi stasera e che lingua parli | Le persone vicine compatibili, le richieste, il match |
| Da quanto sei fermo, in tre livelli (basso, medio, alto) | Indicare la probabilità d'incontro | Le persone vicine compatibili |
| Richieste d'incontro, risposte | Proporre e accettare un incontro | L'altra persona (un "no" è visibile a chi ha chiesto) |
| **Messaggi della chat** | Parlare con il tuo match | Solo il tuo match. Il server li inoltra e **non li conserva**. Sul telefono spariscono quando finisce il match |
| Blocchi e segnalazioni | La sicurezza di tutti | Nessuno. Chi blocchi o segnali non viene avvisato |
| Indirizzo IP | Limitare gli abusi (per esempio troppe sessioni dalla stessa rete) | Nessuno |
| Se acquisti lo sblocco di 2 ore | Verificare il pagamento con App Store o Google Play e attivare lo sblocco | Nessuno. Il pagamento lo gestisce Apple o Google: **noi non vediamo nome, carta né account** |
| Verifica del dispositivo | Quando è attiva, accettare solo l'app originale su un dispositivo reale, contro gli account falsi automatici | Apple (App Attest) o Google (Play Integrity) danno un esito; **non conserviamo nulla** |

Il **controllo del volto** sul selfie avviene **solo sul telefono**: nessun dato biometrico viene creato, salvato o inviato. Su Android e iPhone lo fa il sistema operativo del telefono, senza rete.

Il **profilo** (genere, chi cerchi, intento, lingue, conferma dei 18 anni) **resta sul telefono, cifrato**. Lo mandiamo al server solo mentre sei online.

### Su che basi
- **Contratto** (art. 6(1)(b) GDPR): posizione, selfie, profilo, richieste, chat e acquisti servono a darti il servizio che chiedi premendo Start.
- **Consenso esplicito** (art. 9(2)(a)): per genere e chi vuoi incontrare, che possono rivelare l'orientamento sessuale. Lo dai nel profilo. Non serve se scegli "Preferisco non dirlo" e "Tutti". Puoi ritirarlo in qualsiasi momento (vedi "I tuoi diritti").
- **Interesse legittimo** (art. 6(1)(f)): blocchi, segnalazioni, record di moderazione, limiti per IP e verifica del dispositivo, per proteggere chi usa Raen. Puoi opporti scrivendoci.

### Per quanto tempo
- **Sul nostro server**: per la durata della sessione. Premendo Termina si cancella subito. Se perdi la connessione, la sessione resta nascosta per 45 secondi in attesa che ti riconnetti, poi viene cancellata. Senza segnali dal telefono per 90 secondi viene chiusa.
- **Record di moderazione**: al massimo **30 giorni** (vedi sotto).
- **Acquisti**: il codice di sblocco vale 2 ore. Per evitare che lo stesso pagamento valga due volte teniamo per **8 giorni** solo un'impronta crittografica (non leggibile) della transazione.
- **Indirizzo IP**: da 1 a 30 minuti, secondo il limite. **[Log tecnici del fornitore di hosting: … giorni.]**
- **Sul tuo telefono**: il profilo cifrato finché non lo cancelli o disinstalli l'app. Selfie, chat e foto degli altri solo in memoria, fino a Termina.

### Segnalazioni e record di moderazione
Se più persone diverse segnalano la stessa sessione, questa può essere chiusa automaticamente e per un breve periodo (30 minuti) non si potranno avviare nuove sessioni dalla stessa rete. Questo vale anche per altre persone collegate alla stessa rete, per esempio il Wi-Fi di un locale. Per ogni sessione segnalata conserviamo, **cifrato**, un record per la revisione umana: **la foto della persona segnalata, i motivi, il numero di segnalazioni e l'ora** (arrotondata al minuto). **Mai** posizione, chat, IP né identificativi. Il record viene cancellato dopo 30 giorni o prima, a revisione conclusa. Puoi contestare una decisione o chiedere la cancellazione di un record scrivendo a **[safety@…]**.

### Con chi condividiamo i dati
- **Altri utenti**: solo quanto indicato sopra.
- **[Fornitore di hosting, Paese UE]**, che gestisce i server per nostro conto (responsabile del trattamento).
- **Apple e Google**, per la distribuzione dell'app, i pagamenti e la verifica del dispositivo. **[Da verificare: su Android la libreria di pagamento di Google (Play Billing Library) potrebbe inviare a Google dati tecnici di diagnostica sul proprio funzionamento. Se confermato, dirlo qui (vedi [store_privacy.md](store_privacy.md) §B e la DPIA §6.7).]** Possono trattare dati negli Stati Uniti, con le garanzie previste dai loro termini (**[Data Privacy Framework UE-USA / clausole contrattuali tipo: da verificare]**).
- **Autorità**, solo se la legge lo impone.

### I tuoi diritti, e come si esercitano senza un account
Hai diritto di accesso, rettifica, cancellazione, limitazione, opposizione e portabilità, e puoi ritirare il consenso. Poiché Raen non ha account e non ti identifica, la maggior parte di questi diritti **la eserciti da solo, subito, dall'app**:
- **Vedere o correggere il profilo**: Menu → Il mio profilo.
- **Cancellare i dati dal server**: premi **Termina**. La sessione e tutto ciò che il server sapeva di te spariscono subito.
- **Ritirare il consenso**: Menu → Il mio profilo, poi scegli "Preferisco non dirlo" e "Tutti", oppure Cancella profilo. Se sei online chiudiamo prima la sessione, così il server smette subito di usare genere e preferenze. Lo stesso succede se da online cambi genere, chi vuoi incontrare o "Mostra il mio genere agli altri". Lingue e cosa cerchi di solito valgono dal prossimo Start.
- **Cancellare tutto dal telefono**: disinstalla l'app.

Non possiamo darti una copia dei dati di una sessione già chiusa, perché non li abbiamo più. Per i **record di moderazione** non abbiamo modo di sapere che riguardano te: scrivici a **[safety@…]** indicando giorno e ora approssimativi. Potremmo chiederti elementi per riconoscere il record (per esempio una foto da confrontare), che useremo solo per questo e poi cancelleremo.

Puoi anche presentare reclamo al **Garante per la protezione dei dati personali** (www.garanteprivacy.it) o all'autorità del tuo Paese.

### Età
Raen è solo per persone **maggiorenni (18+)**. Se pensi che qualcuno abbia meno di 18 anni, segnalalo con il motivo "Sembra minorenne".

### Sicurezza
Connessioni cifrate (TLS), profilo cifrato sul telefono, record di moderazione cifrati sul server. Su Android l'app blocca screenshot e registrazioni dello schermo; su iPhone nasconde il contenuto nel selettore delle app. Su iPhone gli altri potrebbero comunque fare uno screenshot: condividi solo ciò che sei disposto a far vedere.

### Modifiche
Se cambiamo questa informativa in modo sostanziale te lo diremo nell'app.

---

## English version

**Version 1 · last updated October 23, 2026** **[final publication date: also update it in `PrivacyPolicyInfo`]**

You can also read it at **[public URL]**.

### Who we are
The data controller is **[company name, address, VAT number]**. For privacy matters write to **[privacy@…]**. For safety and reports write to **[safety@…]**. **[If appointed: our Data Protection Officer can be reached at …]**

### In short
- Raen **has no accounts**: no name, email, phone number or password.
- You are visible only **while you are online**, between **Start** and **End**.
- Our server keeps session data **in memory only** and forgets it when the session ends. The only exception is **moderation records** (see below), kept for at most 30 days.
- We don't sell data, show ads or use analytics or tracking tools.

### What we collect and why

| What | Why | Who sees it |
|---|---|---|
| **Precise location**, while you are online | To show you people within 100 metres (or in the same busy place) and to show you to them | **No one**: other people never receive your location or how far you are. They only know you are close enough to appear. On Android you stay visible **even with the app in the background**, until you tap End (a persistent notification shows this). On iPhone your location is **only used while Raen is open on screen** |
| Session **selfie** | So people can recognise you in person | Compatible people nearby, people you send a request to or receive one from, your match. We remove the photo's metadata (such as where it was taken) |
| **Gender and who you want to meet** | To show you only compatible people, and to show you only to them (both ways) | **Who you want to meet: no one.** Your gender only if you turn on "Show my gender to others". **Note**: people who can see you may guess that they fit what you're looking for |
| Intent, languages (up to 2) | To say what you're up for tonight and which languages you speak | Compatible people nearby, requests, your match |
| How long you've stayed put, in three levels (low, medium, high) | To show how likely a meeting is | Compatible people nearby |
| Meeting requests and replies | To propose and accept a meeting | The other person (a "no" is visible to whoever asked) |
| **Chat messages** | To talk to your match | Only your match. The server relays them and **does not keep them**. On your phone they disappear when the match ends |
| Blocks and reports | Everyone's safety | No one. People you block or report are not told |
| IP address | To limit abuse (for example too many sessions from the same network) | No one |
| If you buy the 2-hour unlock | To verify the payment with the App Store or Google Play and activate the unlock | No one. Apple or Google handles the payment: **we never see your name, card or account** |
| Device check | When it's turned on, to accept only the genuine app on a real device, against fake automated accounts | Apple (App Attest) or Google (Play Integrity) give a verdict; **we keep nothing** |

The **face check** on your selfie happens **only on your phone**: no biometric data is created, saved or sent. On Android and iPhone it is done by your phone's operating system, with no network.

Your **profile** (gender, who you want to meet, intent, languages, 18+ confirmation) **stays on your phone, encrypted**. We only send it to the server while you are online.

### Legal bases
- **Contract** (Art. 6(1)(b) GDPR): location, selfie, profile, requests, chat and purchases are needed to provide the service you ask for when you tap Start.
- **Explicit consent** (Art. 9(2)(a)): for gender and who you want to meet, which may reveal your sexual orientation. You give it in your profile. It isn't needed if you choose "Prefer not to say" and "Everyone". You can withdraw it at any time (see "Your rights").
- **Legitimate interests** (Art. 6(1)(f)): blocks, reports, moderation records, IP limits and the device check, to protect people using Raen. You can object by writing to us.

### How long we keep it
- **On our server**: for the length of the session. Tapping End deletes it immediately. If you lose your connection, the session stays hidden for 45 seconds in case you reconnect, then it is deleted. After 90 seconds with no signal from your phone it is closed.
- **Moderation records**: at most **30 days** (see below).
- **Purchases**: the unlock code lasts 2 hours. To stop the same payment from counting twice we keep only a cryptographic fingerprint (unreadable) of the transaction for **8 days**.
- **IP address**: 1 to 30 minutes, depending on the limit. **[Hosting provider's technical logs: … days.]**
- **On your phone**: the encrypted profile until you delete it or uninstall the app. Selfie, chats and other people's photos in memory only, until End.

### Reports and moderation records
If several different people report the same session, it may be closed automatically, and for a short time (30 minutes) no new sessions can be started from the same network. This also affects other people on the same network, for example a venue's Wi‑Fi. For each reported session we keep an **encrypted** record for human review: **the reported person's photo, the reasons, the number of reports and the time** (rounded to the minute). **Never** location, chats, IP or identifiers. The record is deleted after 30 days, or earlier once reviewed. You can appeal a decision or ask us to delete a record by writing to **[safety@…]**.

### Who we share data with
- **Other users**: only what is described above.
- **[Hosting provider, EU country]**, which runs our servers on our behalf (processor).
- **Apple and Google**, for app distribution, payments and the device check. **[To be verified: on Android, Google's payment library (Play Billing Library) may send Google technical diagnostics about its own operation. If confirmed, say so here (see [store_privacy.md](store_privacy.md) §B and DPIA §6.7).]** They may process data in the United States, with the safeguards set out in their terms (**[EU-US Data Privacy Framework / standard contractual clauses: to be verified]**).
- **Authorities**, only where the law requires it.

### Your rights, and how to use them without an account
You have the right of access, rectification, erasure, restriction, objection and portability, and you can withdraw consent. Because Raen has no accounts and doesn't identify you, you exercise most of these rights **yourself, immediately, in the app**:
- **See or correct your profile**: Menu → My profile.
- **Delete your data from the server**: tap **End**. Your session and everything the server knew about you are gone immediately.
- **Withdraw consent**: Menu → My profile, then choose "Prefer not to say" and "Everyone", or Delete profile. If you're online we end your session first, so the server stops using your gender and preferences right away. The same happens if you change your gender, who you want to meet or "Show my gender to others" while online. Languages and what you're usually looking for apply from your next Start.
- **Delete everything from your phone**: uninstall the app.

We can't give you a copy of the data from a session that has ended, because we no longer have it. For **moderation records** we have no way of knowing they're about you: write to **[safety@…]** with the approximate date and time. We may ask for details to find the record (for example a photo to compare), which we'll use only for that and then delete.

You can also lodge a complaint with a supervisory authority, such as the Italian **Garante per la protezione dei dati personali** (www.garanteprivacy.it) or the authority in your country.

### Age
Raen is only for **adults (18+)**. If you think someone is under 18, report them with the reason "Seems to be under 18".

### Security
Encrypted connections (TLS), encrypted profile on your phone, encrypted moderation records on the server. On Android the app blocks screenshots and screen recording; on iPhone it hides its content in the app switcher. On iPhone other people could still take a screenshot: only share what you're comfortable showing.

### Changes
If we change this policy in a significant way, we'll tell you in the app.
