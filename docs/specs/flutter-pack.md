# Spec : pack Flutter/Dart pour AI Craftsman Superpowers

Statut : proposition. Cible : v5.0.0.
Base de code auditée : commit `9e894d5`, version plugin 4.3.3.
Recherche terrain datée du 2026-08-08 (versions et statuts d'écosystème vérifiés en live à cette date).

---

## 0. Verdict

**Le pack Flutter est pertinent sur le fond, bloqué sur la forme.**

Sur le fond : Flutter a une pathologie architecturale réelle et mécanisable (logique métier dans les `Widget`, `setState` comme couche de persistance, BLoC ou Riverpod utilisés en service locator, `dynamic` et `!` pour faire taire l'analyzer). Dart offre des invariants proches de ce que le pack React valide déjà. Et l'écosystème Dart a trois trous béants que ce plugin sait combler mieux que quiconque (section 3.3).

Sur la forme : **l'activation des packs et la sévérité des règles sont bien pilotées par la configuration. C'est le routage fichier vers validateur qui ne l'est pas**, et il est en amont des deux mécanismes qui le sont, donc il les annule pour tout langage qu'il ne connaît pas.

Distinction importante, parce que la formulation grossière "les packs sont câblés en dur" est fausse. Trois couches, dont deux fonctionnent (section 2.0).

### Statut de ce document

Le diagnostic de la section 2 a été **vérifié dans le code au commit `9e894d5`**, avec preuve d'exécution pour les points marqués comme tels.

**La Phase 0 a été livrée en v4.4.0**, à deux livrables près. Ce qui existe désormais : le bloc `languages:` dans `pack.yml`, `hooks/lib/lang-registry.sh` et son index TSV caché, la disparition des dix `case "$EXT"`, la parité hook/CI restaurée, `add_warning` passant par le rules engine, et cinq capacités consommées par leur vrai consommateur (`test_commands`, `protected_configs`, `lsp`, `entry_markers`, `metrics_dialect`). Voir le CHANGELOG 4.4.0.

**Restent ouverts de la Phase 0** : `ci/doctrine-export.sh` porte toujours les identifiants de règles et leurs textes en dur, donc un pack ne peut pas déclarer `DART001` ; et `hooks/lib/routing-table.sh` teste encore les noms de packs en littéraux. Le schéma `pack.yml`, le guide d'auteur de pack et l'ADR ne sont pas écrits.

Tout ce qui est décrit en section 3 et au-delà **n'existe pas** : aucune ligne de Dart ou de Flutter dans le dépôt, aucune règle `DART00x` implémentée, aucun validateur écrit. C'est une proposition à construire, pas un inventaire de capacités. Aucun élément de la section 3 ne doit être présenté à un utilisateur comme disponible.

**Décision recommandée (certitude 85 pour cent) : Phase 0 avant Phase 1.** Rendre le dispatch manifest-driven, ce qui referme au passage le trou de parité Python/Bash déjà présent, puis livrer Flutter comme premier pack qui ne touche pas le core. Le critère d'acceptation du seam devient : `git diff --stat` après installation du pack ne montre rien hors de `packs/flutter/`. Sinon l'extensibilité est du marketing.

**Non-goal assumé** : ce pack ne vise pas à couvrir Flutter Web ni Flutter Desktop en tant que cibles de rendu. Il vise le développement mobile professionnel (iOS/Android) : architecture, testabilité, frontières de couches, discipline de code.

---

## 1. Ce que la recherche a établi

### 1.1 Versions de référence au 2026-08-08

| Élément | Version | Note |
|---|---|---|
| Flutter stable | 3.44.9 (2026-08-06) | lignée 3.44 = Google I/O 2026 |
| Dart stable | 3.12.2 | |
| Flutter beta | 3.47.0-0.4.pre (Dart 3.13 beta) | promotion stable visée août 2026 |
| Charnière outillage | **Dart 3.10 = Flutter 3.38** (nov 2025) | nouveau système de plugins analyzer |

Cadence : cuts trimestriels (3.41 fév, 3.44 mai, 3.47 août, 3.50 nov 2026). Pas de Flutter 4 annoncé.

### 1.2 Le fait structurant : `custom_lint` est mort, `dart analyze` a tout absorbé

C'est **le** point qui décide de l'architecture technique de ce pack.

- Le nouveau système de plugins analyzer a shippé dans **Dart 3.10 / Flutter 3.38** (nov 2025). Déclaration `plugins:` au **niveau racine** de `analysis_options.yaml`, plus sous `analyzer: plugins:`.
- `invertase/dart_custom_lint` est **archivé en lecture seule depuis le 2026-03-24**. Son README renvoie explicitement vers `analysis_server_plugin`.
- La dépréciation du système legacy est planifiée (dart-lang/sdk#62164, phase 2 à partir de Dart 3.12).
- `riverpod_lint` 3.1.8 et `import_lint` 2.0.0 ont déjà migré. `architecture_lints` 0.1.5 est resté sur custom_lint : ne pas construire dessus.

Conséquence directe : **un seul parseur suffit**. `dart analyze --format=machine` agrège SDK + lints + plugins tiers + règles maison dans un format à 8 colonnes stable :

```
SEVERITY|TYPE|CODE|FILE_PATH|LINE|COLUMN|LENGTH|MESSAGE
```

Échappement : le backslash échappe `|` et `\` dans FILE_PATH et MESSAGE ; newline devient `\n`, CR devient `\r`.

Côté PHP il faut parser PHPStan, ECS et deptrac séparément. Côté Dart, un seul flux. C'est un avantage net.

Deux pièges à documenter :
- `--format=json` a un bug historique de préambule texte (dart-lang/sdk#54877). **Parser `machine`, pas `json`.**
- `flutter analyze` n'a **pas** `--format` et a des défauts différents (`--fatal-infos` à `true` alors que `dart analyze` l'a à `false`). **Utiliser `dart analyze --format=machine` même sur un projet Flutter** : même analyzer, format spécifié.

### 1.3 Les trois trous exploitables de l'écosystème Dart

1. **Aucune métrique de code open source.** `dart_code_metrics` est freezé depuis 2023-07-16 et marqué discontinued. DCM (dcm.dev) est commercial : le tier Free plafonne à 50 000 lignes et **l'intégration CI/CD est gated au tier Teams à 80 dollars/mois**. `clean_code_lints` 0.3.1 couvre longueur de fichier/fonction/classe et nombre de paramètres, mais ni la complexité cyclomatique ni la profondeur d'imbrication, et il totalise 203 téléchargements.
   **Or ce plugin calcule déjà NEST001, LOC001, GOD001, PARAM001 et les ratchete.** C'est du gratuit face à un marché payant.
2. **Aucune règle "final class by default".** La doc officielle Dart (`dart.dev/language/class-modifiers-for-apis`) le recommande en prose, aucun lint ne l'applique. Pas de `prefer_final_class` dans les 212 règles de `very_good_analysis`.
3. **Aucun problem matcher ni émetteur SARIF first-party.** Ni `dart-lang/setup-dart@v1` ni `subosito/flutter-action@v2` n'enregistrent de problem matcher (vérifié sur leurs README) : contrairement à une idée reçue répandue, il n'y a **aucune annotation inline automatique** des erreurs analyzer sur les PR GitHub. Le seul pont est `advanced-security/dart-analyzer-sarif`, non officiel. DCM couvre le gap avec des reporters `github`/`gitlab`/`checkstyle`/`sonar`, mais derrière son paywall CI.
   **Or `ci/adapters/` fait exactement ça, pour quatre providers, gratuitement.** Générer `::error file=...,line=...,col=...::message` depuis 8 colonnes pipe-séparées est trivial.

### 1.4 Arbitrage d'architecture : Google MVVM par défaut, pas Reso Coder

Trois doctrines en présence.

**Google, officiel** (`docs.flutter.dev/app-architecture`, section complète et prescriptive) :
- UI layer : **View** + **ViewModel** en relation 1:1. Les Views n'ont aucune logique métier. Les ViewModels exposent données et **Commands**.
- Data layer : **Repository** (source de vérité, cache, retry ; "should never be aware of each other") + **Service** (sans état, wrappe REST/plateforme/fichiers).
- **Domain layer : OPTIONNEL.** Use-cases uniquement quand la logique combine plusieurs repositories, est très complexe, ou est réutilisée entre ViewModels. Citation : *"A good approach is to add use-cases only when needed."*
- Erreurs : **`sealed class Result<T>` écrite à la main** avec `Ok`/`Error`, dépliée par `switch` avec pattern matching. Dart core n'a toujours pas de `Result`.
- Nav : `go_router`. DI : le package `provider` (oui, `provider`, pas `get_it` ni Riverpod).
- Échantillon vivant : `compass_app` dans `flutter/samples`. Feature-first côté UI, type-first côté data.

**Very Good Ventures** : 4 couches par feature (Data, Repository, Business Logic, Presentation), Data et Repository en packages Dart séparés dans `packages/`, zéro Flutter SDK dans ces packages, path deps, barrel exports. Solide en pratique, mais **ce n'est pas du DDD** : il n'y a pas de couche Domain isolée (le modèle de domaine vit dans le package Repository, donc l'infrastructure porte le domaine), pas d'inversion de dépendance par interface (le Bloc dépend de la classe concrète), pas de Value Objects, pas d'Aggregates, pas de Domain Events.

**Reso Coder** (référence citée par le demandeur) : deux séries distinctes et **doctrinalement contradictoires**, dont le code source des trois dépôts a été lu intégralement.

| | Série A : Clean Architecture TDD (2019, 9 parties) | Série B : Firebase DDD (2020, 5 parties écrites sur ~32 vidéos) |
|---|---|---|
| Organisation | `lib/features/<f>/{domain,data,presentation}/` : **couches dans la feature** | `lib/{domain,application,infrastructure,presentation}/<f>/` : **features dans la couche**, alors que l'article annonce l'inverse. Contradiction non corrigée. |
| Couches | 3 | **4** : `application` intercalée, c'est là que vivent les BLoCs |
| Use cases | `abstract class UseCase<Type, Params>` avec `call()`, un par verbe métier, `Params` local par use case | **supprimés** : les BLoCs appellent directement les repositories |
| Erreur | `Either<Failure, T>` (dartz), hiérarchie `Failure` en `Equatable` | `Either<Failure, T>` (dartz), unions `freezed` par bounded context |
| Value Objects | aucun, `Entity` = `Equatable` nue | `ValueObject<T>` avec `factory` validant + constructeur privé `._`, validateurs top-level composés par `flatMap` |
| Tests | **TDD strict**, miroir `test/` exact, AAA explicite, `verifyNoMoreInteractions` | **zéro test.** Aucun. |
| DI | `get_it` manuel, `final sl = GetIt.instance` | `get_it` + `injectable` codegen |

**Ce qui est mort dans le code livré** (faits durs, pas d'opinion) :
- `dartz` a pour dernière publication le **2021-12-03**, contrainte SDK `>=2.12.0 <3.0.0` : **incompatible Dart 3**, donc le code ne compile pas. Son flag `isDiscontinued` est pourtant à `false` : un outil qui se fie à ce flag ne le détecte pas.
- `kt_dart` (1.1.0, 2023-03-20) et `data_connection_checker` (0.3.4, **2019-06-09**, 471 téléchargements sur 30 jours) : SDK `<3.0.0`, incompatibles Dart 3.
- `mapEventToState` et le getter `initialState` : **dépréciés en bloc 7.2.0, supprimés en bloc 8.0.0** (2021-11-18). Actuel : `bloc` 9.2.1. Réécriture complète des blocs obligatoire.
- `@required`, `assert(input != null)` : morts depuis la null safety saine (Dart 2.12, 2021-03-03).
- `auto_route` : vivant (11.1.0) mais la doc officielle dit *"Use go_router for navigation. Go_router is the preferred way to write 90% of Flutter applications."* (go_router 3.63M dl/30j contre 332k).
- `mockito` 4 avec `extends Mock implements X` nu : ne compile plus, la null safety impose `@GenerateNiceMocks` + `build_runner`.
- `equatable` reste **vivant** (2.1.0, 5.56M dl/30j). Seul changement : `EquatableMixin` déprécié.

**Deux défauts structurels indépendants du temps**, à ne pas reproduire :
1. `firestore_helpers.dart` appelle le service locator **depuis l'infrastructure** (`getIt<IAuthFacade>()` dans une extension sur `Firestore`). C'est un service locator caché, pas de l'injection, et l'extension devient intestable sans conteneur global.
2. `NetworkInfo.isConnected` vérifié **avant** chaque appel dans le repository : race condition entre le check et l'appel, faux positif sur portail captif. Le pattern correct est de faire l'appel et de gérer l'échec.

**Ce qui survit, et c'est beaucoup** : sept principes, tous au niveau du principe, aucun au niveau de l'implémentation.

1. La **règle de dépendance** : Domain n'importe rien. Reformulée officiellement en *"unidirectional data flow"* et *"Repositories should never be aware of each other."*
2. L'**inversion par interface** : `abstract` dans domain, `Impl` dans data. Classé *"Strongly recommend"* par Flutter.
3. La **frontière exception vers failure** : les exceptions ne franchissent pas la couche Data, un seul endroit convertit. Seul le véhicule change (`Either` devient `Result`).
4. L'**erreur dans le type de retour**. Reso Coder en 2023 : *"Failing at compile time is what we want, not at run time"*. Équipe Flutter en 2025 : *"Result classes force the calling method to check for errors."* Même thèse, implémentation opposée.
5. Le **Value Object auto-validant** : validation en `factory`, constructeur privé, impossible de construire un objet invalide. C'est l'apport le plus durable et **le plus mal copié** : la plupart des gens ont recopié `dartz` sans comprendre qu'il n'était qu'un véhicule pour compenser l'absence de `sealed` avant Dart 3.
6. La **séparation Watcher / Actor** (lecture réactive contre commande, deux objets d'état distincts) : c'est du CQRS appliqué à l'UI, jamais nommé comme tel dans le cours, et valable avec n'importe quel state management.
7. La **discipline de test de la série A** : ordre de l'intérieur vers l'extérieur, miroir `test/` strict, AAA explicite, `setUp` factorisé par contexte. La syntaxe a changé, la méthode non.

Reso Coder lui-même a bougé : son article du 2023-12-05 recommande `fpdart` et montre des `sealed class` Dart 3 avec pattern matching. Sa position sur le principe n'a pas changé, son implémentation oui.

**Résumé** : Reso Coder a eu raison sur le principe et l'histoire lui a donné tort sur presque toute l'implémentation. Le profil `ddd` du pack est une **modernisation** de cette doctrine, pas une copie : `sealed Result` au lieu d'`Either`, pas de use case systématique, DI explicite au lieu du service locator, et les tests que la série B n'a jamais écrits.

Contexte à connaître : le blog Reso Coder est quasi mort (dernier article 2024-12-02, avant cela 2023-12-05 puis 2022-04-22), et `resocoder.academy` ne liste publiquement qu'un seul produit (Flutter Developer Bootcamp, instructor-led). Le contenu du dashboard n'a pas été récupéré : il est derrière authentification, et scraper un compte personnel payant n'a pas été fait sans accord explicite.

**Décision de la spec** : le pack expose **deux profils d'architecture**, pas un dogme.

| Profil | Cible | Couches | Erreur | Quand |
|---|---|---|---|---|
| `mvvm` (défaut) | doctrine Google officielle | UI (View + ViewModel) → Data (Repository + Service), Domain optionnel | `sealed Result<T>` maison | app produit, équipe mixte, time-to-market |
| `ddd` | tactique complet | Presentation → Application → Domain ← Infrastructure | `sealed Result<T>` ou `fpdart` si l'équipe veut les monades | domaine métier riche, invariants forts, longévité |

Les deux profils partagent le même noyau non négociable : flux de données unidirectionnel, aucune logique métier dans un `Widget`, repositories abstraits, modèles immuables, erreurs typées et non des exceptions qui traversent, aucune dépendance du domaine vers Flutter.

Rationale du défaut sur `mvvm` : c'est la doctrine officielle, elle est documentée, échantillonnée (`compass_app`) et elle admet explicitement que la couche Domain est optionnelle. Imposer le DDD tactique complet à toute app Flutter est le même travers que le pack VGV commet dans l'autre sens en imposant ses 4 couches sans alternative. Le profil `ddd` reste un choix explicite, pas un défaut subi.

### 1.5 Choix de packages : ce qui est vivant, ce qui est mort

**Paris sains** (versions et publishers vérifiés sur pub.dev au 2026-08-08) :

| Rôle | Package | Version | Publisher vérifié |
|---|---|---|---|
| Lints baseline | `very_good_analysis` | 10.3.0 | VGV |
| Plugin analyzer maison | `analysis_server_plugin` | ^0.3.0 | dart.dev |
| Frontières de couches | `import_lint` | 2.0.0 | kawa.dev |
| State (option A) | `flutter_bloc` / `bloc` | 9.1.1 / 9.2.1 | bloclibrary.dev |
| State (option B) | `flutter_riverpod` | 3.4.2 | dash-overflow.net |
| Mocking | `mocktail` | 1.0.5 | felangel.dev |
| Golden | `alchemist` | 0.14.0 | betterment.dev |
| Nav | `go_router` | (SDK-aligné) | flutter.dev |
| Monorepo | `melos` | 8.2.2 | Invertase |
| CLI/scaffold | `very_good_cli` | 1.3.0 | VGV |

`very_good_analysis` 10.3.0 : **212 règles**, autonome (n'inclut ni `lints` ni `flutter_lints`), plus `strict-casts`, `strict-inference`, `strict-raw-types` à `true`, plus `formatter: trailing_commas: preserve`. À comparer : `flutter_lints` 6.0.0 = 49 règles, `lints/recommended` = 39, `lints/core` = 22. **very_good_analysis est 4x plus strict que le baseline Flutter et versionne son fichier** (`analysis_options.10.3.0.yaml`), donc reproductible. C'est le baseline à recommander.

**Morts ou mourants, à interdire par règle** :

| Package | Statut |
|---|---|
| `dartz` | dernière publication 2021-12-03, SDK `<3.0.0` : **ne compile pas sur Dart 3**. Flag `isDiscontinued` à `false`, donc indétectable par un check naïf de pub.dev. |
| `kt_dart` | 1.1.0 (2023-03-20), SDK `<3.0.0` : incompatible Dart 3 |
| `data_connection_checker` | 0.3.4 (**2019-06-09**), 471 dl/30j, `is:dart3-incompatible` |
| `custom_lint` | runner archivé 2026-03-24, bloqué en 0.8.1 |
| `architecture_lints` | bâti sur custom_lint, 2 likes, 312 dl |
| `golden_toolkit` | **discontinued** sur pub.dev, ~3 ans |
| `dart_code_metrics` (OSS) | **discontinued**, freeze 2023-07-16 |
| `oxidized` | 2 ans sans publication |

Leçon d'outillage à consigner : **la détection de package mort ne peut pas reposer sur le flag `discontinued` de pub.dev.** `dartz` est mort et le flag est à `false`. Le signal fiable est la contrainte SDK (`<3.0.0` sur un projet Dart 3) plus la date de dernière publication. DART011 teste les deux.

Note freezed : version actuelle **3.2.5** (2026-02-03). Migration 2 vers 3 en deux points : les classes doivent être `abstract`, `sealed`, ou implémenter `_$MyClass` manuellement (donc **`sealed` pour les unions**, `abstract` pour les modèles à constructeur unique) ; et `map`/`when` sont à remplacer par le `switch` Dart 3. Nuance : `map`/`when` ont été supprimés en 3.0.0 puis **réintroduits en 3.1.0** (2025-07-02) comme *"(Legacy) Pattern matching utilities"*. Ils fonctionnent encore, la doc dit de migrer. Un `4.0.0-dev.3` existe : ne pas y toucher.

`mockito` 5.8.1 n'est **pas** mort (publié par dart.dev, activement maintenu) mais exige `build_runner` via `@GenerateNiceMocks`. `mocktail` est le défaut communautaire (2.89M dl/semaine) et ne demande aucun codegen. Le pack recommande `mocktail` en `warn`, pas en `block` : une équipe avec convention mocks générés a le droit.

`provider` 6.1.5+1 n'est **pas** déprécié (certitude 75 pour cent, aucun avis officiel trouvé), reste Flutter Favorite et reste recommandé par les docs officielles pour la DI, malgré une cadence de release stale face à Riverpod.

**Point de contexte important : les macros Dart sont annulées.** Annonce officielle de l'équipe Dart du 2025-01-29 (`dart.dev/blog/an-update-on-dart-macros-data-serialization`) : arrêt indéfini, les macros devaient se ré-exécuter pendant la compilation incrémentale et détruisaient le Hot Reload. **Aucun remplaçant livré.** `build_runner` (^2.6.0) reste obligatoire pour tout codegen annoté. La stratégie de repli officielle est de livrer des features de langage réduisant le besoin de codegen : dot shorthands (3.10), private named parameters (3.12), primary constructors (3.12, expérimental derrière `--enable-experiment=primary-constructors`). Ne pas écrire de doctrine qui suppose des macros.

---

## 2. Phase 0 : ouvrir le seam (prérequis bloquant)

### 2.0 Ce qui fonctionne déjà, et qu'il ne faut pas refaire

Deux des trois couches du mécanisme sont config-driven, implémentées et opérantes. Toute proposition qui les réécrirait serait du gaspillage.

**Couche 1, activation des packs : config-driven, fonctionne.** `pack_loader_init` (`hooks/lib/pack-loader.sh:166-192`) parcourt `packs/` et n'appelle `_load_pack` que si `_pack_stack_compatible` (`:81-99`) accepte. Cette fonction lit `config_stack` du projet et la compare à `compatibility.stack` du manifeste, avec `*` comme joker. Un pack non compatible n'est jamais sourcé. Les packs externes déclarés par `config_external_packs` passent par le même filtre. Le contrat est déjà là : un pack déclare pour quelles stacks il vaut, l'utilisateur déclare sa stack, l'intersection décide.

**Couche 2, sévérité des règles : config-driven, fonctionne, à condition de passer par `add_violation`.** `add_violation` (`hooks/post-write-check.sh:204-226`) appelle `rules_severity_for_file "$file_path" "$rule"`, retourne immédiatement si la sévérité résolue vaut `ignore`, et consulte `file_has_ignore`. C'est exactement le mécanisme à trois niveaux Global → Projet → Répertoire annoncé par le produit, et il opère réellement.

Preuve d'exécution, `CLAUDE_PLUGIN_ROOT` positionné, fixture Python violant PY004 et PY005 :

```
🚫 BLOCKED by AI Craftsman - 2 violation(s):
  ✗ PY004: line 4: Bare 'except:' - catch specific exceptions
  ✗ PY005: line 1: Mutable default argument - use None + assignment
PY_HOOK_EXIT=2
```

Le pack `python` a été chargé parce que son `compatibility.stack` contient `fullstack`, ses validateurs ont été sourcés, `pack_validate_python` a été trouvée par `type`, et la sévérité a été résolue par le rules engine. La chaîne complète fonctionne pour un langage que le `case` connaît.

**Couche 3, routage fichier vers validateur : câblé en dur.** C'est le seul maillon défaillant, et il s'exécute avant les deux autres.

### 2.1 Le problème, factuellement

`pack_run_validators` (`hooks/lib/pack-loader.sh:195-202`) résout dynamiquement `pack_validate_<lang>`. Aucun appelant ne dérive `<lang>` d'un manifeste. Tous les call sites sont des `case "$EXT"` littéraux, dupliqués verbatim.

Inventaire des touchpoints (références de ligne au commit `9e894d5`, **à revérifier au moment de l'implémentation**) :

**Dispatch par extension, 6 fichiers, 13 occurrences :**

| Fichier | Lignes |
|---|---|
| `hooks/post-write-check.sh` | 264, 298 |
| `hooks/file-changed.sh` | 31, 61 |
| `hooks/pre-write-check.sh` | 27 |
| `hooks/subagent-quality-gate.sh` | 133 |
| `hooks/agent-ddd-verifier.sh` | 29 |
| `hooks/agent-final-review.sh` | 30 |
| `hooks/lib/static-analysis.sh` | 56 |
| `ci/craftsman-ci.sh` | 474, 481, 540, 582 |

**Registres annexes à ouvrir :**

| Fichier | Ligne | Défaut |
|---|---|---|
| `hooks/lib/config.sh` | 60-80 | `config_php_enabled` / `config_ts_enabled` : design à deux langages, pas de troisième exprimable |
| `ci/doctrine-export.sh` | 26-36, 40+ | doctrine en dur, alors que `pack.yml → rules.builtin` existe et n'est lu que par `scripts/validate-pack.sh:183` |
| `hooks/lib/structural_metrics.py` | 148 | binaire `php` contre regex TS |
| `hooks/lib/hotspot_analysis.py` | 31-34, 96 | `LANG_BY_EXT` sans `.dart` ; `if lang in ("php","ts")` |
| `hooks/lib/codemap.py` | 17-23 | `ENTRY_MARKERS` sans `pubspec.yaml` |
| `hooks/lib/ratchet.py` | 39-55 | `FN_RE` ne matche ni `Foo({required this.x})` ni les méthodes `@override` |
| `hooks/config-protection.sh` | 30-38 | pas de `analysis_options.yaml` ni `pubspec.yaml` |
| `hooks/lib/healthcheck.sh` | 167-176 | sondes LSP sans `dart language-server` |
| `hooks/lib/routing-table.sh` | 33, 39, 43 | `grep -q "symfony"` / `"react"` / `"ai-ml"` en littéraux |
| `hooks/post-bash-test-verify.sh` | 26 | regex de détection de test sans `flutter test` ni `dart test` |
| `teams/templates/code-review.yml` | 18, 21, 27 | `agent: symfony-reviewer` en dur |
| Skills | `setup`, `verify`, `team`, `ci`, `scaffold` | détection de stack en prose (`Glob("composer.json")`) |

**Conséquence déjà réelle, démontrée par exécution.** Le `find` de `scan_paths` ne ramasse que `-name "*.php" -o -name "*.ts" -o -name "*.tsx"`, et `scan_file` (`:481-503`) retourne 0 sur tout le reste via son `*)`. Deux barrages indépendants pour le même effet : les packs `python` et `bash` ne tournent **jamais** en CI.

Même fixture Python que ci-dessus, passée cette fois au pipeline, dans un répertoire contenant en plus un `.php` conforme :

```
craftsman-ci v4.3.3 - Quality Gate
Config: strict, fullstack

No issues found in 1 file(s).
```

**Le hook sort 2 et bloque. La CI sort vert sur le même fichier.** C'est la rupture de parité, constatée, pas déduite.

Le détail qui aggrave : sans le `.php`, la CI affiche *"craftsman-ci: no source file was found, so this is not a pass"*. Ce garde-fou anti-vert-silencieux est excellent et il fonctionne. Mais `FILES_DISCOVERED` ne s'incrémente que sur `php|ts|tsx` (`:474`), donc **un seul fichier PHP dans le dépôt suffit à le faire taire**, et tout le Python et le Bash passent alors en silence. Le compteur conçu pour détecter le gate jamais exécuté porte lui-même le bug qu'il prévient.

`CLAUDE.md` et `README.md:65` affirment l'inverse (*"CI sources the same pack validators... the parity tests fail when two front-ends disagree"*). Ce dépôt est lui-même à 124 fichiers `.sh` et 18 `.py` : c'est le dogfooding qui saute en premier.

**Défaut distinct, découvert en vérifiant le précédent** : `add_warning` (`hooks/post-write-check.sh:228-234`) **court-circuite entièrement le rules engine**. Pas d'appel à `rules_severity_for_file`, pas de `file_has_ignore` : la sévérité est gelée au site d'appel dans le validateur. Conséquence vérifiée sur SH001, déclaré règle bloquante dans `ci/doctrine-export.sh:31` (`DOCTRINE_RULES_SH="SH001 SH002 SH003 SH004 SH005"`) mais émis par `add_warning` dans `packs/bash/hooks/bash-validator.sh:71`. Résultat : SH001 ne peut jamais bloquer, ne peut jamais être relaxé par un `.craft-rules.yml` de répertoire, et ne peut jamais être mis à `ignore`. La configuration utilisateur n'a aucune prise sur lui, dans les deux sens.

C'est le même défaut de fond que le `case "$EXT"` : une décision qui devrait venir de la configuration est figée dans le code. Un pack Flutter qui appellerait `add_warning` hériterait du problème.

**Le garde-fou existant teste le mauvais consommateur** : `tests/core/test-external-packs.sh:74-77` assert que `pack_validate_go` est *callable* après chargement. Il ne vérifie jamais qu'elle est *appelée* sur un fichier `.go`. Il reste vert pendant que la fonctionnalité est morte. Cas d'école du principe "valider l'artefact par son consommateur réel".

### 2.2 Livrables de Phase 0

| # | Livrable | Critère d'acceptation |
|---|---|---|
| P0-1 | `pack.yml` déclare `languages: [{id, extensions, validators, static_analysis}]` | schéma `schemas/pack.schema.json` mis à jour, `validate-pack.sh` le vérifie |
| P0-2 | `hooks/lib/lang-dispatch.sh` expose `lang_for_extension()` et `pack_dispatch_file()` | les 13 `case "$EXT"` réduits à un appel, y compris depuis `ci/craftsman-ci.sh` |
| P0-3 | `ci/craftsman-ci.sh` dérive sa liste `find` du même registre | Python et Bash tournent en CI ; parité restaurée |
| P0-4 | `config_lang_enabled "<lang>"` remplace la paire `config_php_enabled`/`config_ts_enabled` | `compatibility.stack` devient porteur au lieu d'être un filtre |
| P0-5 | `ci/doctrine-export.sh` agrège les `rules:` des packs chargés | un pack peut déclarer ses IDs sans éditer le core |
| P0-6 | `tests/core/test-external-packs.sh` réécrit : fixture `.go` réelle, passage par le dispatcher, violation attendue en sortie | **le test doit être rouge avant le fix** : c'est la preuve que le défaut est réel |
| P0-7 | `tests/ci/test-parity.sh` étendu : pour chaque langage déclaré par un pack chargé, hook et CI produisent la même sévérité | rouge aujourd'hui sur `python` et `bash` |
| P0-8 | ADR-0028 : dispatch de langage piloté par manifeste | consigne la dette et la sortie |
| P0-9 | `docs/guides/authoring-a-pack.md` | le contrat de `pack.yml` cesse d'être déductible uniquement en lisant `pack-loader.sh` |
| P0-10 | `skills/scaffold/SKILL.md:92` : le meta-type `pack` génère un manifeste `languages:` valide | `/craftsman:scaffold pack my-go-pack` produit un pack qui **exécute** quelque chose |
| P0-11 | `add_warning` résout sa sévérité par `rules_severity_for_file`, comme `add_violation` | SH001 devient configurable et respecte `ignore` ; un test le prouve en le passant de `warn` à `block` puis à `ignore` par `.craft-rules.yml` |
| P0-12 | `FILES_DISCOVERED` (`ci/craftsman-ci.sh:474`) compte toute extension déclarée par un pack chargé | le garde-fou anti-vert-silencieux cesse d'être aveugle aux langages qu'il est censé couvrir |

Point annexe : `pack-loader.sh:30-79` fait du `grep|sed` maison alors que `hooks/lib/yaml-parser.py` existe et sert au rules engine. Le parseur shell ne lit que les tableaux inline `[a, b]`, pas les séquences en bloc. Un contributeur qui écrit du YAML idiomatique obtient un pack silencieusement vide. **P0-1 impose des structures imbriquées : ce parseur doit être remplacé par `yaml-parser.py`, ce n'est pas optionnel.**

Note sur `config/default-config.yml` (lignes 14-17) : son bloc `packs:` ne liste que `core`, `symfony`, `react`. Il est périmé et n'est lu par aucun code du runtime (`pack_loader_init` découvre par le système de fichiers). Ne pas y ajouter `flutter` en croyant activer quoi que ce soit.

---

## 3. Phase 1 : le pack Flutter

### 3.1 Manifeste

```yaml
name: flutter
version: "1.0.0"
description: "Flutter/Dart craftsman pack - Flutter 3.44, Dart 3.12, MVVM ou DDD, very_good_analysis"
compatibility:
  core: ">=5.0.0"
  stack: ["flutter", "mobile", "fullstack"]

languages:
  - id: dart
    extensions: ["dart"]
    entry_markers: ["pubspec.yaml"]
    config_files: ["analysis_options.yaml", "pubspec.yaml"]
    validators: ["hooks/dart-validator.sh", "hooks/flutter-layer-validator.sh", "hooks/flutter-widget-validator.sh", "hooks/dart-security-validator.sh"]
    static_analysis: ["static-analysis/dart-analyze.sh", "static-analysis/import-lint.sh"]
    test_commands: ["flutter test", "dart test", "very_good test", "patrol test"]
    lsp: "dart language-server"

rules:
  builtin: ["DART001", "DART002", "DART003", "DART004", "DART005", "DART006", "DART007", "DART008", "DART009", "DART010", "DART011", "DART012", "DART013", "DART014", "DART015", "DART016", "LAYER001", "NEST001", "LOC001", "GOD001", "PARAM001"]
  static_analysis: ["ANALYZER001", "ANALYZER002", "ANALYZER003", "ANALYZER004", "IMPORTLINT001"]

profiles:
  architecture: ["mvvm", "ddd"]   # défaut: mvvm
  state: ["riverpod", "bloc"]     # défaut: riverpod, TOUJOURS écrasé par la détection pubspec.yaml

commands:
  scaffold_types: ["feature", "viewmodel", "repository", "value-object", "widget", "bloc", "notifier"]

agents: ["agents/flutter-craftsman.md", "agents/flutter-reviewer.md"]
knowledge: ["knowledge/"]
templates: ["templates/"]
```

### 3.2 Catalogue de règles Level 1 (regex, hook Write/Edit, cible <50ms, zéro outil requis)

Ces règles tournent **sans SDK Dart installé**. C'est la condition de dégradation gracieuse déjà tenue par les autres packs.

| ID | Règle | Sévérité | Détection | Rationale |
|---|---|---|---|---|
| DART001 | pas de `dynamic` | block | `\bdynamic\b` hors commentaire, hors `.g.dart`/`.freezed.dart` | miroir exact de TS001 (`any`) |
| DART002 | pas de null assertion `!` | block | `\w[!](?!=)` hors chaînes, hors tests | miroir TS ; `!` est le `any` du null-safety |
| DART003 | pas de setter public | block | `set\s+[a-z]\w*\s*\(` sur classe non-Widget | méthodes comportementales, doctrine PHP transposée |
| DART004 | classe `final` par défaut | warn | `^\s*class\s+\w+` sans `final`/`sealed`/`abstract`/`base`/`interface`/`mixin`, hors `part of` | recommandé par dart.dev **en prose uniquement**, aucun lint ne l'applique |
| DART005 | pas de `print()` en `lib/` | block | `\bprint\s*\(` | logger injecté |
| DART006 | pas d'I/O dans un `Widget` | block | fichier contenant `extends (Stateless\|Stateful)Widget` **et** import de `package:http`, `dio`, `cloud_firestore`, `shared_preferences`, `sqflite` | la pathologie Flutter numéro un |
| DART007 | pas de `DateTime.now()` | block | `DateTime\.now\(\)` hors tests | Clock injecté, miroir exact de la règle PHP |
| DART008 | pas de catch vide | block | `catch\s*\([^)]*\)\s*\{\s*\}` ou `on\s+\w+\s*\{\s*\}` | miroir PHP |
| DART009 | pas de `late` mutable | warn | `late\s+(?!final)` hors tests | `late` non-final est une NPE différée |
| DART010 | pas d'import de `src/` cross-package | warn | `import\s+'package:(?!<self>)[^']*\/src\/` | barrel exports aux frontières |
| DART011 | pas de package mort | block | import ou entrée pubspec de `dartz`, `kt_dart`, `data_connection_checker`, `golden_toolkit`, `dart_code_metrics`, `custom_lint`, `architecture_lints`, `oxidized` | voir 1.5. Ne **pas** se fier au flag `discontinued` de pub.dev : tester la contrainte SDK et la date de publication. |
| DART012 | `analysis_options.yaml` doit inclure `very_good_analysis` | warn | absence de `include: package:very_good_analysis` | 212 règles contre 49 pour `flutter_lints` |
| DART013 | pas d'API bloc supprimée | block | `mapEventToState`, `get initialState`, `BlocOverrides` | supprimés en bloc 8.0.0 (2021-11-18) et 9.0.0. Le code ne compile pas. |
| DART014 | union `freezed` doit être `sealed` | warn | `@freezed\s+abstract class` avec plus d'une `const factory` | freezed 3.x exige `abstract`, `sealed` ou `implements _$X` ; `map`/`when` sont legacy, `switch` est la cible |
| DART015 | pas de check de connectivité avant appel | warn | `isConnected` ou `checkConnectivity` évalué en garde d'un appel réseau dans un repository | race condition entre le check et l'appel, faux positif sur portail captif. Faire l'appel, gérer l'échec. |
| DART016 | pas de service locator hors composition root | block | `getIt<`, `GetIt.instance`, `sl<` dans `lib/domain/**`, `lib/infrastructure/**`, `lib/data/**` | défaut réel du dépôt Reso Coder DDD : rend le code intestable sans conteneur global |

Réutilisées du core (une fois `structural_metrics.py` étendu à Dart, voir 3.4) : LAYER001, NEST001, LOC001, GOD001, PARAM001.

**Suivant le principe de la table des faux remèdes** (le meilleur pattern de rédaction repris du plugin VGV), chaque règle bloquante est livrée avec les contournements qu'elle refuse. Exemple pour DART001 :

| Contournement proposé | Pourquoi c'est le même défaut |
|---|---|
| `// ignore: avoid_dynamic` | supprime le signal, pas la cause |
| `Object?` à la place | correct, et c'est le fix : `Object?` force le narrowing, `dynamic` le supprime |
| `dynamic` dans un DTO de désérialisation | la frontière JSON se type avec `Map<String, Object?>` puis un factory `fromJson` validant |
| `dynamic` "temporaire" | un `TODO` non daté sur une règle `block` est un contournement, pas un plan |

### 3.3 Level 2 : `dart analyze --format=machine`

`packs/flutter/static-analysis/dart-analyze.sh` :

1. Détecte le SDK. Absent : `exit 0` silencieux, Level 1 reste actif (dégradation gracieuse).
2. `dart analyze --format=machine --fatal-infos=false <path>`.
3. Parse les 8 colonnes en gérant l'échappement backslash de `|` et `\`.
4. Mappe vers les IDs du rules engine :

| ID | Mapping | Sévérité par défaut |
|---|---|---|
| ANALYZER001 | `SEVERITY=ERROR` | block |
| ANALYZER002 | `SEVERITY=WARNING` | block |
| ANALYZER003 | `SEVERITY=INFO`, `TYPE=LINT` | warn |
| ANALYZER004 | `analysis_options.yaml` absent ou non parsable | warn |
| IMPORTLINT001 | code émis par le plugin `import_lint` | block |

5. La sévérité finale passe par `rules-engine.sh`, donc un `.craft-rules.yml` de répertoire peut relaxer sur du legacy. C'est le différenciateur numéro 2 du produit, appliqué à Dart : `dart analyze` seul ne sait pas relaxer par dossier.

Frontières de couches via `import_lint` 2.0.0 (nouveau système de plugin, Dart 3.10+), généré par profil :

```yaml
# profil ddd
import_lint:
  rules:
    domain_is_pristine:
      target: "lib/domain/**"
      from: "lib/{infrastructure,application,presentation}/**"
    domain_no_flutter:
      target: "lib/domain/**"
      from: "package:flutter/**"
    presentation_skips_no_layer:
      target: "lib/presentation/**"
      from: "lib/infrastructure/**"
```

```yaml
# profil mvvm
import_lint:
  rules:
    view_no_data:
      target: "lib/ui/**/widgets/**"
      from: "lib/data/**"
    viewmodel_no_service:
      target: "lib/ui/**/view_models/**"
      from: "lib/data/services/**"
    repositories_are_islands:
      target: "lib/data/repositories/**"
      from: "lib/data/repositories/**"
```

Réserve honnête : `import_lint` est mature techniquement mais faiblement adopté (28 likes, 4.7k dl/semaine). Repli si l'adoption ne suit pas : écrire la règle de frontière dans notre propre plugin analyzer (environ 100 lignes de Dart avec `AnalysisRule` + `SimpleAstVisitor`), ce qui donne en prime le contrôle du format de sortie.

### 3.4 Métriques structurelles : où se gagne la différenciation

`hooks/lib/structural_metrics.py:148` est aujourd'hui un binaire `php` contre regex TS. Dart prendrait la voie TypeScript : acceptable pour NEST001, LOC001 et GOD001, approximatif pour PARAM001 (les paramètres nommés Dart `({required this.x})` ne matchent pas proprement, et `ratchet.py:39-55` a le même angle mort sur les constructeurs et les méthodes `@override`).

Deux options, dans cet ordre :

**Option A, v1 (recommandée) : étendre `structural_metrics.py` et `ratchet.py` à Dart.** Coût faible, réutilise le ratchet existant, **zéro install côté utilisateur**, cohérent avec la contrainte zero-install du projet. Précision suffisante pour NEST/LOC/GOD, à calibrer explicitement pour PARAM001 sur les paramètres nommés et `required this.x`.

**Option B, v2 : publier `craftsman_dart_lints` sur pub.dev**, plugin analyzer first-party exposant complexité cyclomatique, LOC/méthode, nombre de paramètres, profondeur d'imbrication, absence de `else`, et `final class by default`. API : `analysis_server_plugin: ^0.3.0`, `analyzer_plugin: ^0.13.0`, `analyzer: ^8.0.0`, `Plugin` + `registry.registerWarningRule` + `AnalysisRule` + `SimpleAstVisitor` + `reportAtNode`. Quick fixes via `ResolvedCorrectionProducer` + `ChangeBuilder`.

**Ce que l'option B vaut** : ces métriques n'existent en gratuit nulle part dans l'écosystème Dart depuis la mort de `dart_code_metrics` en 2023, et DCM les facture 80 dollars/mois dès qu'on veut les mettre en CI. C'est le seul endroit de cette spec où le plugin peut livrer quelque chose qui n'existe pas ailleurs, pour qui que ce soit, Flutter ou pas.

Contrainte de l'option B : elle exige que le projet cible déclare le plugin dans son `analysis_options.yaml`. Ce n'est plus du zero-install, c'est une dépendance de dev déclarée. Elle doit donc rester **opt-in**, l'option A restant le chemin par défaut.

### 3.5 CI et annotations

`ci/adapters/` reçoit un mapping Dart. Le problem matcher GitHub se dérive directement des 8 colonnes :

```
::error file=<FILE_PATH>,line=<LINE>,col=<COLUMN>::<CODE>: <MESSAGE>
```

Rappel du 1.3 : **aucun setup-action Dart ou Flutter n'enregistre de problem matcher**, il n'y a pas d'émetteur SARIF first-party, et l'intégration CI de DCM est payante. Une annotation inline gratuite sur PR est donc une capacité que le pack apporte, pas une commodité qu'il enveloppe.

Le workflow généré s'aligne sur `VeryGoodOpenSource/very_good_workflows/.github/workflows/flutter_package.yml@v1` pour l'ordre des étapes (format, analyze, bloc lint, test + coverage + seuil) mais **ne délègue pas** : `craftsman-ci.sh` doit rester la source de vérité de la sévérité, sinon la parité hook/CI se casse au premier `.craft-rules.yml` de répertoire.

`min_coverage` : VGV met **100 par défaut** dans ses workflows, et leur politique 100 pour cent est corroborée par le code (pas seulement par un billet de blog de 2023). Le pack propose **80 par défaut, 100 opt-in**, avec les exclusions standard `**/*.{g,freezed,gen}.dart` plus l10n. Rationale : 100 pour cent sur `lib/` complet transforme la couverture en objectif au lieu d'un signal, ce que la doctrine de test du projet (pyramide 70/20/10, tester le comportement) rejette explicitement. Exclusions LCOV via `// coverage:ignore-file` / `ignore-line` / `ignore-start`/`ignore-end`, ou post-traitement `lcov --remove`.

### 3.6 Boucle de vérification déterministe

`hooks/post-bash-test-verify.sh:26` doit reconnaître `flutter test`, `dart test`, `very_good test`, `patrol test`, sinon ADR-0023 ne se déclenche jamais sur un projet Flutter et "les tests passent" redevient une affirmation non vérifiée.

Sharding disponible : `flutter test --total-shards N --shard-index i` (certitude 85 pour cent, confirmé via issue GitHub, pas via doc first-party). `--experimental-faster-testing` : ne pas recommander, problèmes de perf documentés sur grosses suites (flutter/flutter#146603).

E2E : `integration_test` du SDK en baseline. `patrol` 4.8.0 (leancode.co, API `platform` remplaçant `native`/`native2` dépréciées) comme option, **avec avertissement CI explicite** : plusieurs sources 2026 indépendantes et cohérentes signalent une instabilité en CI (certitude 80 pour cent). Budgéter du debug. Ne pas le mettre en défaut.

Golden : `alchemist` 0.14.0, `golden_toolkit` étant discontinued. Pratique CI à documenter : épingler un seul OS (Linux x64) pour éviter la dérive pixel.

### 3.7 Agents, knowledge, templates

**`agents/flutter-craftsman.md`** : génère du code conforme au profil actif. Contrat de sortie strict.

**`agents/flutter-reviewer.md`** : reprend le meilleur pattern du plugin VGV, à savoir le **contrat de sortie tabulaire** (exactement un tableau, colonnes `location | problem | fix | standard`, jamais de tableau vide, jamais de finding inventé, plus une note obligatoire sur les zones hors périmètre chargé). Différence assumée avec VGV : il **ne remonte pas** les findings `dart analyze`, qui sont déjà couverts mécaniquement par ANALYZER001-003. Un agent qui reformule ce qu'un hook a déjà bloqué produit du bruit.

**`knowledge/canonical/`** : `dart-value-object.dart` (validation en `factory`, constructeur privé, `sealed` au lieu d'`Either`), `dart-result-sealed.dart`, `dart-repository.dart`, `dart-viewmodel-command.dart`, `dart-bloc-sealed.dart`, `dart-riverpod-notifier.dart`, `dart-widget-dumb.dart`, `dart-watcher-actor-cqrs.dart` (la séparation lecture réactive / commande, le meilleur apport non nommé de Reso Coder).

**`knowledge/anti-patterns/`** : `logic-in-widget.md`, `setstate-as-state-management.md`, `bloc-as-service-locator.md`, `dynamic-escape-hatch.md`, `either-overuse.md` (pourquoi `sealed Result` bat `Either` dans 90 pour cent des cas, et pourquoi `dartz` n'était qu'un véhicule pour l'absence de `sealed` avant Dart 3), `usecase-per-method.md`, `service-locator-in-infrastructure.md` (le défaut réel de `firestore_helpers.dart` chez Reso Coder), `network-check-before-call.md` (`NetworkInfo.isConnected` en garde : race condition et portail captif), `model-extends-entity.md` (l'héritage couple la sérialisation au domaine ; la doc Flutter classe la séparation modèle API / modèle domaine en *"Conditional: use in large apps"*), `getorcrash-outside-boundary.md`, `dead-packages.md`.

**`templates/`** : `mobile-app.template.md` (profil mvvm), `mobile-ddd.template.md` (profil ddd), `flutter-package.template.md`. Chaque template respecte le contrat existant : heading de niveau 1, `## Mission`, `## Context Files`.

**Aucune version de package en dur dans les fichiers `knowledge/` et `templates/`.** Leçon directe du plugin VGV : ses fichiers de référence portent `sdk: ^3.11.0` et `flutter: ^3.29.0` dans le même bloc `environment` (Flutter 3.29 n'embarque pas Dart 3.11), c'est-à-dire exactement l'erreur que sa propre skill d'upgrade désigne comme *"the single most common error in this change"*, commise deux fois dans son propre exemple canonique. Le pack porte ses versions dans **un seul fichier** `packs/flutter/versions.yml`, daté, et un test vérifie qu'aucun `^3.` ne traîne ailleurs.

---

## 4. Ce qu'on reprend du plugin VGV, ce qu'on rejette

Audit de `~/Dev/claude-plugin-lab/vgv-ai-flutter-plugin` v0.0.5 : 126 fichiers, 9 301 lignes de markdown dans `skills/`, 5 804 dans `evals/`. Repo documentation-only : zéro Dart, zéro `pubspec.yaml`, zéro test unitaire hors 2 scripts bash.

### À reprendre

| Élément | Pourquoi |
|---|---|
| **Harnais d'evals à deux colonnes** | rejouer chaque prompt avec et sans le plugin, et déclarer qu'un grader qui passe dans les deux colonnes mesure le modèle et pas la skill. Seule méthode honnête pour savoir si une skill sert à quelque chose. Transposable tel quel à PHP/React/Python à coût faible, et ça répond à une question qu'aucun plugin de skills ne se pose. |
| **Pattern "refus + livraison de l'alternative dans la même réponse"** | formulé de façon non ambiguë : *"an offer is not a replacement"*, *"a tidier conditional is the same defect with better formatting"*. Directement transposable : on demande un setter, on livre la méthode comportementale, pas le setter commenté. |
| **Table des faux remèdes** | anticiper les cinq contournements que le développeur va proposer et les réfuter un par un avec la raison technique. Très supérieur à "ne hardcode pas de secret". Repris en 3.2. |
| **`allow-readonly-git.sh`** | rejet préalable de tout opérateur shell **puis** whitelist, plutôt que blacklist sur le premier token. Défense en profondeur correcte, testée sur les bypasses par composition. À reprendre tel quel pour tout agent read-only. |
| **Contrat de sortie tabulaire du reviewer** | ce qui rend une sortie d'agent consommable par un orchestrateur. Repris en 3.7. |
| **Séparation `SKILL.md` / `references/` avec chargement à la demande** | leur skill `accessibility` fait 318 lignes en SKILL.md pour 2 147 au total, dont 6 fichiers plateformes chargés seulement si la plateforme est sélectionnée. Bonne économie de contexte. |
| **Spec de boucle `green-gate`** | fingerprint par gate, no-progress contre oscillation, précédence stricte, "never cache green", cap par package. *"A standing instruction to keep going does not override a trigger"* est exactement la règle qu'il faut. À réimplémenter **avec état persisté**, voir ci-dessous. |
| **Le couplage explicite règle-markdown vers script d'enforcement** | leur skill pointe le script qui la rend vraie. Bon patron, appliqué une seule fois sur quinze skills. |

### À rejeter

| Élément | Pourquoi |
|---|---|
| **Le modèle d'enforcement** | 95 pour cent prompt, 5 pour cent mécanique, et le 5 pour cent mécanique ne valide **aucune** des règles doctrinales. `grep -r "mockito" hooks/` retourne vide alors que la skill écrit "never `package:mockito`". Zéro regex métier dans tout `hooks/`. Aucune règle nommée, aucune sévérité, aucun override projet ou répertoire, aucune métrique, aucun apprentissage. |
| **`layered-architecture` telle quelle** | pas de Domain isolé, pas de ports, pas de Value Objects. C'est du "Repository + DTO mapping", pas du DDD. Voir 1.4. |
| **Les versions de packages dans les fichiers de référence** | pourrissent et se contredisent déjà entre skills (`very_good_analysis` `^7.0.0` d'un côté, `^10.0.0` de l'autre). Voir 3.7. |
| **L'état de boucle dans le contexte du modèle** | `green-gate` gère un fingerprint, un compteur d'itérations, une détection d'oscillation et un cap de 5 : **tout cela vit dans le contexte**, pas dans un état persisté. Une compaction efface la machine à états. Ce plugin a déjà `session-state.json` avec écriture atomique : c'est là que ça va. |
| **Le "wishful prompting"** | *"Declaring success from memory is forbidden; confirm success only with the actual numbers observed"* est précisément le comportement qu'un LLM échoue à tenir, et rien ne peut constater qu'il a menti. ADR-0023 (boucle de vérification déterministe) existe pour ça et doit couvrir Dart, voir 3.6. |
| **15 skills toutes model-invocables** | descriptions longues, zones de recouvrement réelles, empreinte permanente dans le skill listing. La politique d'invocation de ce projet (`tests/core/test-invocation-policy.sh`) est plus saine. |

### Sur leurs evals, une réserve à ne pas répéter

Leur suite mesure le **routage** et le **vocabulaire**, pas la correction : 164 `llm-rubric` sur 502 assertions sans gold set annoté, et l'assertion custom `dart-parses.js` ne fait que `dart format --output=none`, donc elle prouve la syntaxe et rien d'autre. **Aucune assertion ne fait tourner `dart analyze` ni les tests sur le code généré.** Un snippet syntaxiquement valide, sémantiquement faux et violant trois standards passe s'il contient les bons mots.

Leur propre documentation admet l'instabilité : même output noté 1.00 puis 0.30 sur la même rubrique, un cas "routed 3 of 3 on one pass and failed to route on the next", et la recommandation maison est `--repeat 3` avant de croire un rouge. Ils en tirent la bonne conclusion (`continue-on-error: true`, *"a single eval run is too noisy to gate on"*), et c'est le bon arbitrage.

**Si on reprend le harnais, on ajoute ce qu'il leur manque** : une assertion qui écrit le code généré dans un projet fixture et lance `dart analyze --format=machine` dessus. On a l'outil, eux ne l'avaient pas branché.

Et l'isolation de leur ablation n'est protégée par rien : les quatre clés qui tiennent la validité de toute la mesure (`tools`, `setting_sources`, `strict_mcp_config`, `plugins`) ne sont vérifiées par aucun test CI, et leur README admet *"this suite shipped leaking until a run exposed it"*. Notre version doit avoir un test qui **échoue** si la colonne sealed peut lire les skills.

---

## 5. Plan de livraison

| Phase | Contenu | Sortie |
|---|---|---|
| **P0** (livrée en v4.4.0, sauf `doctrine-export`, `routing-table`, schéma, guide, ADR) | Seam manifest-driven, parité CI, tests rouges d'abord | Python et Bash tournent en CI. `test-lang-registry.sh` teste le consommateur réel. |
| **P1** | `packs/flutter/` : manifeste, DART001-012, `dart-analyze.sh`, profils `mvvm`/`ddd`, `versions.yml` | **Critère d'acceptation du seam : `git diff --stat` ne montre rien hors de `packs/flutter/`.** |
| **P2** | Métriques Dart option A (`structural_metrics.py`, `ratchet.py`), `post-bash-test-verify.sh`, `healthcheck.sh`, `config-protection.sh`, `routing-table.sh` | NEST/LOC/GOD/PARAM actifs et ratchetés sur Dart. |
| **P3** | Agents, knowledge canonique, anti-patterns, templates, adaptateurs CI et problem matcher | Annotation inline PR gratuite, capacité absente de l'écosystème. |
| **P4** | Harnais d'evals deux colonnes avec assertion `dart analyze` sur le code généré, plus test d'isolation qui doit pouvoir passer au rouge | Mesure du lift réel, pas du vocabulaire. |
| **P5** (opt-in) | `craftsman_dart_lints` publié sur pub.dev : complexité cyclomatique, LOC/méthode, paramètres, imbrication, `final class by default` | Comble le trou laissé par `dart_code_metrics`, gratuitement. |

**Un garde-fou jamais vu rouge ne prouve rien.** Chaque règle DART00x livrée avec un fixture violant, et une réintroduction du défaut après correction pour vérifier que le check échoue.

---

## 6. Risques et réserves

| Risque | Mitigation |
|---|---|
| **YAGNI.** La stack déclarée est Symfony/React, aucun signal de demande Flutter dans le repo. | Le refactor P0 a une valeur **indépendante et supérieure** : il débloque Go, Rust, Kotlin et les packs externes tiers déjà à moitié promis par `config_external_packs`, et il répare un défaut de parité déjà présent. Si Flutter est abandonné, P0 reste rentable. Si un projet Flutter concret démarre, le pack passe devant et P0 reste un prérequis, pas un suivant. |
| `import_lint` faiblement adopté (28 likes) | repli documenté : règle de frontière dans notre propre plugin analyzer, environ 100 lignes |
| Le nouveau système de plugins analyzer est jeune (nov 2025) | pas d'assists encore (roadmap), pas de `TypeChecker`. À vérifier avant P5. |
| Versions Flutter/Dart qui pourrissent | `versions.yml` unique et daté, plus un test interdisant les contraintes de version hors de ce fichier |
| Le formatter "tall style" (Dart 3.7) ajoute et retire les trailing commas automatiquement | ne jamais écrire de règle sur les trailing commas. `very_good_analysis` 10.3.0 met `formatter: trailing_commas: preserve`, c'est le signal de ce que fait l'industrie. |
| Deux profils d'architecture doublent la surface de doctrine | le noyau non négociable (1.4) est partagé ; seuls les noms de dossiers et la présence de la couche Domain divergent |

---

## 7. Questions ouvertes pour le porteur

1. **Y a-t-il un projet Flutter concret qui démarre ?** La réponse ne change pas la recommandation P0-avant-P1, elle change la priorité relative face aux autres chantiers.
2. **Le harnais d'evals (P4) est-il un chantier transverse plutôt qu'un morceau du pack Flutter ?** Il vaut pour les 6 packs. Le sortir de cette spec et en faire son propre ADR est défendable.
3. **`~/Dev/claude-plugin-lab/vgv-ai-flutter-plugin` restera-t-il installé en parallèle ?** Si oui, prévoir la collision : leurs 15 skills sont toutes model-invocables et plusieurs recouvrent ce que ce pack fera.

---

## 8. State management : Riverpod, tranché sur les projets réels

Question résolue par mesure, pas par sondage pub.dev. Deux applications Flutter dans `~/Dev/Sport Project App` :

| | `sporthabits` | `super7` |
|---|---|---|
| State | `flutter_riverpod: ^3.3.2` | `flutter_riverpod: ^2.6.1` + `riverpod_annotation: ^2.6.1` |
| Bloc | **absent** | **absent** |
| Fichiers `.dart` dans `lib/` | 331 | 271 |
| Fichiers déclarant `Notifier` / `StateNotifier` | 16 | 24 |
| `freezed` | **absent** | absent, retiré explicitement (commentaire pubspec) |
| Nav | `go_router: ^17.3.0` | `go_router: ^13.2.4` |
| Persistance | `drift` 2.34 + Firebase | `hive_flutter` + `flutter_secure_storage` + `http` |
| Lints | `flutter_lints: ^6.0.0` (49 règles) | `flutter_lints` |
| Fichiers `*_test.dart` | 117 (~35 pour cent des fichiers de `lib/`) | **22 (~8 pour cent)** |
| Organisation `lib/` | `core/` + `features/<f>/` | `core/` + `features/<f>/` |

**Décision : `riverpod` est le défaut du pack.** 40 fichiers Notifier au total, zéro Bloc, sur deux applications indépendantes. Les statistiques pub.dev donnaient un match nul discutable (Riverpod 2.78M dl contre bloc 1.95M, mais `flutter_bloc` 8.0k likes contre 2.9k) : les projets tranchent sans ambiguïté.

**Trois observations qui changent la spec, au-delà du choix du package :**

1. **Les deux projets sont déjà feature-first** (`lib/core/` plus `lib/features/<feature>/`), donc alignés sur le consensus 2026 et sur `compass_app`. Le pack n'a pas de migration structurelle à imposer, seulement des frontières à faire respecter à l'intérieur d'une organisation déjà saine. C'est un argument fort pour le profil `mvvm` par défaut : ils y sont déjà, à ceci près que rien ne garantit les frontières aujourd'hui.
2. **Deux majeures de Riverpod coexistent, et l'API diffère.** Riverpod 3 (stable depuis 2025-09-10) fusionne `AutoDisposeNotifier` et `FamilyNotifier` dans `Notifier`, renomme `AsyncValue.valueOrNull` en `.value`, enveloppe les exceptions dans `ProviderException`, et ajoute mutations, retry à backoff exponentiel et `Ref.mounted`. `super7` est en 2.6.1 avec codegen (`riverpod_annotation`), `sporthabits` en 3.3.2 sans. **Le pack doit détecter la version majeure, pas seulement la présence du package**, sinon il génère du code qui ne compile pas dans l'un des deux dépôts. La détection lit la contrainte de `pubspec.yaml`, et à défaut `pubspec.lock`.
3. **`riverpod_lint` 3.1.8 a migré vers le nouveau système de plugin analyzer** : 14 règles et 6 assists, déclarées par `plugins: { riverpod_lint: <version> }`, exécutées dans `dart analyze`. Elles remontent donc dans le même flux `--format=machine` que tout le reste, et la spec les mappe sur ANALYZER003 sans code de parsing supplémentaire. Le pack recommande son activation en `warn`.

**Deux constats qui ne concernent pas le choix du state manager mais qui cadrent la valeur du pack :**

- Aucun des deux n'utilise `very_good_analysis`. Les deux sont sur `flutter_lints` 6.0.0, soit **49 règles au lieu de 212**. DART012 a un effet immédiat et mesurable dès la première exécution.
- `super7` est à environ 8 pour cent de fichiers testés contre 35 pour cent pour `sporthabits`. Un seuil de couverture unique appliqué aux deux serait soit inatteignable, soit inutile. C'est précisément l'argument pour l'override par répertoire du rules engine, à condition que P0-11 rende la sévérité réellement configurable pour les règles émises en warning.

**Contrainte de conception qui prime sur le défaut** : le défaut `riverpod` ne s'applique qu'au scaffolding d'un projet vierge. Sur un projet existant, **la détection l'emporte toujours**. Un pack qui imposerait Riverpod à un dépôt Bloc reproduirait exactement ce que fait le plugin VGV en imposant Bloc sans alternative. Le profil est une valeur résolue depuis le projet, pas une opinion du pack.
