# Plan v3.6 → v4.0 — AI Craftsman Superpowers : combler les gaps concurrence, piliers Refactoring & Legacy, synergies plugins

## Context

Le plugin (v3.5.0 réelle — CLAUDE.md dit 3.4.5, à resynchroniser) est fort sur l'enforcement temps réel (quality gate 3 niveaux, rules engine 3 niveaux d'héritage, correction learning, CI zéro-drift) mais présente des gaps confirmés face à la concurrence 2026 (obra/superpowers, BMAD ~49k★, UI-UX PRO MAX, dykyi-roman PHP toolkit, security-guidance Anthropic) :

- **Aucun workflow Legacy** : pas de commande takeover, pas de characterization tests / golden master, pas de seams / dependency-breaking (Feathers), pas de strangler fig, pas de hotspots churn×complexité. `/refactor` suppose une suite de tests verte.
- **Knowledge core léger** (~3 000 lignes) : aucun fichier core Clean Architecture, Hexagonale, TDD, stratégie de test, ni Legacy. Le DDD vit dans le pack symfony au lieu du core. Doublon `patterns.md`/`design-patterns.md`. Pas de SOLID par langage.
- **Packs à 2 vitesses** : python/bash sans agents, templates, scaffold types ni static analysis (ruff/mypy/shellcheck absents) ; Go/Rust seulement en skeletons non chargés ; pas de Java ni Node backend.
- **Pas de couche visuelle** : aucun rapport HTML/Mermaid, contrairement à Graphify / davila7.
- **Pas de guides de synergie** avec l'écosystème (BMAD, Brainstorming/superpowers, UI-UX PRO MAX, RTK, Graphify).

Objectif : combler ces gaps **sans dénaturer le plugin** (code quality, SOLID, Clean Architecture, best practices par langage, extensibilité packs), en ajoutant un pilier Refactoring majeur (cœur de la culture craft) et en positionnant Craftsman comme **le quality gate de l'écosystème** plutôt qu'un concurrent des plugins d'orchestration.

## Décisions de cadrage (validées par l'utilisateur)

1. **Synergies progressives** : guides d'interopérabilité d'abord, adaptateurs techniques optionnels ensuite (flags + dégradation gracieuse, comme L2/L3).
2. **Tous les packs** : python/bash promus 1re classe, go/rust shippés, puis Java/Spring et Node/NestJS (vague 2).
3. **Surface legacy** : nouvelle commande `/craftsman:legacy` dédiée + `/refactor` approfondie.

## Contraintes & sources

- Corpus à distiller depuis les ouvrages : *Clean Architecture* (R.C. Martin), *Clean Code*, *Legacy Code First Aid Kit* (N. Carlo), *TDD by Example* (K. Beck), *Working Effectively with Legacy Code* (Feathers), Livre Blanc ADTF (test), *The Algorithm Design Manual* (Skiena — priorisation hotspots).
- ADRs contraignants : ADR-0005 knowledge-first (le knowledge précède les commandes), ADR-0007 commands-over-skills, ADR-0009 command-hooks-over-agent-hooks, ADR-0010 model tiering, ADR-0012 progressive disclosure, ADR-0013 workflow orchestrator, ADR-0004 agents 3P.
- Règles CLAUDE.md : hooks `exit 0/2` jamais 1 ; JSON via `jq -n` ; SQLite via `metrics-query.py` ; écritures atomiques ; frontmatter `description`+`effort` ; templates avec heading + `## Mission` + `## Context Files` ; checklist de version sync à chaque release.

---

## Roadmap — 6 releases incrémentales, chacune shippable

Séquencement : knowledge d'abord (ADR-0005), puis commandes qui le consomment, puis packs qui s'y branchent, puis intégrations sur un plugin feature-complete, enfin la fenêtre de breaking changes v4.0.

---

### v3.6.0 — Fondation Knowledge (« Corpus Craftsman »)

Pur contenu + nettoyage, zéro changement de comportement. Débloque tout le reste.

**Nouveaux fichiers core** (répertoires par thème dès ≥3 fichiers, comme `knowledge/anti-patterns/`) :

| Fichier | Source | Contenu |
|---|---|---|
| `knowledge/clean-architecture.md` | Clean Architecture (Martin) | Dependency Rule, cercles entities/use-cases/adapters/frameworks, boundaries & humble objects, screaming architecture, trade-offs des partial boundaries. Cross-liens vers GOD001/NEST001 comme signaux de détection. |
| `knowledge/hexagonal.md` | Cockburn | Ports driving/driven, placement des adapters, table de correspondance Hexagonale ↔ Clean Architecture ↔ layout du pack symfony, test au port. |
| `knowledge/tdd.md` | Beck | Red-green-refactor, 3 stratégies (fake it / triangulate / obvious), test list, quand TDD n'est PAS l'outil (spike/legacy → lien corpus legacy). |
| `knowledge/testing-strategy.md` | ADTF + Beck | Pyramide vs trophée, responsabilités unit/integration/contract/e2e, modèle de couverture ADTF, characterization tests comme porte d'entrée legacy, politique flaky tests. |
| `knowledge/legacy/legacy-techniques.md` | Feathers + Carlo | Définition (« code sans tests »), seams (object/link/preprocessing), catalogue dependency-breaking (Extract Interface, Parameterize Constructor, Subclass & Override, Adapt Parameter…), sprout method/class, wrap method/class, scratch refactoring. |
| `knowledge/legacy/characterization-testing.md` | Feathers + Carlo + ADTF | Recette golden master / approval testing, sensing variables, pinning tests, coverage-of-change. |
| `knowledge/legacy/strangler-fig.md` | Fowler / Carlo | Strangler fig, branch-by-abstraction, anti-corruption layer, event interception, checklists de bascule incrémentale. |
| `knowledge/refactoring/mikado-method.md` | Mikado + Carlo | Graphe d'objectifs, revert-instead-of-fix, exploration des prérequis, persistance du graphe entre sessions. |
| `knowledge/refactoring/refactoring-campaigns.md` | Fowler + Skiena | Campagnes multi-fichiers, priorisation churn×complexité (hotspots), stratégie de batching, métriques de campagne (lien `metrics-db.sh`). |

**Compléter le catalogue Fowler** dans `knowledge/refactoring-techniques.md` (Split Phase, Move Statements, Replace Loop with Pipeline, variantes Replace Conditional with Polymorphism…).

**Promotion DDD vers le core** :
- Déplacer `packs/symfony/knowledge/ddd-domain-design.md` et `ddd-cqrs-architecture.md` → `knowledge/ddd/`, réécrits agnostiques du langage.
- Le spécifique Symfony reste dans le pack : nouveau `packs/symfony/knowledge/ddd-symfony-implementation.md` (Doctrine, Messenger) ; `canonical/` inchangé.
- Stubs de dépréciation aux anciens chemins (supprimés en v4.0). Mettre à jour les références de `hooks/agent-ddd-verifier.sh`.

**SOLID par langage** : `knowledge/principles.md` reste LE texte canonique (pas de duplication de théorie) + un fichier canonique par pack chargé par `pack-loader.sh` : `packs/symfony/knowledge/canonical/php-solid.php`, `packs/react/.../tsx-solid.tsx`, `packs/python/.../py-solid.py`, `packs/bash/.../bash-solid.sh` (honnête sur les principes applicables). Table de mapping ajoutée à `principles.md`. Go/Rust/Java/Node suivent avec leurs packs.

**Nettoyage** :
- Fusionner `patterns.md` + `design-patterns.md` → garder `patterns.md` (une entrée par pattern : intent / smell corrigé / lien canonical pack) ; `design-patterns.md` devient stub. Grep + repointage de toutes les références (commands/, agents/, hooks/, packs/).
- Nouveaux anti-patterns core : `god-object.md` (GOD001), `primitive-obsession.md`, `singleton-abuse.md`.
- Mettre à jour les `## Context Files` de `commands/design.md`, `refactor.md`, `test.md` et `agents/architect.md`.
- Resynchroniser la version dans CLAUDE.md (3.4.5 → courante).

**Nouvel ADR** : `docs/adr/0015-core-knowledge-taxonomy.md` — core = concepts agnostiques, packs = implémentations canoniques.

---

### v3.7.0 — Piliers REFACTORING + LEGACY

**Nouvelle commande `commands/legacy.md`** — une commande, 4 modes (précédent : `/git`, `/workflow`), `effort: heavy` :
- **`/legacy audit`** — cartographie & rapport de reprise : hotspots (churn×complexité), carte de dépendances, modules classés par risque, recommandation « où poser le premier test » (flow First Aid Kit). Sortie : `LEGACY-AUDIT.md` avec diagrammes Mermaid natifs.
- **`/legacy cover`** — characterization tests / golden master AVANT tout changement, avec le framework de test du pack actif (phpunit/jest/pytest/bats), sensing variables, layout approval files.
- **`/legacy untangle`** — catalogue dependency-breaking : identifier le seam, choisir la technique, sprout/wrap quand la classe est intestable.
- **`/legacy migrate`** — planificateur de campagne strangler fig : ACL, points d'interception, checklist de bascule, état persisté dans `.craftsman/legacy-campaign.json` (écritures atomiques, pattern `session_state.py`).

Pas de `/takeover` ni `/migrate` séparés — `/legacy audit` EST l'entrée takeover.

**`/refactor` approfondie** (`commands/refactor.md`) :
- **Gate safety-net-first (étape 0)** : lancer les tests ; si rouges ou absents, ne PAS refuser — router vers `/legacy cover` pour construire un golden master, puis reprendre. C'est le lien comportemental entre les deux piliers.
- **Mode Mikado** pour les campagnes multi-fichiers : graphe persisté dans `.craftsman/mikado.json`, discipline revert-don't-fix, rendu Mermaid en fin de session.
- Pointer le catalogue de smells vers `knowledge/refactoring-techniques.md` (ADR-0005) au lieu de le dupliquer inline ; élargir `paths:` au-delà de php/ts/tsx (py, sh, go, rs).
- Conformément à ADR-0009 : pas de nouveau agent hook — le gate vit dans le flow de commande, le quality gate 3 niveaux continue de valider les writes.

**Hotspot tooling** : nouveau `hooks/lib/hotspot_analysis.py` — churn (`git log --numstat`, lecture seule) × complexité (réutilise le scoring de `structural_metrics.py` : NEST001/LOC001/GOD001) → ranking JSON, persisté via `metrics-db.sh` (nouvelle table `hotspots`, accès via `metrics-query.py`). **Command-time uniquement, jamais hook-time** (budget L1 <50ms préservé). Advisory. `commands/metrics.md` gagne une section hotspots.

**Agent + team** :
- Nouvel agent core `agents/legacy-surgeon.md` — pattern 3P (ADR-0004), tier Sonnet (ADR-0010). Un seul nouvel agent ; architect et doc-writer réutilisés.
- Nouveau template `teams/templates/legacy-takeover.yml` (architect → legacy-surgeon → security-pentester → doc-writer), schéma des 3 templates existants.

**Routage 3 scénarios dans `/workflow`** (`commands/workflow.md`, ADR-0013) — détection/sélection à l'étape 1 :
- **greenfield build** → pipeline 7 étapes existant, avec `clean-architecture.md` + `tdd.md` injectés aux étapes design/test ;
- **analyse de legacy** → pipeline `/legacy audit` (audit → rapport → backlog priorisé) ;
- **reprise de contrôle legacy** → audit → cover → untangle → `/refactor` (Mikado) → migrate, avec suggestion du team template `legacy-takeover`.

**Docs & exemples** : `examples/legacy/` (convention `examples/<command>/`), `docs/guides/legacy-first-aid.md` (playbook façon Carlo).

---

### v3.8.0 — Packs vague 1 : python/bash 1re classe, go/rust shippés

**Python 1re classe** :
- `packs/python/static-analysis/` : intégration ruff + mypy dans `hooks/lib/static-analysis.sh` L2 avec dégradation gracieuse (skip silencieux si binaire absent — pattern phpstan).
- `packs/python/agents/python-craftsman.md` + `python-reviewer.md` (split craftsman/reviewer du pack symfony).
- Templates (heading + Mission + Context Files), `canonical/py-usecase.py`, `py-value-object.py`, `py-solid.py`.
- Scaffold types dans `commands/scaffold.md` : `fastapi-service`, `cli-tool`.

**Bash 1re classe** : intégration shellcheck (L2, dégradation), `packs/bash/agents/bash-craftsman.md` (un seul agent suffit), `canonical/bash-solid.sh`, scaffold type `bash-cli`.

**Shipper Go et Rust** : promouvoir `examples/pack-skeleton-{go,rust}` → `packs/go/`, `packs/rust/` : pack.yml, validateurs (gofmt/go vet ; cargo clippy/rustfmt — L2 dégradation), knowledge (idiomes + `canonical/go-solid.go`, `rust-solid.rs` avec framing interfaces/traits pour ISP/DIP), un agent `*-craftsman.md` chacun, un scaffold type chacun. Les skeletons restent dans `examples/` comme artefacts de doc pour `docs/creating-packs.md`.

---

### v3.9.0 — Synergies écosystème + rapports visuels

**Infrastructure partagée** :
- `commands/setup.md` + wizard : détection des plugins compagnons installés → bloc `integrations:` dans `.craft-config.yml`, parsé par `hooks/lib/config.sh`. Tout est **flags + docs, zéro dépendance dure** (dégradation gracieuse comme L2/L3). `commands/healthcheck.md` rapporte le statut des intégrations.
- Index `docs/guides/synergies.md` + un guide par plugin. Chaque guide documente les DEUX sens : comment le plugin améliore Craftsman, et comment Craftsman améliore son usage.

**Décisions par plugin** :

| Plugin | Mécanisme | Synergie (les 2 sens) |
|---|---|---|
| **BMAD** | `docs/guides/synergy-bmad.md` + `commands/workflow.md` accepte un story/PRD BMAD comme input de spec (mapping documenté). | BMAD apporte le pilotage produit (PRD → stories) ; Craftsman est le quality gate des phases Dev/QA/Architect — nos hooks tirent quel que soit le pilote. On ne reconstruit AUCUN de ses 34 workflows. |
| **Brainstorming (superpowers)** | `docs/guides/synergy-superpowers.md` (étend `docs/superpowers/`) : table de mapping (leur brainstorming → notre `/design`+`/challenge` ; leur skill TDD vs notre `/test` — config documentée pour éviter le double-gating). | Leur exploration socratique en amont ; notre enforcement DDD/architecture en aval. Doc-only, ADR-0007 préservé. |
| **UI-UX PRO MAX** | Clause de délégation dans `agents/ui-ux-director.md` : si flag actif, déférer styles/palettes/stacks à UI-UX PRO MAX ; conserver l'architecture de composants et la revue accessibilité-code. | Leur DB (107 styles/131 règles) est inégalable ; notre valeur = qualité du code des composants qu'ils spécifient. |
| **RTK** | `docs/guides/synergy-rtk.md` + check healthcheck : vérifier que la réécriture PreToolUse de RTK ne shadow pas l'ordre de nos hooks dans `hooks/hooks.json`. | RTK réduit 60-90 % des tokens sur nos commandes verbeuses (git/test/audit) ; on documente le combo et on teste le seul risque réel (ordre des hooks). |
| **Graphify** | Intégration la plus profonde : `/legacy audit` et `/metrics --report`, si flag actif, orchestrent Graphify puis **superposent les findings Craftsman sur `graph.json`** (violations de Dependency Rule, hotspots de `hotspot_analysis.py`). | Graphify apporte la visualisation interactive (graph.html) qu'on ne construira jamais ; Craftsman enrichit son graphe d'annotations qualité qu'aucun autre plugin ne produit. |

**Rapports visuels — décision** : natif = **Mermaid-in-Markdown uniquement** ; HTML interactif = délégué à Graphify (construire un dashboard HTML dénaturerait le plugin).
- Nouveau `hooks/lib/report_generator.sh` : assemble `CRAFTSMAN-REPORT.md` depuis `metrics-query.py` (table hotspots, tendance quality-gate, distribution des métriques structurelles, diagrammes Mermaid modules/hotspots). Utilisé par `/metrics --report` et `/legacy audit`. Si Graphify détecté : le rapport lie/embarque ses sorties avec annotations Craftsman par nœud.

---

### v3.10.0 — Packs vague 2 : Java/Spring + Node/NestJS

(Choix utilisateur explicite ; vague séparée pour shipper chaque pack correctement plutôt que 4 à moitié.)

**Pack `packs/java/`** : validateur regex L1 (JAVA001+ : pas de field injection, pas de God controller, exceptions checked avalées…), static analysis L2 Checkstyle/SpotBugs + **ArchUnit L3** (équivalent deptrac pour la Dependency Rule), agents `java-craftsman.md` + `java-reviewer.md`, knowledge (idiomes Spring/DDD Java, `canonical/java-solid.java`, `java-usecase.java`, `java-value-object.java` — records), templates bounded-context, scaffold types `spring-usecase`, `spring-api-resource`.

**Pack `packs/node/`** : cible backend TypeScript (NestJS) distincte du pack react — validateur NODE001+ (pas de logique dans les controllers, DTO validés, pas d'`any`), ESLint strict + dependency-cruiser L3 réutilisé, agents `node-craftsman.md` (+ réutilisation de `react-reviewer` si pertinent), knowledge Clean Architecture Node/NestJS, `canonical/nest-usecase.ts`, scaffold types `nest-module`, `nest-usecase`.

Les deux passent `scripts/validate-pack.sh --check-collisions` et suivent le contrat de `docs/creating-packs.md` — ce cycle valide au passage que le contrat de pack tient pour un langage JVM (retour d'expérience → amendements éventuels de `creating-packs.md`).

---

### v4.0.0 — Team features + consolidation (fenêtre de breaking changes)

- **Correction-learning team sync** (promis « v4 » dans le README) : nouveau `hooks/lib/team-sync.sh` — export/import de la table SQLite `corrections` vers `.craftsman/team-corrections.yml` anonymisé et committable (opt-in via `.craft-config.yml`, note privacy ; réutilise `metrics-db.sh` + `yaml-parser.py`). `commands/metrics.md` gagne la vue équipe ; merge additif avec décroissance de confiance.
- **Boucle corrections → règles d'équipe** : documenter/encourager la génération d'un `.craft-rules.yml` projet depuis les corrections synchronisées. Décision : PAS de 4e niveau d'héritage dans `rules-engine.sh` — le niveau projet couvre déjà le besoin.
- **Nettoyages breaking** : suppression des stubs (`design-patterns.md`, stubs DDD symfony), finalisation des defaults `refactor.md`.
- `docs/guides/upgrading-to-v4.md` ; `docs/adr/0016-team-corrections-sync.md`.

---

## Garde-fous anti-dénaturation (ce que ce plan ne fait PAS)

1. Pas de système PRD/story/planning — c'est BMAD ; `/spec` reste à l'altitude code.
2. Pas de base design-system ni générateurs UI — territoire UI-UX PRO MAX ; seule une clause de délégation.
3. Pas de hooks d'optimisation de tokens — c'est RTK ; on ne teste que la compatibilité d'ordre des hooks.
4. Pas de dashboard HTML natif — Mermaid Markdown + délégation Graphify.
5. Pas de bascule vers skills-avec-gating façon superpowers — violerait ADR-0007 ; la complémentarité reste le positionnement.
6. Pas de prolifération de personas — un seul nouvel agent core (legacy-surgeon), minimum par pack.
7. Pas de CircleCI/Azure dans ce cycle (generic.sh couvre) — candidats v4.x.
8. Pas d'analyse hotspot en hook-time — command-time uniquement (budget L1 <50ms).

## Vérification (par release + transverse)

**Transverse (chaque release)** :
- `bash tests/run-tests.sh` complet vert ; chaque nouvelle lib/commande a son `tests/core/test-*.sh` (style fixtures existant).
- Hooks : exit 0/2 jamais 1 ; JSON via `jq -n` ; SQLite via `metrics-query.py` ; écritures atomiques pour `.craftsman/*.json`.
- Commandes : frontmatter `description`+`effort` ; templates : heading + Mission + Context Files (lint `tests/templates/`).
- Packs : `scripts/validate-pack.sh --check-collisions` sur tous les packs.
- Checklist version sync : `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `ci/craftsman-ci.sh`, `CHANGELOG.md`, badge README (+ CLAUDE.md).

**Par release (smoke test dogfood sur le repo du plugin lui-même)** :
- v3.6 : nouveau `tests/core/test-knowledge-integrity.sh` (cross-links, stubs, frontmatter) ; grep zéro référence restante à `design-patterns.md` hors stub ; `/craftsman:design` charge le nouveau corpus.
- v3.7 : `tests/core/test-legacy-command.sh`, `test-hotspot-analysis.sh` (repo git fixture, ranking déterministe), `test-workflow-command.sh` étendu au routage 3 scénarios ; dogfood `/legacy audit` sur le repo.
- v3.8 : tests packs avec ET sans binaires SA installés (le chemin de dégradation est LE test critique) ; `/scaffold` de chaque nouveau type dans un dir temp + validation du résultat.
- v3.9 : `test-integrations-config.sh` (parsing flags, dégradation plugin absent), `test-report-generator.sh` (DB fixture → Markdown déterministe) ; wizard avec/sans faux plugin compagnon ; rendu Mermaid vérifié.
- v3.10 : validate-pack sur java/node, scaffolds Spring/Nest smoke-testés.
- v4.0 : `test-correction-learning.sh` étendu (roundtrip export→wipe→import, assertions d'anonymisation, fixture merge 2 machines) ; grep zéro référence aux stubs supprimés.

## Fichiers critiques

- `commands/refactor.md` — gate safety-net-first, mode Mikado, paths élargis (cœur du pilier Refactoring)
- `commands/legacy.md` (nouveau) — 4 modes audit/cover/untangle/migrate
- `commands/workflow.md` — routage 3 scénarios (ADR-0013)
- `hooks/lib/hotspot_analysis.py` (nouveau) — churn×complexité, réutilise `structural_metrics.py`
- `hooks/lib/pack-loader.sh` — contrat de chargement des canoniques SOLID/DDD par pack et des nouveaux packs
- `knowledge/principles.md` — ancre du SOLID-par-langage et de la taxonomie core-vs-pack (ADR-0015)
- `docs/creating-packs.md` + `scripts/validate-pack.sh` — contrat d'extensibilité éprouvé par les 4 nouveaux packs
