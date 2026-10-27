# Mise en place de la CI (authentification JWT au Dev Hub)

Le job `scratch-org` de [ci.yml](../.github/workflows/ci.yml) se connecte au Dev Hub `portfolio` sans mot de passe,
par le flux OAuth 2.0 JWT Bearer. Ces étapes sont manuelles et se font **une seule fois**.

## 1. Générer une paire clé/certificat (localement, hors du dépôt)

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 730 -nodes \
  -keyout devhub.key -out devhub.crt -subj "/CN=sf-portfolio-ci"
```

`devhub.key` est un secret : ne jamais le committer (`*.key` est dans `.gitignore`).

## 2. Créer l'application connectée dans le Dev Hub

Setup → **External Client App Manager** → _New External Client App_ (ou App Manager → _New Connected App_) :

- OAuth activé, callback `http://localhost:1717/OauthRedirect` ;
- **Use digital signatures** : téléverser `devhub.crt` ;
- scopes : `api`, `refresh_token, offline_access`, `web` ;
- politique : _Admin approved users are pre-authorized_, puis ajouter le profil **System Administrator**
  (ou une permission set dédiée) à l'application.

Récupérer la **Consumer Key**.

## 3. Vérifier en local

```bash
sf org login jwt --client-id <consumer key> --jwt-key-file devhub.key \
  --username <utilisateur du Dev Hub> --alias devhub-jwt
```

## 4. Secrets GitHub (Settings → Secrets and variables → Actions)

| Secret                | Valeur                          |
| --------------------- | ------------------------------- |
| `SF_DEVHUB_CLIENT_ID` | Consumer Key                    |
| `SF_DEVHUB_USERNAME`  | nom d'utilisateur du Dev Hub    |
| `SF_DEVHUB_JWT_KEY`   | contenu complet de `devhub.key` |

## Quotas

Un Dev Hub Developer Edition autorise 3 scratch orgs actives et 6 créations par 24 h glissantes.
Le job ne tourne donc que sur `main` et à la demande (`workflow_dispatch`). Il est sérialisé (`concurrency`)
et supprime toujours son org.
