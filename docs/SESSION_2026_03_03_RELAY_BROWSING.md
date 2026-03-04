# Session 2026-03-03 - Relay Browsing & E2EE Fixes

## Statut : EN COURS

---

## 1. Correctifs appliques (valides)

### 1a. Connexion bidirectionnelle via lien d'invitation (RESOLU)

**Probleme** : Quand l'iPhone (5G) scannait le lien d'invitation du Mac (WiFi),
la connexion etait unidirectionnelle - l'iPhone avait le Mac comme contact,
mais le Mac n'avait pas l'iPhone.

**Cause** : `relay_poller.rs:poll_once()` exigeait `crypto_service` pour traiter
TOUS les messages, y compris les `connection_request` bruts (non chiffres) qui
n'ont pas besoin de crypto (probleme du bootstrap - on ne peut pas chiffrer pour
quelqu'un qu'on ne connait pas encore).

**Correctif** (4 fichiers) :
- `relay_transport.rs` : `crypto_service` rendu `Option<Arc<...>>`
- `relay_poller.rs` : `poll_once()` restructure - traite les messages bruts sans crypto,
  les messages chiffres seulement si crypto disponible (sinon laisse en mailbox pour le
  prochain cycle)
- `api/relay.rs` : appel `RelayTransport::new(Some(crypto_service))`
- `api/peer.rs` : idem

**Tests** : `cargo clippy` clean, `cargo test` 128 tests OK, confirme par l'utilisateur.

### 1b. Garde-fou hub `is_listed` apres reinstallation macOS (APPLIQUE)

**Probleme** : Apres desinstallation complete sur macOS, `~/Library/Application Support/`
persiste. La DB SQLite conserve `hub_directory_config.is_listed = 1`, ce qui
publie la bibliotheque en ligne sans le consentement de l'utilisateur apres reinstall.

**Correctif** : Dans `frb.rs:start_server()`, avant la creation d'AppState :
si aucun utilisateur n'existe dans la table `users`, forcer `is_listed = 0`.

### 1c. Options de cache par defaut (APPLIQUE)

**Probleme** : `peerOfflineCachingEnabled` et `allowLibraryCaching` etaient `false`
par defaut. Apres reset, les 2 options sont desactivees.

**Correctif** : `theme_provider.dart` - default change a `true` (champ d'instance + fallback SharedPreferences).

---

## 2. Correctifs relay browsing (session continuee)

### Fix 2a : Initialisation E2EE pour relay-only (RESOLU)

**Probleme** : `initIdentityFfi()` etait appele uniquement sous `networkDiscoveryEnabled`
(WiFi discovery). Un appareil avec seulement "Joignable a distance" actif n'initialisait
pas son identite E2EE, causant `has_crypto: false`.

**Correctif** : `main.dart` - condition changee en `networkDiscoveryEnabled || remoteReachableEnabled`.
L'init E2EE est extraite avant le bloc mDNS (qui reste gate par networkDiscoveryEnabled seul).

### Fix 2b : Suppression destructive de peer sur 404 LAN (RESOLU)

**Probleme** : LAN sync retourne 404, l'iPhone supprime le peer meme s'il a des credentials
relay valides (`relay_url` + `mailbox_id`).

**Correctif** : `api_service.dart` - dans le catch DioException 404, verifie `relay_url` et
`mailbox_id` avant de supprimer. Si le peer a des credentials relay, on le garde.

### Fix 2c : Regeneration identite apres UUID mismatch (RESOLU)

**Probleme** : Apres reset, SharedPreferences sont videes, un nouveau UUID est genere.
Les anciennes crypto_keys chiffrees avec l'ancien UUID echouent au dechiffrement.
`identity_service.rs:init()` retournait une erreur fatale.

**Correctif** : `identity_service.rs` - detecte `Decryption failed` ou `not 32 bytes`,
supprime les anciennes cles (`DELETE FROM crypto_keys WHERE user_id = 0`), regenere
une nouvelle identite. Tests Rust mis a jour (128 OK).

### Fix 2d : Fallback relay quand LAN echoue (RESOLU)

**Probleme** : Sur 5G, `_getMyUrl()` retourne une IP cellulaire non-null, le code prend
le chemin LAN, le handshake echoue, mais PAS de fallback relay. Le `_depositConnectionRequest`
n'est jamais appele.

**Correctif** : `api_service.dart:connectLocalPeer()` - ajoute relay fallback dans le catch
`DioException`. Si `relayUrl` et `mailboxId` sont disponibles, sauvegarde le peer en relay-only
et depose une connection request. Confirme par les logs iPhone :
`P2P Connect: LAN failed, falling back to relay-only` / `Relay deposit: 201`.

### Fix 2e : Timeouts relay augmentes (RESOLU)

**Probleme** : `try_send_e2ee` timeout (65s) trop proche du cycle relay poller (60s+10s jitter).

**Correctif** :
- `peer.rs` : `overall_timeout` 65s -> 90s
- `api_service.dart` : Dio `receiveTimeout` 80s -> 110s

### Fix 2f : Adaptive polling concurrent flooding (RESOLU)

**Probleme** : `_startAdaptivePolling` dans `peer_book_list_screen.dart` utilise
`Timer.periodic(5s)`. Chaque tick lance un `requestPeerManifest` asynchrone qui bloque
en Rust jusqu'a 90s. Comme Timer.periodic n'attend pas la completion du callback,
~18 requetes concurrentes sont creees, chacune avec un correlation_id different.
Les reponses du peer distant matchent les ANCIENS IDs, pas les derniers.

**Correctif** : Ajout d'un guard `_pollRequestInFlight`. Si une requete precedente est
encore en cours, le tick est ignore. Cela garantit une seule requete relay active a la
fois, avec un correlation_id stable.

### Browsing : etat actuel

- Mac -> iPhone : FONCTIONNE (confirme par l'utilisateur)
- iPhone -> Mac via relay : tous les correctifs sont en place, a tester apres rebuild

---

## 3. Autres anomalies observees dans les logs

### TabBar controller mismatch (Mac)

```
Controller's length property (2) does not match the number of tabs (3) present
in TabBar's tabs property.
```

Probablement lie a un ecran qui affiche 3 onglets mais dont le controller
n'en gere que 2. A investiguer separement (cosmetic, non bloquant).

### "Error syncing enabled modules" 404 (Mac)

Le Mac tente de synchroniser les modules actives via HTTP mais recoit 404.
Probablement parce que le setup n'est pas complete (pas d'utilisateur).

### "error in connection_block_invoke_2: Connection invalid" (iPhone)

Erreur systeme iOS (probablement liee au changement de reseau WiFi/5G).
Non actionnable.

---

## 4. Etat du code (fichiers modifies dans cette session)

| Fichier | Changement | Teste |
|---------|-----------|-------|
| `bibliogenius/src/services/relay_transport.rs` | crypto_service Optional | cargo clippy + test OK |
| `bibliogenius/src/services/relay_poller.rs` | poll_once restructure | cargo clippy + test OK |
| `bibliogenius/src/api/relay.rs` | Some() wrapper | cargo clippy + test OK |
| `bibliogenius/src/api/peer.rs` | Some() wrapper + timeout 65s->90s | cargo clippy + test OK |
| `bibliogenius/src/api/frb.rs` | Hub config cleanup on startup | cargo clippy + test OK |
| `bibliogenius/src/services/identity_service.rs` | Regeneration apres UUID mismatch | cargo test OK (128) |
| `bibliogenius-app/lib/main.dart` | E2EE init pour relay-only | flutter analyze OK |
| `bibliogenius-app/lib/services/api_service.dart` | Guard peer deletion + relay fallback + timeout 110s | flutter analyze OK |
| `bibliogenius-app/lib/providers/theme_provider.dart` | Cache defaults true | flutter analyze OK |
| `bibliogenius-app/lib/screens/peer_book_list_screen.dart` | Guard polling concurrent | flutter analyze OK |

### Changements d'une session precedente (deja en place)

| Fichier | Changement |
|---------|-----------|
| `bibliogenius/src/api/view_counter.rs` | Nouveau - middleware compteur de vues |
| `bibliogenius/src/api/mod.rs` | Layer middleware + route /api/stats/views |
| `bibliogenius/src/infrastructure/db.rs` | Migration library_view_stats |
| `bibliogenius/src/infrastructure/server.rs` | into_make_service_with_connect_info |

---

## 5. Feature "Compteur de vues" (view counter) - etat

Rust : implemente (middleware, migration, endpoint `/api/stats/views`).
FFI : fonction `get_library_view_stats()` ajoutee dans `frb.rs`.
**Flutter** : bindings FFI non regeneres (`flutter_rust_bridge_codegen generate` non execute).
Le profil ne peut pas encore afficher le compteur.

**Prochaine etape** : regenerer les bindings FFI, ajouter le widget dans profile_screen.dart,
ajouter les traductions i18n.

---

## 6. Contexte technique (pour reference)

### Flux relay browsing (ADR-012)

```
iPhone                          Relay Hub                      Mac
  |                                |                            |
  |-- POST relay/library_request ->|                            |
  |   (try_send_e2ee 65s wait)     |                            |
  |                                |                            |
  |-- E2EE encrypted request ----->|-- mailbox deposit -------->|
  |                                |                            |
  |   (poll_once every 5s)         |                  poll_once |
  |                                |                            |
  |                                |<-- E2EE response ---------|
  |<-- poll_once picks up ---------|                            |
  |                                |                            |
  |   correlation_id matched       |                            |
  |   -> return 200 with data      |                            |
```

### Timeouts (mis a jour)

- `try_send_e2ee` overall : 90s (etait 65s)
- `try_send_e2ee` poll interval : 5s
- Mac relay poller : 60s + 0-10s jitter
- Dio receiveTimeout (Flutter) : 110s (etait 80s)
- Adaptive polling (Flutter) : 5s x 36 = 3 min (avec guard anti-flooding)
