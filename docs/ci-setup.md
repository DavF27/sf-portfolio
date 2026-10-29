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

Une **Connected App** classique (App Manager → _New Connected App_ ; dans `portfolio` : `demo2`) :

1. _Enable OAuth Settings_, callback `http://localhost:1717/OauthRedirect` ;
2. juste en dessous, cocher **Use digital signatures** → _Choose File_ → `devhub.crt`. Sans certificat, le JWT échoue
   avec `invalid assertion` ;
3. scopes `api`, `web`, `refresh_token, offline_access` (pas _Full access_) ;
4. _Save_, puis _Manage_ → _Edit Policies_ → _Permitted Users_ = **Admin approved users are pre-authorized** ;
5. _Manage Profiles_ → **System Administrator** ;
6. attendre une dizaine de minutes, le temps que l'app soit active.

Récupérer la **Consumer Key** (_Manage Consumer Details_). Le Consumer Secret ne sert pas au JWT.

Une External Client App convient aussi pour le JWT (_Flow Enablement_ → cocher le flux JWT → téléverser `devhub.crt`).

### Erreur `C-1016` à la création de la scratch org

Depuis Spring '26, le service d'inscription ne sait plus répliquer l'app du Dev Hub dans la nouvelle scratch org,
et ce, qu'il s'agisse d'une ECA ou d'une Connected App (mesuré le 2026-10-29 avec `demo2`).
Le contournement officiel, affiché par `@salesforce/core` ≥ 9.4 et suivi dans [forcedotcom/cli#3515](https://github.com/forcedotcom/cli/issues/3515),
consiste à faire passer l'inscription par l'app intégrée de la CLI. [ci.yml](../.github/workflows/ci.yml) le fait à l'étape _Create scratch org_ :

```yaml
SF_SCRATCH_SIGNUP_CONNECTED_APP: PlatformCLI
SF_SCRATCH_SIGNUP_CALLBACK_URL: http://localhost:1717/OauthRedirect
```

Une création en échec ne consomme pas le quota quotidien.

## 3. Tester uniquement dans la CI

Ne pas tester `sf org login jwt` en local avec le même utilisateur que l'alias `portfolio` : la connexion JWT remplace la connexion web,
et un échec supprime l'autorisation locale. Lancer plutôt le workflow à la demande (_Actions_ → _CI_ → _Run workflow_).

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
