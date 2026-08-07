# Prima di creare un file — la checklist

Versione estesa di [CLAUDE.md](CLAUDE.md): non solo la regola, ma la domanda che te la fa venire in mente. Da scorrere **in ordine** ogni volta che stai per aggiungere un file (o un campo, o una riga di logica) e non sei sicuro di dove vada.

## 0. La domanda prima di tutte

> **Cosa sto descrivendo?**
> - Un'azione che l'app sa fare → **use case** (`domain/usecases`)
> - Un concetto/oggetto del problema → **entity** (`domain/entities`)
> - Una promessa su come si ottengono/salvano dei dati, senza dire come → **repository interface** (`domain/repositories`)
> - Il modo vero, concreto, per ottenere quei dati (rete, disco, memoria) → **datasource** (`data/datasources`)
> - Come quei dati arrivano/partono in JSON → **model** (`data/models`)
> - Chi mantiene la promessa del repository, orchestrando i datasource → **repository impl** (`data/repositories`)
> - Qualcosa che l'utente vede, tocca, o lo stato che serve per mostrarlo → **presentation** (`pages`/`widgets`/`providers`)

Se non sai rispondere a questa, fermati prima di scegliere la cartella — il resto della checklist assume che tu sappia già che "tipo" di file stai scrivendo.

## 1. Sto scrivendo un'interfaccia (`abstract class`)? Dove vive?

- [ ] **È un repository** (il contratto che uno use case chiamerà)? → **sempre** `domain/repositories/`, mai altrove.
  - *Perché*: lo use case che la chiama vive in `domain/`. Se l'interfaccia fosse in `data/`, il domain dovrebbe importare da data — rotto il senso stesso dell'architettura.
- [ ] **È un datasource** (usato solo da un repository impl, mai da uno use case)? → resta in `data/datasources/`, anche se è un'interfaccia.
  - *Perché*: nessuna classe in `domain/` la importa mai. Il test è sempre lo stesso: **"c'è qualcosa dentro `domain/` che deve importare questa interfaccia e chiamarla direttamente?"** Sì → `domain/`. No → resta dove viene usata.

## 2. Sto scrivendo l'implementazione di un'interfaccia?

- [ ] È in un **file separato** da quello dell'interfaccia, con suffisso `_impl.dart`? (mai nello stesso file, nemmeno quando interfaccia e impl stanno nel medesimo layer, come i datasource)
- [ ] Il nome della classe segue `XxxImpl` (es. `CounterRepositoryImpl`, `TodoLocalDataSourceImpl`)?

## 3. Sto aggiungendo/modificando un campo o una proprietà?

- [ ] **Uno use case, o una futura regola di business, deve leggere questo valore per decidere qualcosa?**
  - Sì → va sull'**entity** (`domain/entities`) e sul **model** (`data/models`, per portarlo dal JSON).
  - No, serve solo a essere mostrato, o è un dettaglio tecnico lato server (es. un `_etag` di sincronizzazione) → resta **solo sul model**; l'entity non lo vede mai.
- [ ] Attenzione al falso segnale: **"si vede in UI" non è il test giusto.** Un valore già presente sull'entity può essere solo *riformattato* dentro un widget (es. "creato 2 minuti fa" da un `createdAt` che esiste già) senza toccare né entity né model.

## 4. Sto scrivendo una regola di validazione o di business logic?

- [ ] Va nello **use case** corrispondente — non nel provider (gestisce solo stato UI), non nel repository (gestisce solo accesso ai dati), non nel widget.
- [ ] Se la regola serve a più use case, valuta se estrarla in un metodo condiviso dentro `domain/`, ma non farla "salire" verso presentation né "scendere" verso data.

## 5. Sto gestendo un errore?

- [ ] Sto scrivendo codice in `data/` (datasource o repository impl) che può fallire per motivi tecnici (rete, cache vuota, parsing)? → lancia/cattura un'**`Exception`** tua (`core/errors/exceptions.dart`), non una `Failure`.
- [ ] Sto scrivendo il **repository impl**? → cattura le `Exception`, traducile in **`Failure`** (`core/errors/failures.dart`), ritorna `Either<Failure, T>`.
- [ ] Sto scrivendo qualcosa in `domain/` o `presentation/`? → non toccare mai un try/catch su un'eccezione tecnica: lì esiste solo `Either<Failure, T>`.

## 6. Sto scrivendo testo visibile all'utente?

- [ ] È hardcoded in un widget? → **no**: va in `lib/l10n/app_en.arb` (il template, sempre aggiornato per primo) e poi in `app_it.arb` (e nelle altre lingue).
- [ ] Hai rigenerato con `flutter gen-l10n` dopo aver toccato gli ARB?

## 7. Come chiamo il file e la classe?

| Se il file è in... | Nome file | Nome classe |
|---|---|---|
| `presentation/pages` | `ui_*.dart` | `UiXxx` |
| `presentation/widgets` | `cmp_*.dart` | `CmpXxx` |
| `presentation/providers` | `pro_*.dart` | `ProXxx` |
| `domain/repositories` | `*_repository.dart` | `XxxRepository` |
| `data/repositories` | `*_repository_impl.dart` | `XxxRepositoryImpl` |
| `data/datasources` | `*_data_source.dart` / `_impl.dart` | `XxxDataSource` / `Impl` |
| `domain/usecases` | `*_usecase.dart` | `XxxUseCase` |

## 8. Controllo finale — la direzione delle dipendenze

- [ ] Sto per scrivere un `import` che porta qualcosa da `data/` dentro un file in `domain/`? → **fermati**, è il segnale che qualcosa è nel posto sbagliato.
- [ ] Ogni `implements`/`extends` che ho scritto punta verso `domain/`, mai in uscita da esso?
- [ ] Se dovessi sostituire l'implementazione concreta (es. datasource locale → API vera), dovrei toccare `domain/` o `presentation/`? Se la risposta è sì, qualcosa non è isolato come dovrebbe.

## 9. Sto creando una feature intera da zero?

- [ ] Hai copiato la struttura di `lib/features/profile/` o `lib/features/nearby/` e rinominato, invece di creare le cartelle a mano?
- [ ] Hai guardato `lib/features/nearby/` come riferimento per la versione "completa" (datasource remoto+locale, validazione, entity+model separati)?

## 10. Sto usando lo strumento giusto per lo stato?

- [ ] State management: **Provider** (`ChangeNotifier`) — non introdurre Riverpod/Bloc/GetX senza una ragione discussa esplicitamente.
