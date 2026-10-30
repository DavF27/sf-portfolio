# Portfolio Salesforce démontrable — Plan

## Objectif

Prouver une expertise Salesforce par des démonstrations **exécutables**, pas par du texte.
Chaque cas reproduit un mécanisme réel rencontré en mission, avec un état « avant » qui échoue,
un état « après » qui réussit, et des métriques mesurées dans l'org.

## Règles non négociables

1. **Écrit à partir de zéro.** Aucune classe, flow, donnée, nom d'objet ou identifiant d'un client n'est copié.
   On reproduit des mécanismes génériques de la plateforme.
2. **Dépôt personnel**, sur un compte GitHub personnel, sans lien avec l'organisation du client.
3. **Données 100 % synthétiques**, générées par script.
4. **Toute affirmation du README pointe vers une preuve** : un test, une sortie de CI, une métrique.
5. Vocabulaire neutre : « équipementier industriel B2B », « CPQ tiers », « ERP ».

## Environnements

| Rôle                 | Org                                                                         | Usage                                                |
| -------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------- |
| Vitrine + Dev Hub    | Developer Edition `<my-domain>` (alias à créer : `portfolio`) | Démo en direct, vidéo, création des scratch orgs     |
| Preuve reproductible | Scratch org éphémère créée par la CI                                        | Rejoue déploiement + tests + métriques à chaque push |

Contraintes de plateforme :

- stockage de données de la Developer Edition : **5 Mo mesurés** (`sf org list limits`, `DataStorageMB` = 5), soit environ 2 500 records à 2 Ko ;
- quotas de scratch orgs d'un Dev Hub Developer Edition : **3 actives, 6 créations par 24 h glissantes**
  ([doc officielle](https://developer.salesforce.com/docs/platform/sfdx-dev/guide/sfdx-dev-scratch-orgs-editions-and-allocations.html)).
  Conséquence : la CI scratch org ne tourne pas sur chaque push (voir Phase 1) et supprime toujours son org ;
- règle de désactivation des Developer Editions inactives : à vérifier ;
- Platform Events _Publish Immediately_ : **150 `EventBus.publish` par transaction**, limite distincte des DML
  ([Limits Class](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_methods_system_limits.htm)).
  Le publisher plafonne à 40 étapes de progression par run. Le quota quotidien de livraison d'événements en Developer Edition reste à vérifier.

Contraintes découvertes en Phase 2 (mesurées, preuves dans la CI) :

- un trigger déclenché par la **Bulk API** s'exécute avec les **limites asynchrones** : `SOQL_Limit__c` = 200 mesuré
  (100 depuis le panneau). Un lot de 50 lignes qui casse en synchrone passe donc en Bulk : la démo Bulk réelle utilise 100 lignes ;
- en **succès partiel** (Bulk API, `Database.update(…, false)`), la plateforme **rejoue le trigger** sur les lignes valides et les
  **variables statiques survivent** entre les tentatives : une garde anti-récursion par `Set` statique sauterait ces lignes.
  On garde sur la transition (Draft → Active) ;
- les flows record-triggered s'exécutent **par tranche de 200 enregistrements** : leur coût suit le nombre de tranches, pas de lignes ;
- une limite dépassée **dans un flow** pendant un DML Apex remonte en `DmlException` (`LIMIT_EXCEEDED`, interceptable),
  pas en `LimitException` : la valeur exacte du compteur n'est pas dans le message, d'où une étape publiée par contrat ;
- un flow qui met à jour un parent pendant le trigger de ce parent provoque `SELF_REFERENCE_FROM_TRIGGER` : les flows écrivent
  dans un journal enfant ;
- `update` en `USER_MODE` refuse un champ master-detail non reparentable présent sur l'enregistrement : mettre à jour des copies ;
- `Demo_Setting__mdt.getAll()` tronque les champs texte long à **255 caractères** (test de garde dans `DemoCatalogTest`) ;
- en Developer Edition (vitrine et scratch orgs), une **chaîne de Queueables compte au plus 5 jobs** : la démo asynchrone travaille
  par lots de 5 lignes, une chaîne par lot ;
- les tests Apex n'exécutent qu'un niveau de Queueable et `Test.stopTest()` s'arrête au premier job en échec : l'enchaînement est rejoué
  maillon par maillon (`AsyncChain`), l'isolement entre lots est prouvé par la CI ; un Transaction Finalizer s'exécute bien dans les tests ;
- des jobs asynchrones parallèles qui ferment un run doivent se sérialiser (`FOR UPDATE` sur l'enregistrement parent) ;
- Developer Edition : **10 000 livraisons de Platform Events par jour** (`DailyDeliveredPlatformEvents`, mesuré) : les batchs publient
  leur progression par paliers (20 étapes par run au plus) ;
- un test Apex n'exécute qu'un seul `execute()` par `Database.executeBatch` : un batch à lot de 1 est rejoué start / execute / finish ;
- un champ formule ne peut pas être affecté en Apex, même en mémoire : construire l'enregistrement par `JSON.deserialize` dans les tests ;
- l'URL _frontdoor_ de `sf org open --url-only` est **à usage unique** : Playwright se connecte une fois (global setup) et réutilise la session ;
- quota de scratch orgs atteint le 2026-10-29 (6 créations) : regrouper les push qui déclenchent la CI. Mesuré le 2026-10-30 à 10 h 43 :
  `DailyScratchOrgs` = 6/6 disponibles alors que 6 orgs avaient été créées moins de 24 h avant ; le compteur se réinitialise donc plus tôt que
  ne le laisse penser la règle « 24 h glissantes ». C'est `sf org list limits` qui fait foi.

## Architecture

```
sf-portfolio/
  force-app/
    core/          panneau LWC de démonstration, mesure des métriques, générateur de données, interrupteur avant/après
    demo-bulk/     lot Bulk API tout-ou-rien
    demo-order/    ordre d'exécution trigger / flow
    demo-async/    chaîne de Queueables qui casse en silence
    demo-batch/    batch : filtre en Apex vs filtre en SOQL
  tools/           outillage DevOps générique (fraîcheur, drift, garde de déploiement) + tests
  scripts/         génération de données, lancement des démos, export des métriques
  .github/workflows/ci.yml
  docs/            une fiche par cas
```

**Avant et après coexistent dans l'org.** Un Custom Metadata `Demo_Setting__mdt` (une ligne par démo, champ `Mode__c` = `BEFORE` | `AFTER`)
sélectionne l'implémentation via une interface (pattern stratégie). Le panneau LWC propose _Lancer avant_ / _Lancer après_ et affiche
les métriques enregistrées dans un objet `Demo_Run__c`. Le panneau affiche SOQL, DML, CPU, durée, records traités, records en échec et erreur.

**Décisions de conception (Phase 1)**

- Une CMDT ne se modifie pas par DML : le panneau et les scripts passent le mode explicitement ; `Mode__c` n'est que le mode par défaut.
  La CMDT porte aussi les classes `Before_Class__c` / `After_Class__c` / `Seeder_Class__c` et les bornes de volume (`Max_Volume__c` protège les 5 Mo de la vitrine).
- Une `System.LimitException` (cœur des démos AVANT) **ne peut pas être interceptée** et annule toute la transaction, y compris l'insertion d'un `Demo_Run__c`.
  Les mesures passent donc par `Demo_Step__e` en _Publish Immediately_, qui survit au rollback. Un trigger d'événement (`DemoStepHandler`) écrit `Demo_Run__c`
  par upsert sur `Run_Key__c`, une clé générée par l'appelant. Quand l'appel Apex meurt, l'appelant (panneau ou script) publie l'échec avec la même clé.
  La valeur qui a cassé la limite est lue dans le message de la plateforme (« Too many SOQL queries: 101 »).
- Les tests ne peuvent pas non plus intercepter une `LimitException`. Un test AVANT prouve donc l'échec en mesurant que la consommation croît linéairement
  avec le volume. L'échec réel est prouvé par `scripts/run-demos.js` dans la CI.
- Démo de calibration `Limits_Probe` (core) : AVANT = 1 SOQL par unité de volume, APRÈS = 1 SOQL. Elle valide toute la chaîne avant la Phase 2.

## Preuves visuelles et effet « wow »

Le portfolio doit **se voir**, pas seulement se lire. Principe : les visuels sont **produits par la machine**, pas retouchés à la main.

### Captures générées par la CI (preuve)

- Playwright ouvre la scratch org (`sf org open --url-only`), lance chaque démo en mode AVANT puis APRÈS depuis le panneau,
  et enregistre les captures dans `docs/screenshots/<demo>/before.png` et `after.png`, plus un GIF ou une vidéo du parcours.
- Chaque capture est publiée en artefact du job, avec l'identifiant du commit et la date, puis référencée par le README.
  Une capture prise à la main peut être truquée ; une capture régénérée à chaque push par une CI publique ne peut pas l'être.
- Captures complémentaires : page Setup > Apex Jobs, résultat du job Bulk API, résumé des tests de la CI.

### Effet « wow » par démo

| Démo                  | Visualisation dans le panneau LWC                                                                                                                                                                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lot Bulk tout-ou-rien | Jauges animées SOQL / CPU qui montent pendant le lot ; AVANT : jauge rouge à 101 et 50 lignes qui basculent en échec d'un coup ; APRÈS : jauge stable, 50 lignes vertes.                                                                           |
| Ordre d'exécution     | **Frise chronologique** de la transaction, reconstruite par instrumentation (chaque trigger et flow écrit une étape) : on voit le trigger passer avant le flow et la photo partir vide.                                                            |
| Chaîne asynchrone     | **Progression en temps réel via Platform Events** (`empApi`) : les lignes s'allument une à une, la chaîne casse sur la ligne piégée, les suivantes restent grises. APRÈS : le bundle passe d'un bloc, ou l'échec s'affiche en rouge avec sa cause. |
| Batch Apex vs SOQL    | **Course côte à côte** : les deux batchs lancés en même temps sur le même stock, deux barres de progression lues dans `AsyncApexJob`, chronomètre et nombre d'exécutions.                                                                          |
| Outillage DevOps      | Enregistrement terminal (asciinema ou GIF) : modification dans l'org → drift `UNKNOWN` avec auteur et date → déploiement bloqué en rouge.                                                                                                          |

### Page vitrine

- GitHub Pages : une page par démo avec le GIF, les captures AVANT/APRÈS, le tableau des métriques de la dernière CI
  et l'historique des runs (graphique). Lien de la page dans le CV et sur LinkedIn.
- Bouton « Chaos » dans le panneau : injecte la condition d'échec (ligne invalide, job qui plante) pour une démo en entretien.

## Phases et tâches

### Phase 0 — Mise en place

- [x] Dossier `c:\dev\sf-portfolio` créé.
- [x] Ouvrir `c:\dev\sf-portfolio` dans une **nouvelle fenêtre VS Code** (hors du dépôt client).
- [x] `git init`, `.gitignore` SFDX, licence (MIT). _(aucun commit encore)_
- [x] Identité Git **locale** personnelle (`git config user.name/user.email` dans ce dépôt) : `DavF27`. L'identité globale reste celle du client.
- [x] Connecter la Developer Edition (domaine `my.salesforce.com`, pas `lightning.force.com`) : `sf org login web --alias portfolio --instance-url https://<my-domain>.my.salesforce.com --set-default-dev-hub`
- [x] Activer Dev Hub dans Setup de la Developer Edition. _(vérifié le 2026-10-27 : `SELECT COUNT() FROM ScratchOrgInfo` répond)_
- [x] `target-org` et `target-dev-hub` en config **locale** du projet = `portfolio` (le `target-org` global pointe vers une sandbox client).
- [x] Créer le dépôt GitHub personnel `DavF27/sf-portfolio` (privé jusqu'à la publication). Les push passent par le jeton `gh` de `DavF27` (`GH_TOKEN`), sans changer le compte `gh` actif utilisé par l'autre fenêtre VS Code.

**Preuve :** `sf org display --target-org portfolio` OK, `sf org list` montre le Dev Hub.

### Phase 1 — Socle

- [x] `sfdx-project.json` avec un package directory par dossier de `force-app/`.
- [x] `Demo_Setting__mdt`, `Demo_Run__c`, classe `DemoMetrics` (capture des `Limits.*` et de la durée).
- [x] Interface `DemoStrategy` + fabrique qui lit le mode.
- [x] Panneau LWC `demoPanel` (liste des démos, boutons avant/après, tableau des derniers runs) + tests Jest.
- [x] Générateur de données synthétiques paramétrable (volume) : `SyntheticDataGenerator` (déterministe), interface `DemoDataSeeder`, `scripts/seed.js`.
- [x] Définition de scratch org `config/project-scratch-def.json`.
- [x] CI : authentification JWT au Dev Hub (secret GitHub) → scratch org → déploiement → tests Apex + Jest → export des métriques en artefact et dans le résumé du job → suppression de la scratch org.
      _Run [40883713530](https://github.com/DavF27/sf-portfolio/actions/runs/40883713530) (commit `c42022e`, 2026-10-29) : 46 tests Apex, 100 % de réussite, couverture 97 % ; scratch org créée puis supprimée. Contrainte : depuis Spring '26, la création de scratch org échoue en `C-1016` avec une app propre au Dev Hub (ECA ou Connected App) ; contournement officiel `SF_SCRATCH_SIGNUP_CONNECTED_APP=PlatformCLI` (voir [docs/ci-setup.md](docs/ci-setup.md))._

- [x] Instrumentation commune : événement `Demo_Step__e` (Platform Event) publié par chaque étape, consommé par le panneau (`empApi`).
- [x] Composants visuels réutilisables : jauges de limites, frise chronologique, barres de progression.
- [x] Playwright dans la CI : captures AVANT/APRÈS + GIF par démo, publiés en artefact. _`Limits_Probe` : `panel.png`, `before.png`, `after.png`, `limits-probe.gif` dans l'artefact `proof-<sha>`. Métriques mesurées : AVANT 101 SOQL, échec `Too many SOQL queries: 101` ; APRÈS 1 SOQL, 150/150._
- [x] Validation Apex dans une org : `sf project deploy validate --source-dir force-app/core --test-level RunLocalTests` sur `portfolio` (check-only, rien enregistré),
      validation `0Afak00000q0Yv3CAE` du 2026-10-27 : **46 tests, 0 échec, couverture 97,4 %**.
      Leçons : `WITH USER_MODE` impose la FLS, donc les tests tournent sous un utilisateur `Demo_Admin` (`DemoTestFactory.demoUser()`) ;
      `Assert.*` refuse un message `null` ; une FlexiPage sans parent n'accepte pas `<mode>Replace</mode>`.

État au 2026-10-29 : CI verte de bout en bout. Défauts relevés sur les premières captures et corrigés : jauge DML « / 1 » (`getLimits` était `cacheable=true`, contexte en lecture seule où la plateforme annonce une limite DML de 1 ; désormais appel impératif, puis limites de la transaction du run) ; barre utilitaire figée au milieu des captures pleine page (masquée par géométrie avant capture) ; durée des runs en échec non intercepté écrasée par les horodatages des événements, précis à la seconde (désormais en dernier recours seulement).

Vitrine : socle déployé dans `portfolio` le 2026-10-29 (déploiement `0Afak00000qKWQoCAO`, 91 composants, 47 tests Apex, 0 erreur), permission set `Demo_Admin` attribuée ; panneau affiché sur l'onglet _Demo Panel_ (vérifié par chargement headless, sans lancer de démo). Quatrième défaut corrigé au passage : les étapes reçues pendant l'enregistrement d'un échec non intercepté étaient écrasées (`0a16268`, test de non-régression qui échoue sur l'ancien code).

**Preuve :** CI verte publique, panneau visible dans la vitrine, première capture générée par la CI.

### Phase 2 — Démo « Lot Bulk tout-ou-rien »

Mécanisme : un lot Bulk API passe dans une seule transaction de trigger ; une cascade (trigger parent → mise à jour des enfants
→ flows) dépasse une limite et **toutes** les lignes du lot échouent.

- [x] Modèle : `Contract_Demo__c` (parent) → `Deal_Demo__c` (master-detail, mis à jour à l'activation, règle de validation)
      → `Activation_Log_Demo__c` écrit par 2 flows record-triggered after-save sur Deal.
- [x] AVANT (`ContractActivationBefore`) : requête et `update` des deals contrat par contrat, chaque DML relance les 2 flows (~3 SOQL et 3 DML par contrat).
- [x] APRÈS (`ContractActivationAfter`) : une requête, un `Database.update(deals, false)`, `addError` sur la seule ligne en échec, échec journalisé
      dans `Demo_Run__c` (`Records_Failed__c`, message) via `Demo_Step__e`.
- [x] Mode choisi par ligne (`Processing_Mode__c` envoyé dans le CSV) : un job Bulk ne transporte pas de paramètre.
- [x] Script `scripts/bulk-demo.js` : vrai job Bulk API 2.0 (`sf data upsert bulk`), lecture du résultat du job, jointure avec `Demo_Run__c`.
- [x] Panneau : composant `rowGrid` (une tuile par ligne du lot).
- [x] Tests : 200 contrats APRÈS (succès, coût par tranche de 200), AVANT extrapolé (`LimitException` non interceptable) → rupture avant 50 lignes,
      ligne invalide isolée en APRÈS (199/1) et lot entier en échec en AVANT. 65 tests Apex, couverture 98 %, 100 % sur les classes de la démo.

**Preuve** (CI [40899094782](https://github.com/DavF27/sf-portfolio/actions/runs/40899094782), commit `e9d8ebd`) :

| Chemin                                     | Lignes | AVANT                                                                        | APRÈS                     | APRÈS + Chaos                               |
| ------------------------------------------ | -----: | ---------------------------------------------------------------------------- | ------------------------- | ------------------------------------------- |
| Vrai job Bulk API (async, limite SOQL 200) |    100 | ❌ 100/100 en échec, `Too many DML statements: 151` (SOQL 120/200)           | ✅ 100/100, 3 SOQL, 3 DML | ⚠️ 99/1, `Amount must be greater than zero` |
| Panneau (synchrone, limite SOQL 100)       |     50 | ❌ 50/50 en échec, `LIMIT_EXCEEDED` dans un flow (SOQL 96/100 au contrat 32) | ✅ 50/50, 3 SOQL          | ⚠️ 49/1                                     |

Captures `docs/screenshots/bulk-all-or-nothing/` (`before.png`, `after.png`, `chaos.png`, GIF) dans l'artefact `proof-<sha>`.
Vitrine : déployée dans `portfolio` le 2026-10-29 (`0Afak00000qKii7CAC`, 131 composants, 65 tests), permission set `Demo_Bulk` attribuée.

Corrections vérifiées par la CI [41035719990](https://github.com/DavF27/sf-portfolio/actions/runs/41035719990) (commit `86bf23e`) :
`chaos.png` correcte, description complète, erreurs résumées dans le tableau des runs.

### Phase 3 — Démo « Ordre d'exécution trigger / flow »

Mécanisme : un trigger `after update` s'exécute **avant** un flow `after-save` ; une copie (« photo ») créée par le trigger
manque les valeurs calculées par le flow.

- [x] Modèle : `Asset_Demo__c` + `Asset_Snapshot_Demo__c` (master-detail ; suffixe `_Demo` comme les autres démos).
- [x] AVANT : calcul dans le flow after-save `Asset_Demo_Service_Terms_After_Save` → le trigger after prend une photo vide ; au
      réenregistrement déclenché par le flow, ce n'est plus une nouvelle installation, donc pas de nouvelle photo.
- [x] APRÈS : choix documenté = **déplacement du calcul dans un flow before-save** (`Asset_Demo_Service_Terms_Before_Save`) ;
      alternative « rafraîchir la photo » écartée (voir la fiche). Même trigger, flow choisi par `Processing_Mode__c`.
- [x] Échec AVANT **silencieux** : run « Succeeded », chaque photo incomplète comptée comme ligne en échec (grille rouge).
- [x] Frise : chaque acteur publie son étape (trigger before = témoin du flow before-save, qui ne peut pas appeler d'Apex ;
      flow after-save via l'action invocable `DemoStepAction`) ; séquence partagée par run dans `DemoStepPublisher`.
- [x] Tests : 200 records, assertions sur chaque champ de chaque photo (AVANT : vides ; APRÈS : égales aux valeurs recalculées en Apex),
      ordre des étapes vérifié. Validation check-only dans `portfolio` : **81 tests Apex, 0 échec**.
- [x] Fiche [docs/demos/order-of-execution.md](docs/demos/order-of-execution.md) avec les schémas Mermaid AVANT/APRÈS.

**Preuve** (CI [41035719990](https://github.com/DavF27/sf-portfolio/actions/runs/41035719990), commit `86bf23e`, 81 tests Apex) :

| Mode  | Volume | Run                             | Photos incomplètes | SOQL | DML |
| ----- | -----: | ------------------------------- | -----------------: | ---: | --: |
| AVANT |    200 | ✅ Succeeded (échec silencieux) |          200 / 200 |    3 |   3 |
| APRÈS |    200 | ✅ Succeeded                    |            0 / 200 |    2 |   2 |

Captures `docs/screenshots/order-of-execution/` : la frise AVANT montre trigger before → trigger after (photo vide) → flow after-save →
réenregistrement. Vitrine : déployée dans `portfolio` le 2026-10-30 (`0Afak00000qSm3nCAC`, 164 composants), permission set `Demo_Order` attribuée.

### Phase 4 — Démo « Chaîne asynchrone silencieuse »

Mécanisme : activation ligne par ligne, un Queueable par ligne enchaîné au précédent ; un job qui échoue arrête la chaîne
sans erreur visible, le groupe reste bloqué dans un état intermédiaire.

- [x] Modèle : `Order_Demo__c` → `Order_Bundle_Demo__c` (lots de 5, limite de chaîne en Developer Edition) → `Order_Line_Demo__c`,
      règle de validation sur le prix unitaire (ligne piégée injectée par Chaos).
- [x] AVANT (`LineActivationChainJob`) : un job par ligne, enchaîné, sans finalizer ni gestion d'erreur → chaîne arrêtée en silence,
      lot bloqué en _Activating_, run jamais fermé.
- [x] APRÈS (`BundleActivationJob` + `BundleActivationFinalizer`) : un job par lot, une mise à jour tout-ou-rien, Transaction Finalizer
      qui journalise l'échec (lot _Failed_ + cause) ; le dernier lot ferme le run (clôture verrouillée).
- [x] Requête de détection des lignes bloquées (`AsyncOrderStrategy.inspect`, interface `DemoMonitor`) : appelée par le panneau après 20 s
      sans nouvelle étape, et par `run-demos.js` une fois les jobs terminés.
- [x] Socle : runs asynchrones (`DemoResult.pending`), tuiles pilotées ligne par ligne (`Rows_Done__c`, `Rows_Failed__c`), étapes asynchrones
      sans séquence (ordre d'arrivée).
- [x] Tests : 109 tests Apex (couverture 98,8 %), 34 tests Jest, 21 tests de scripts. Fiche [docs/demos/async-chain-break.md](docs/demos/async-chain-break.md).

**Preuve** (CI [41045565063](https://github.com/DavF27/sf-portfolio/actions/runs/41045565063), commit `cb87693`, 110 tests Apex) :

| Mode  | Chaos | Lignes | Run          | Lignes en échec | Comment le run est fermé                                                                                      |
| ----- | ----- | -----: | ------------ | --------------: | ------------------------------------------------------------------------------------------------------------- |
| AVANT | non   |    100 | ✅ Succeeded |               0 | dernier maillon (100 jobs, un par ligne)                                                                      |
| APRÈS | non   |    100 | ✅ Succeeded |               0 | dernier finalizer (20 jobs, un par lot)                                                                       |
| AVANT | oui   |    100 | ❌ Failed    |      3 bloquées | **par la surveillance** : aucun job ne l'a fermé, aucune erreur journalisée (1 job en échec dans _Apex Jobs_) |
| APRÈS | oui   |    100 | ✅ Succeeded |  5 journalisées | dernier finalizer, lot piégé _Failed_ avec sa cause, 0 ligne bloquée                                          |

Captures `docs/screenshots/async-chain-break/` : en AVANT, les tuiles s'allument chaîne par chaîne, 47 vertes et 3 rouges après détection.
Vitrine : déployée dans `portfolio` le 2026-10-30 (`0Afak00000qTsLdCAK`, 203 composants, 110 tests), permission set `Demo_Async` attribuée.

Défaut trouvé par le premier run CI et corrigé : un run asynchrone lancé sous les jobs du précédent réinitialisait les mêmes lignes
(`UNABLE_TO_LOCK_ROW`). La stratégie refuse désormais de démarrer tant que des jobs d'activation tournent, et `run-demos.js` attend
puis surveille chaque run asynchrone avant le suivant.

### Phase 5 — Démo « Batch : filtre Apex vs SOQL »

Mécanisme : un batch parcourt tout le stock et filtre en Apex, record par record ; un batch équivalent filtre dans la requête
(formule ou date calculée) et ne traite que les éligibles.

- [x] Modèle : `Renewal_Demo__c` avec date de début, durée, préavis ; formule `Notice_Deadline__c` ; `Lane__c` pour que les deux modes
      courent en même temps sur des stocks séparés. 1 contrat sur 20 est dû.
- [x] AVANT (`RenewalNoticeBatchBefore`) : `start` sans filtre, taille de lot 1, filtre en Apex.
- [x] APRÈS (`RenewalNoticeBatchAfter`) : filtre en SOQL sur la formule, taille de lot 200. Mêmes avis envoyés (test de comparaison).
- [x] Mesure via `AsyncApexJob` (`JobItemsProcessed` → `Demo_Run__c.Async_Executions__c`, durée jusqu'au `finish`).
      Vitrine : 500 contrats par couloir ; CI : 1 000 par couloir (au lieu de 2 000+, à ajuster selon la durée mesurée de l'AVANT).
- [x] Visuel : bouton _Race_ (interface `DemoRaceable`), composant `raceLanes` (progression, chronomètre, exécutions, premier arrivé).
- [x] Tests : 122 tests Apex, 41 tests Jest, 22 tests de scripts. Fiche [docs/demos/batch-filter.md](docs/demos/batch-filter.md).

**Preuve (CI verte, run 41054955308, commit `89a7fe8`, scratch org, 1 000 contrats par couloir) :**

| Mode                            | Exécutions (`JobItemsProcessed`) | Durée jusqu'au `finish` | Avis envoyés |
| ------------------------------- | -------------------------------: | ----------------------: | -----------: |
| AVANT (filtre Apex, lot de 1)   |                            1 000 |                    32 s |           50 |
| APRÈS (filtre SOQL, lot de 200) |                                1 |                     1 s |           50 |

Le run précédent (41052625837) mesurait 52 s contre 2 s : la durée de l'AVANT varie avec la file d'attente asynchrone partagée,
le nombre d'exécutions ne varie pas. Captures de la course : `race.png` (APRÈS terminé, AVANT à 0/200) et `race-finished.png`.
Correctif issu de la CI : au lancement, la stratégie annonçait tout le stock comme couvert ; elle annonce désormais 0.

**Déployé dans `portfolio`** le 2026-10-30 (`0Afak00000qUQjtCAG`, 230 composants, 122 tests), permission set `Demo_Batch` attribuée.

### Phase 6 — Outillage DevOps

Réécriture générique (aucun code client copié) :

- [ ] **Fraîcheur** : prouver que la version locale d'un composant est identique à l'org avant analyse (statut `fresh`/`stale`/`missing`).
- [ ] **Drift** : classer les écarts org ↔ Git (connu / intentionnel / inconnu + auteur et date de la modification dans l'org).
- [ ] **Garde de déploiement** : refuser d'écraser un composant modifié dans l'org depuis la dernière récupération ; tag Git du déploiement.
- [ ] Tests automatisés des scripts dans la CI.

**Preuve :** démo enregistrée — modification directe dans l'org vitrine → drift `UNKNOWN` → déploiement bloqué.

### Phase 7 — Publication

- [ ] README principal : une ligne par démo (problème, mécanisme, lien vers la fiche, badge CI).
- [ ] Une fiche par cas dans `docs/` : contexte anonymisé → symptôme → hypothèse et preuve → cause racine → solution (schéma Mermaid) → résultat mesuré → compétences.
- [ ] Vidéo de 2 à 3 minutes (panneau LWC, avant/après), montée à partir des GIF de la CI et commentée.
- [ ] Page GitHub Pages publiée (GIF, captures, métriques, historique).
- [ ] Relecture anonymisation (aucun nom de client, d'objet, de ticket, d'Id, de personne).
- [ ] Liens vers certifications et profil Trailhead ; demander une recommandation LinkedIn à un manager ou à un Business Analyst.

## Définition de « terminé » pour une démo

- Test AVANT en échec documenté et test APRÈS vert dans la CI.
- Métriques enregistrées dans `Demo_Run__c` et publiées par la CI.
- Fiche rédigée, schéma inclus, relue pour l'anonymisation.
- Lançable depuis le panneau de la vitrine, avec sa visualisation animée.
- Captures AVANT/APRÈS et GIF générés par la CI, référencés dans la fiche et sur la page vitrine.

## Reprise dans une nouvelle conversation

Ouvrir `c:\dev\sf-portfolio` dans une nouvelle fenêtre VS Code, puis :

> « Lis PLAN.md et démarre la Phase 0, puis la Phase 1. Ne déploie rien sans mon accord. »
