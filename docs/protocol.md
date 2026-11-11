# Protocole Pegasus — v1

> Issue : #4 · Statut : MVP · Implémentation partagée : `packages/pegasus_protocol`

Communication entre l'**app** (mobile Flutter) et l'**agent** (PC, Flutter desktop).

## 1. Transport

| Élément | Valeur |
|---|---|
| Protocole | WebSocket sur TLS (`wss://`) |
| URL | `wss://<hôte>:47800/ws` (port configurable dans l'agent) |
| Encodage | Trames texte, JSON UTF-8 |
| Taille max d'un message | 64 Kio |
| Réseau accepté | Réseau local uniquement : l'agent refuse les adresses sources hors plages privées (RFC 1918, link-local, IPv6 ULA). Accès distant : V3 |

### Certificat
- Au premier lancement, l'agent génère une paire de clés **ECDSA P-256** et un certificat auto-signé (validité 10 ans).
- **Empreinte** = SHA-256 du certificat DER, encodée en base64url sans padding.
- L'app **épingle** cette empreinte à l'appairage et refuse toute connexion dont le certificat ne correspond pas.
- Régénérer le certificat (action manuelle dans l'agent) oblige à réassocier tous les appareils.

## 2. Enveloppe des messages

Tous les messages partagent la même enveloppe.

```jsonc
// Requête (attend une réponse)
{ "v": 1, "type": "req", "id": "42", "op": "power.lock", "data": {} }

// Réponse OK
{ "v": 1, "type": "res", "id": "42", "ok": true, "data": {} }

// Réponse en erreur
{ "v": 1, "type": "res", "id": "42", "ok": false,
  "error": { "code": "forbidden", "message": "Module « power » désactivé sur ce PC" } }

// Commande sans réponse (haute fréquence)
{ "v": 1, "type": "cmd", "op": "input.move", "data": { "dx": 3.5, "dy": -1 } }

// Événement poussé par l'agent
{ "v": 1, "type": "evt", "op": "audio.changed", "data": { "volume": 60, "muted": false } }
```

| Champ | Description |
|---|---|
| `v` | Version majeure du protocole (entier) |
| `type` | `req` · `res` · `cmd` · `evt` |
| `id` | Chaîne unique par connexion, choisie par l'émetteur de la requête (compteur conseillé). Absent pour `cmd` et `evt` |
| `op` | Opération, sous la forme `<module>.<action>` |
| `data` | Objet, `{}` si vide |

Règles de compatibilité :
- Un champ inconnu est **ignoré** (compatibilité ascendante).
- Une `op` inconnue répond `not_supported`.
- Toute requête reçoit une réponse sous **10 s**, sinon l'app la considère en échec (`timeout` côté client).

## 3. Appairage

### Contenu du QR code
```
pegasus://pair?v=1&h=192.168.1.20&p=47800&id=<agentId>&n=<nomDuPC>&fp=<empreinte>&t=<jeton>
```
| Paramètre | Description |
|---|---|
| `h`, `p` | Adresse IP locale et port de l'agent |
| `id` | Identifiant stable de l'agent (UUID) |
| `n` | Nom du PC (URL-encodé) |
| `fp` | Empreinte du certificat |
| `t` | Jeton d'appairage : 16 octets aléatoires, base64url, **usage unique, 5 min** |

### Code manuel (secours)
- 6 chiffres, usage unique, 5 min. 5 essais ratés → code invalidé.
- Sans QR code, l'app ne connaît pas l'empreinte à l'avance : elle affiche les 8 premiers caractères de l'empreinte reçue, que l'utilisateur compare à ceux affichés par l'agent avant de valider.

### Échange
La connexion TLS est ouverte sans authentification, puis :

```jsonc
// app → agent
{ "v": 1, "type": "req", "id": "1", "op": "pair.request", "data": {
    "token": "<jeton du QR>",            // ou "code": "482193"
    "device": { "id": "<uuid app>", "name": "Téléphone 1", "platform": "android", "model": "…" }
} }

// agent → app
{ "v": 1, "type": "res", "id": "1", "ok": true, "data": {
    "agentId": "<uuid>", "agentName": "PC-Bureau",
    "deviceSecret": "<32 octets aléatoires, base64url>"
} }
```

- L'app stocke `deviceSecret` dans le stockage sécurisé (Keychain iOS / Keystore Android), avec `agentId`, l'adresse et l'empreinte.
- L'agent stocke le secret chiffré (DPAPI sous Windows) et ajoute l'appareil à la liste des appareils autorisés.
- La connexion continue ensuite directement avec l'authentification (§4).

## 4. Authentification (chaque connexion)

```jsonc
// 1. app → agent
{ "v": 1, "type": "req", "id": "1", "op": "session.hello", "data": {
    "deviceId": "<uuid app>", "app": { "version": "0.1.0" },
    "protocol": { "min": 1, "max": 1 }
} }
// agent → app
{ "v": 1, "type": "res", "id": "1", "ok": true, "data": {
    "nonce": "<32 octets aléatoires, base64url>", "protocol": 1
} }

// 2. app → agent
{ "v": 1, "type": "req", "id": "2", "op": "session.auth", "data": {
    "mac": "<base64url(HMAC-SHA256(deviceSecret, nonce ‖ agentId ‖ deviceId))>"
} }
// agent → app
{ "v": 1, "type": "res", "id": "2", "ok": true, "data": {
    "agent": { "id": "<uuid>", "name": "PC-Bureau", "version": "0.1.0", "os": "windows" },
    "modules": { "input": true, "media": true, "power": true, "apps": true },
    "paused": false
} }
```

- Le secret ne transite jamais après l'appairage ; chaque nonce n'est valable qu'une fois.
- Le handshake doit être terminé en **10 s**, sinon fermeture `4408`.
- Avant `session.auth` réussi, seules `pair.request`, `session.hello` et `session.auth` sont acceptées.
- Un même appareil connecté deux fois : l'ancienne connexion est fermée avec `4409`.

## 5. Connexion maintenue

| Règle | Valeur |
|---|---|
| Ping | Trames WebSocket `ping` toutes les **15 s** (des deux côtés) |
| Déconnexion | Aucune trame reçue pendant **45 s** |
| Reconnexion (app) | Délai exponentiel 1 s → 2 → 4 → 8 → 16 → **30 s max**, ±20 % d'aléa ; immédiate au retour de l'app au premier plan |

### Codes de fermeture
| Code | Signification |
|---|---|
| `4400` | Handshake invalide |
| `4401` | Authentification refusée |
| `4403` | Appareil révoqué → l'app supprime le secret et propose de réassocier |
| `4408` | Handshake trop long |
| `4409` | Remplacée par une nouvelle connexion du même appareil |
| `4426` | Version de protocole non supportée |

## 6. Codes d'erreur

| Code | Cas |
|---|---|
| `bad_request` | Données manquantes ou invalides |
| `unauthorized` | Session non authentifiée |
| `forbidden` | Module désactivé dans les autorisations de l'agent |
| `paused` | Agent en pause : seules les `session.*` et `agent.*` répondent |
| `rejected` | Action refusée sur le PC (confirmation refusée ou expirée) |
| `not_supported` | Opération inconnue ou non disponible sur cet OS |
| `rate_limited` | Trop de messages |
| `internal` | Erreur côté agent |

## 7. Modules et permissions

Le préfixe de `op` désigne le module. Il correspond à un interrupteur de la section **Autorisations** de l'agent. Module désactivé → `forbidden`.

| Préfixe(s) | Module |
|---|---|
| `input.*` | `input` (souris & clavier) |
| `media.*`, `audio.*` | `media` |
| `power.*` | `power` |
| `apps.*`, `url.*` | `apps` |
| `session.*`, `pair.*`, `agent.*` | toujours autorisés |

Événements de session poussés par l'agent :
- `session.paused` `{ "paused": true }`
- `session.modules` `{ "modules": { … } }` — l'app grise immédiatement les modules désactivés.

## 8. Opérations du MVP

### Agent
| Op | Type | Données | Réponse |
|---|---|---|---|
| `agent.info` | req | — | `{ id, name, version, os, paused, modules }` |

### Souris & clavier (`input`)
| Op | Type | Données |
|---|---|---|
| `input.move` | cmd | `{ dx, dy }` en pixels (sensibilité appliquée côté app), envoyé par lots jusqu'à ~60/s |
| `input.scroll` | cmd | `{ dx, dy }` en crans (décimaux acceptés) |
| `input.button` | cmd | `{ button: "left"\|"right"\|"middle", state: "down"\|"up" }` (glisser-déposer) |
| `input.click` | req | `{ button: "left"\|"right"\|"middle", count: 1\|2 }` |
| `input.text` | req | `{ text }` — 1000 caractères max, Unicode complet |
| `input.key` | req | `{ key, modifiers: ["ctrl","alt","shift","win"] }` |

Valeurs de `key` : `escape`, `tab`, `enter`, `backspace`, `delete`, `space`, `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`, `f1`…`f12`, `printscreen`, une lettre ou un chiffre (`a`…`z`, `0`…`9`). Exemples : Alt+Tab = `{ "key": "tab", "modifiers": ["alt"] }`, Win seul = `{ "key": "win", "modifiers": [] }`.

### Médias (`media`)
| Op | Type | Données | Réponse |
|---|---|---|---|
| `media.play_pause` | req | — | — |
| `media.next` | req | — | — |
| `media.previous` | req | — | — |
| `audio.get` | req | — | `{ volume: 0-100, muted }` |
| `audio.set` | req | `{ volume?: 0-100, muted?: bool }` | `{ volume, muted }` |
| `audio.changed` | evt | `{ volume, muted }` | — (envoyé aussi quand le volume change sur le PC) |

### Alimentation (`power`)
| Op | Type | Données |
|---|---|---|
| `power.lock` | req | — |
| `power.sleep` | req | — |
| `power.logoff` | req | `{ confirmed: true }` |
| `power.restart` | req | `{ confirmed: true }` |
| `power.shutdown` | req | `{ confirmed: true }` |

- `confirmed: true` est obligatoire pour les actions destructrices (l'app affiche la confirmation) ; sans lui → `bad_request`.
- Si le réglage « Demander confirmation sur le PC » est actif, l'agent affiche une boîte de dialogue (15 s) et répond après décision ; refus ou délai → `rejected`.
- L'agent répond **avant** d'exécuter l'action (la connexion sera coupée ensuite).

### Applications (`apps`)
| Op | Type | Données | Réponse |
|---|---|---|---|
| `apps.list` | req | — | `{ apps: [{ id, name, icon }] }` — `icon` : PNG 64×64 en base64 |
| `apps.launch` | req | `{ id }` | — |
| `url.open` | req | `{ url }` | — |

- `apps.launch` n'accepte que les identifiants de la liste des favoris configurée dans l'agent (jamais un chemin arbitraire).
- `url.open` n'accepte que `http://` et `https://`, 2048 caractères max.

## 9. Limites et sécurité

| Règle | Valeur |
|---|---|
| Débit de `cmd` | 200 / s par connexion, au-delà ignorées |
| Débit de `req` | 20 / s par connexion, au-delà `rate_limited` |
| Tentatives d'appairage | 5 échecs → jeton/code invalidé, nouvel essai après régénération |
| Connexions simultanées | 5 appareils max |
| Journal | Chaque `req` exécutée est inscrite dans le journal de l'agent (heure, appareil, module, action) ; les `cmd` d'input ne le sont pas |

## 10. Versionnage

- `v` = version **majeure** ; elle ne change que pour une rupture de compatibilité.
- Ajouts compatibles (nouvelle `op`, nouveau champ optionnel) : pas de changement de `v`. L'app découvre les modules disponibles via `modules` dans `session.auth`.
- Négociation : l'app envoie `protocol: { min, max }`, l'agent choisit la plus haute version commune ou ferme avec `4426`.
