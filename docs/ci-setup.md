# Mise en place de la CI (authentification JWT au Dev Hub)

Le job `scratch-org` de [ci.yml](../.github/workflows/ci.yml) se connecte au Dev Hub `portfolio` sans mot de passe,
par le flux OAuth 2.0 JWT Bearer. Ces étapes sont manuelles et se font **une seule fois**.

## 1. Générer une paire clé/certificat (localement, hors du dépôt)

Windows / PowerShell : `openssl` n'est pas dans le PATH, mais Git for Windows en fournit un.
Le `\` de continuation de ligne est propre à bash ; en PowerShell, la commande tient sur une ligne.

```powershell
$certDir = "$HOME\.sf-portfolio-ci"
New-Item -ItemType Directory -Force $certDir | Out-Null
& "$env:ProgramFiles\Git\mingw64\bin\openssl.exe" req -x509 -newkey rsa:2048 -sha256 -days 730 -nodes -keyout "$certDir\devhub.key" -out "$certDir\devhub.crt" -subj "/CN=sf-portfolio-ci"
```

macOS / Linux / Git Bash :

```bash
mkdir -p ~/.sf-portfolio-ci && cd ~/.sf-portfolio-ci
openssl req -x509 -newkey rsa:2048 -sha256 -days 730 -nodes \
  -keyout devhub.key -out devhub.crt -subj "/CN=sf-portfolio-ci"
```

`devhub.key` est un secret : il reste hors du dépôt et n'est jamais committé (`*.key` et `*.crt` sont en plus dans `.gitignore`).
Le certificat expire après 730 jours : il faudra alors le régénérer et le téléverser à nouveau.

## 2. Créer l'application dans le Dev Hub

⚠️ Selon la [doc Salesforce CLI](https://developer.salesforce.com/docs/platform/sfdx-dev/guide/sfdx-dev-auth-eca.html), un Dev Hub
qui **crée des scratch orgs** doit encore passer par une _Connected App_, pas par une _External Client App_ (ECA).
Or, depuis Spring '26, la création de Connected Apps est désactivée par défaut.

1. Setup → Quick Find `External Client Apps` → **Settings** : si le bouton **Allow creation of connected apps** est présent, l'activer
   et créer une **Connected App** (App Manager → _New Connected App_) :
   - _Enable OAuth Settings_, callback `http://localhost:1717/OauthRedirect` ;
   - **Use digital signatures** → téléverser `devhub.crt` ;
   - scopes `api`, `web`, `refresh_token, offline_access` ;
   - _Manage_ → _Edit Policies_ → _Admin approved users are pre-authorized_ → _Manage Profiles_ : **System Administrator**.
2. Sinon, créer une **External Client App** (App Manager → _New External Client App_), puis valider qu'elle permet de créer une scratch org (étape 3) :
   - _Enable OAuth_, callback `http://localhost:1717/OauthRedirect`, mêmes scopes ;
   - section **Flow Enablement** → cocher **Enable JWT Bearer Flow** : le champ de téléversement du certificat apparaît → `devhub.crt` ;
   - _Create_, puis _Edit_ → onglet **Policies** → _Permitted Users_ = _Admin approved users are pre-authorized_,
     et sélectionner le profil **System Administrator**.

Récupérer la **Consumer Key** (onglet _Settings_ → _OAuth Settings_ → _Consumer Key and Secret_).

## 3. Vérifier en local

```powershell
sf org login jwt --client-id <consumer key> --jwt-key-file "$HOME\.sf-portfolio-ci\devhub.key" --username <utilisateur du Dev Hub> --alias devhub-jwt
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
