# Audit du coeur, CI, distribution et tests

Périmètre: dépôt `ai-craftsman-superpowers`, état initial `879e432`, version 4.10.3. Lecture et vérifications sur des fixtures temporaires. Le parent signale qu'une autre session a avancé HEAD à `fc502c7` pendant l'audit avec le correctif de version `plugin.yaml` (#88). Les observations de distribution de l'état initial ne sont donc pas présentées comme des défauts encore ouverts. Aucun changement au produit, aux installations ou aux données métier. Les preuves UI et documentation officielle sont prises en charge par la session principale.

**Verdict: REQUEST_CHANGES pour une distribution présentée comme compatible Codex et Claude Code.** Le coeur de validation est déjà réutilisable. La matrice de compatibilité et la préservation des instructions existantes ne le sont pas encore.

## Findings actionnables

### P1: l'export recommandé aux utilisateurs Codex écrase leurs instructions

- Localisation: `ci/doctrine-export.sh:127`, invocation documentée dans `skills/ci/SKILL.md:90`.
- Le traitement `export --target agents-md` ouvre directement `AGENTS.md` avec `>`, sans vérifier qu'il appartient au générateur. Un fichier issu de l'import de Claude Code ou maintenu par le projet est entièrement remplacé. La même stratégie concerne `.github/copilot-instructions.md` à la ligne 135.
- Preuve consommateur: dans `/tmp/craftsman-core-consumer-4l2bsdxa`, un `AGENTS.md` préexistant contenant une instruction témoin a été passé au vrai CLI provenant d'une archive Git HEAD non modifiée. Le CLI sort avec 0, le fichier produit fait 5173 octets et le témoin a disparu. Résultat conservé dans `/tmp/craftsman-audit-core-consumer.json`.
- Impact: perte des conventions, contraintes et décisions du projet au moment où l'on cherche à ajouter Craftsman à Codex. Le fichier `AGENTS.md` frais et non suivi de ce checkout est précisément un cas exposé si cette commande y est lancée.
- Correction: remplacer seulement un bloc Craftsman explicitement délimité, conserver tout le contenu extérieur, créer le fichier si absent. Refuser un fichier existant sans marqueur si aucun mode de fusion n'est proposé. Test requis: une instruction témoin hors bloc survit à deux exports et le bloc reste idempotent.

### P1: les contrôles de compatibilité ne chargent aucun artefact dans Codex

- Localisation principale: `tests/adapters/test-parity.sh:75` et `tests/adapters/test-parity.sh:98`.
- La parité éditeur/CI/Hermes injecte des objets `tool_input.file_path` et `tool_input.content` directement dans des scripts Bash. Elle vérifie une parité de fonctions, sans passage par le chargeur ni le protocole d'outil de Codex.
- Autres localisations: `.github/workflows/ci.yml:91` tient une liste locale d'événements Claude; `tests/run-tests.sh:308` ne charge que `.claude-plugin/plugin.json`; `tests/run-tests.sh:221` n'admet que des tiers de modèles Anthropic ou alias Claude.
- Preuve: recherche ciblée des termes `Codex|codex` dans `tests`, `ci`, `adapters`, `.github` et `scripts`: seules les descriptions et les tests d'export de doctrine citent Codex. Aucun chemin de chargement Codex ni scénario d'import n'est présent. Les tests existants peuvent tous passer alors que l'import ne branche aucune écriture sur le validateur.
- Correction: ajouter une matrice explicite Claude Code/Codex avec artefact réellement chargé, écriture valide témoin puis violation connue, options, session ID, annulation et fin de session. Conserver les tests rapides du coeur; ajouter à part les tests d'adaptation et d'intégration des hôtes. Ne pas réécrire les règles par hôte.

### Observation historique de distribution, à ne pas compter comme finding ouvert

- Localisations relevées dans l'état initial: `scripts/bump-version.sh:50`, `.github/workflows/ci.yml:183`, `scripts/release-build.sh:47`.
- Au début de l'audit, la source du numéro était `.claude-plugin/plugin.json`; le validateur de manifeste lisait ce même chemin; le paquet était une archive du tag Git. Les fichiers `.codex/` et `AGENTS.md` de cet import étaient non suivis dans le checkout et ne pouvaient donc entrer dans cette archive. Le correctif concurrent `fc502c7` sur `plugin.yaml` empêche de traiter la synchronisation des versions observée initialement comme un défaut actuel.
- Impact: le résultat local de l'import Desktop n'est pas un livrable reproductible du plugin. Un tag ou une mise à jour du paquet Claude ne suffit pas à distribuer les adaptations Codex observées sur cette machine.
- Correction: versionner ou générer de manière déterministe le paquet destiné à chaque hôte, vérifier chaque paquet avec son consommateur et intégrer leurs versions et fichiers au chemin de publication. Déterminer d'abord avec la documentation actuelle si Codex consomme directement le paquet Claude ou requiert un manifeste propre. L'audit statique ne tranche pas une capacité du produit.

### P2: configuration globale et stockage demeurent liés à Claude

- Localisations: `hooks/lib/config.sh:32`, `hooks/lib/config.sh:48`, `hooks/lib/config.sh:197`, `hooks/lib/config.sh:236`, `hooks/lib/metrics-db.sh:13`, `hooks/lib/lang-registry.sh:32`.
- Les options sont résolues seulement à travers `CLAUDE_PLUGIN_OPTION_*`; la configuration globale pointe vers `~/.claude`; la confiance envers les outils projet et les packs externes lisent directement ce répertoire. Les valeurs par défaut de stockage diffèrent aussi entre métriques, registre et cache de manifests.
- C'est un couplage démontré par le code, pas la preuve que l'import actuel échoue: un adaptateur peut fournir les alias nécessaires. Le parent doit rapprocher ce constat des variables réellement injectées par Desktop.
- Correction: centraliser la résolution d'un contexte d'exécution Craftsman, puis faire traduire les variables de chaque hôte à l'entrée. Garder une reprise explicite des chemins Claude existants. Tests: deux hôtes, deux sessions simultanées, configurations et données isolées, puis migration contrôlée d'une ancienne installation.

## Vérifications exécutées et signification

### Suite complète initiale

Commande: `CRAFTSMAN_HEADLESS_VERIFY=1 bash tests/run-tests.sh`, log `/tmp/craftsman-audit-test-suite.log`.

Résultat du runner: **263 contrôles/sous-suites réussis, 4 sous-suites en échec, 0 ignoré**. Ce nombre ne représente pas le nombre total d'assertions. Cette exécution ne constitue pas un verdict de release valide: la garde globale utilisée pour interdire les appels LLM désactive aussi `session-start.sh:18` et `session-metrics.sh:14`.

Les quatre rouges correspondent exactement à cette instrumentation:

| Sous-suite | Échecs initiaux | Cause |
|---|---:|---|
| test-hooks.sh | 8 | contexte initial absent, session non terminée, métriques absentes |
| test-session-metrics.sh | 10 | écriture et nettoyage de session court-circuités |
| test-session-start.sh | 6 | aucun message ni bridge généré |
| test-legacy-command.sh | 1 | table de routage de SessionStart absente |

### Recontrôle ciblé sans garde globale

Copie créée avec `git archive HEAD` dans `/tmp/craftsman-core-recheck-_k9bqocf/repo`. Le hash exact de HEAD à l'extraction n'a pas été enregistré par ce script; il ne faut pas attribuer arbitrairement ce recontrôle à `879e432` ou `fc502c7`. Sources produit et tests non modifiés. Environnement HOME privé fourni aux sous-processus; pas de nouvel appel LLM. Les tests concernés appellent des hooks déterministes.

- `test-session-metrics.sh`: **28/28**, sortie 0. Log `/tmp/craftsman-audit-recheck-test-session-metrics.sh.log`.
- `test-session-start.sh`: **12/12**, sortie 0. Log `/tmp/craftsman-audit-recheck-test-session-start.sh.log`.
- `test-legacy-command.sh`: **20/20**, sortie 0. Log `/tmp/craftsman-audit-recheck-test-legacy-command.sh.log`.
- `test-hooks.sh`: preuve réutilisée de l'agent hooks, communiquée par le parent: **141/141**. Pas de seconde exécution inutile ici.

Conclusion: les quatre rouges du premier run ne révèlent pas de régression produit. Ne pas transformer cette conclusion en affirmation qu'un run complet sans instrumentation a été effectué.

### Consommateur CLI réel

Le CLI provenant de la même archive Git a été invoqué sans `CLAUDE_PLUGIN_ROOT`, sans option `CLAUDE_PLUGIN_OPTION_*` et avec une configuration projet explicite. Les chemins de données sont temporaires.

- Fichier TypeScript valide: sortie **0**, 1 fichier inspecté, 0 violation.
- Même fichier avec type `any`: sortie **2**, 1 fichier inspecté, **TS001**.
- Export sur un `AGENTS.md` existant: sortie **0**, instruction antérieure perdue.

Preuve structurée: `/tmp/craftsman-audit-core-consumer.json`. Ce témoin démontre que le coeur CLI fonctionne sans session Claude; il ne démontre pas que Codex appelle ce CLI sur ses outils.

## Bonnes pratiques constatées

- `ci/craftsman-ci.sh:365` à 390 source les mêmes bibliothèques de configuration, règles, packs, analyse statique et précédence que les hooks. Hermes délègue au même CLI (`adapters/hermes/pre-verify.sh:57`). Ce partage est réel et évite un fork des règles.
- Le registre de langues dérive des manifests des packs. Les ajouts de langage ne dépendent pas d'une liste de suffixes maintenue dans chaque hôte.
- Les tests de précédence vérifient qu'un analyseur absent, non approuvé, arrêté ou sans verdict ne supprime pas le résultat de niveau 1 (`tests/core/test-precedence.sh:7`).
- Les écritures de métriques utilisent un helper SQLite paramétré. Les écritures d'état utilisent un fichier temporaire suivi d'un renommage (`hooks/lib/session_state.py:49`).
- Les tests protègent la parité de sévérité, les surcharges par répertoire et l'impossibilité de masquer SEC001 avec un commentaire d'ignorance. Ils incluent des témoins pour plusieurs garde-fous.
- La release est reproductible via `gzip -n`; les tags de release et de marketplace doivent désigner le même commit. Actions épinglées et limites de l'attestation documentées. Cette discipline est à étendre au livrable Codex.

## Limites

Pas de chargement réel des paquets dans les deux applications depuis cet agent. Pas de vérification en ligne des fonctionnalités des hôtes, traitée par le parent. Aucun test de facturation réelle des vérificateurs sémantiques ni d'analyseurs externes installés. Aucun nouvel audit exhaustif d'injection de commandes ou des fournisseurs CI distants. Les tests déjà présents fournissent une bonne couverture locale, pas une preuve d'intégration Codex.

Les relevés du working tree effectués par cet agent montraient `?? .codex/` et `?? AGENTS.md`. HEAD a ensuite avancé dans une autre session, comme signalé par le parent. Aucun correctif produit n'a été appliqué par cet agent.
