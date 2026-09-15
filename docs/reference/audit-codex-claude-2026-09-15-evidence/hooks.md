# Audit des hooks Craftsman 4.10.3 : Codex et Claude Code

Périmètre : dépôt `/Users/woprrr/Dev/claude/ai-craftsman-superpowers`, HEAD annoncé `879e432`, import frais de Claude Code vers Codex Desktop. Revue en lecture seule du produit. Les essais écrivent uniquement dans une copie temporaire du dépôt et dans des répertoires de test. Aucun appel LLM réel, aucun changement de configuration installée.

**Verdict : BLOCK pour annoncer la compatibilité fonctionnelle des quality gates Codex.** Le chargement du plugin et le déclenchement de ses hooks sont distincts de la capacité des scripts à traiter les événements. Plusieurs défauts de contrat existent aussi avant l'import, sous Claude Code.

## Findings prioritaires

### H1. P1 : les écritures apply_patch traversent les contrôles sans être analysées

- Localisation : `hooks/pre-write-check.sh:36`, `hooks/pre-write-check.sh:40`, `hooks/post-write-check.sh:203`, `hooks/config-protection.sh:23`, `hooks/agent-ddd-verifier.sh:31`, `hooks/lib/write_mirror.py:196`.
- Les scripts exigent `tool_input.file_path` puis quittent silencieusement lorsqu'il manque. Le miroir connaît Write/Edit et le protocole Hermes, pas apply_patch.
- Le contrat Codex documente les aliases de matcher Edit/Write, mais conserve `tool_name=apply_patch` et le patch dans `tool_input.command`. Ce n'est donc PAS un problème de matcher.
- Preuve comparative exécutée : le même Order.php avec une classe non final et un import Domain vers Infrastructure donne rc=2 et PHP002/LAYER001 via Write, mais rc=0 et zéro sortie via apply_patch, avant et après écriture. Une écriture vers phpstan.neon est refusée via Write, admise via apply_patch.
- Impact : enforcement, métriques, apprentissage des corrections, compteur de writes, invalidation de verified et revue DDD ne fonctionnent pas pour les écritures Codex ordinaires. Le contrôle de configuration est lui aussi contourné involontairement par le protocole.
- Correction : une normalisation à la frontière des hosts, produisant la liste des fichiers affectés et leur contenu futur. Le parser doit gérer ajout, mise à jour, suppression, déplacement et patch multifichier, puis utiliser le même miroir et les mêmes validateurs. En sortie, l'autofix Codex doit réécrire `command`, pas un objet Write avec `content`.
- Validation de sortie : vrais appels apply_patch du host, contrôle invalide refusé avant écriture, contrôle valide appliqué, tests de plusieurs fichiers et chemins déplacés. Conserver les contrôles Write/Edit Claude existants.

### H2. P1 : le succès d'une commande de tests est interprété comme une régression

- Localisation : `hooks/post-bash-test-verify.sh:21`, `hooks/post-bash-test-verify.sh:69`.
- Le script lit `.tool_result.exit_code // .tool_result.exitCode // "1"`. Les événements PostToolUse des deux hosts utilisent `tool_response`, pas `tool_result`.
- Preuve exécutée : état initial verified=true, commande pytest et `tool_response.exit_code=0` donnent rc=2, message « Test suite REGRESSED », puis verified=false. Le contrôle identique avec le champ non documenté `tool_result.exit_code=0` donne verified=true.
- Les tests existants valident donc un faux contrat. La suite générale verte n'annule pas cette reproduction.
- Correction : normaliser la réponse spécifique de chaque host. Vérifier les formes réellement émises pour Bash et exec_command, dont l'exécution terminée après write_stdin. L'absence de code ne doit pas être inventée comme un code 1. Traiter une exécution en cours comme sans verdict.
- Validation de sortie : succès réel => verified, échec réel après succès => révocation, code absent => diagnostic sans faux résultat, shell asynchrone => attendre le résultat final.

### H3. P1 sous environnement sans alias Claude : l'identité de session stdin est ignorée

- Localisation : `hooks/lib/session-files.sh:29`, `hooks/lib/session_state.py:303`, `hooks/session-start.sh:44`, `hooks/session-metrics.sh:27`, `hooks/session-metrics.sh:154`.
- La séparation des fichiers dépend uniquement de CLAUDE_CODE_SESSION_ID. Aucun de ces chemins ne récupère le session_id fourni dans stdin. SessionStart jette même son entrée.
- Preuve isolée : deux événements portant session_id=codex_A et session_id=codex_B, sans variable CLAUDE_CODE_SESSION_ID, créent un seul session-state.json avec les deux événements. La fin d'une session utilise ce même nom pour supprimer l'état.
- Observation de l'environnement exec_command de cette session Codex : CLAUDE_CODE_SESSION_ID absent, CODEX_THREAD_ID et CODEX_SESSION_ID présents. Les valeurs n'ont pas été imprimées. Cette observation n'est pas une capture de l'environnement des hooks eux-mêmes.
- Certitude : défaut du contrat d'entrée et collision dans la reproduction confirmés. La présence éventuelle d'un alias injecté uniquement dans les processus hook du Desktop doit encore être capturée avant de qualifier une collision de production d'observée.
- Correction : session_id stdin canonique pour les hooks, contexte de session explicite partagé avec les outils/skills, résolution propre à chaque host. Aucun fallback partagé silencieux pour une session dont l'entrée donne déjà un ID.
- Validation de sortie : deux sessions Codex, une session Claude simultanée, états distincts, fin de B conserve A, verified de A ne valide jamais B.

### H4. P2 : le contrôle de sous-agent lit le transcript du parent

- Localisation : `hooks/subagent-quality-gate.sh:34`, `hooks/subagent-quality-gate.sh:63`, `tests/core/test-agent-hooks.sh:217`.
- Le champ lu est transcript_path. Le contrat SubagentStop des deux hosts fournit agent_transcript_path pour le sous-agent. Sous Claude, transcript_path est explicitement le transcript du parent.
- Preuve exécutée : transcript parent vide et enfant contenant un Write invalide => aucune sortie. En plaçant artificiellement le transcript enfant dans transcript_path, le même hook signale PHP001 et PHP002.
- Impact : absence de vérification des fichiers de l'enfant ou attribution des fichiers du parent au mauvais agent. De plus, le parser JSONL interne ne sait lire que les blocs Claude `assistant/message/content/tool_use` avec Write/Edit/MultiEdit. La documentation Codex ne garantit pas la stabilité de son transcript.
- Correction : utiliser agent_transcript_path côté Claude; pour Codex, journaliser les fichiers touchés depuis les événements outils normalisés avec leur propriétaire, plutôt que dépendre d'un format de conversation non stable. Corriger les fixtures.
- Limite supplémentaire : vérifier la destination du feedback. Les commentaires du script promettent le parent, alors que les contrôles SubagentStop documentés concernent la poursuite du sous-agent; Claude recommande PostToolUse Agent pour injecter chez le parent.

### H5. P2 : le cycle de revue sémantique reste attaché au CLI Claude et à la reprise asynchrone Claude

- Localisation : `hooks/lib/haiku-verify.sh:31`, `hooks/lib/haiku-verify.sh:57`, `hooks/agent-ddd-verifier.sh:94`, `hooks/agent-final-review.sh:126`, `hooks/hooks.json:50`, `hooks/hooks.json:153`.
- Le backend exécute exclusivement `claude -p` avec modèle Haiku, outils Read/Grep/Glob et paramètres Claude. Si claude n'est pas disponible, les appelants sortent silencieusement avec succès. Installer uniquement Codex ne fournit pas de backend pour cette couche.
- Les verdicts négatifs sont transmis via stderr + exit 2, et le manifeste utilise asyncRewake. La doc Codex précise que l'achèvement d'un hook de fond ne démarre pas un nouveau tour; les hooks de fond ne contrôlent pas la continuation. asyncRewake n'est pas mentionné comme champ Codex, ce qui seul ne prouverait pas une absence de support; c'est la sémantique de fond explicitement décrite qui empêche de promettre la même reprise.
- Correction : backend de vérification sélectionné explicitement par host, avec diagnostics « disponible / désactivé / absent » et collecte d'un verdict neutre. Livraison Codex via additionalContext persistant, ou contrôle synchrone du Stop avec budget défini si la reprise automatique est un critère obligatoire. Conserver le backend Claude sous Claude.
- Validation de sortie : Codex seul sans claude, résultat sémantique proprement déclaré; backend sélectionné exécuté; verdict négatif effectivement reçu par la session cible. Aucun appel payant n'a été réalisé pendant cet audit.

### H6. P2 : le pont global ~/.claude n'isole pas les installations Claude et Codex

- Localisation : `hooks/session-start.sh:60`, `hooks/session-start.sh:61`, `hooks/session-start.sh:90`, `hooks/session-start.sh:102`, `hooks/session-start.sh:125`, `hooks/lib/session_state.py:291`.
- Chaque SessionStart réécrit les mêmes ponts et wrappers dans ~/.claude, avec le chemin du code et des données de sa propre installation. Une session d'une autre installation remplace ces fichiers globaux. Les readers préfèrent le pont au répertoire fourni dans leur propre environnement.
- Impact concret d'architecture : après démarrage de Codex, une skill Claude peut utiliser le wrapper Codex et inversement; les métriques/verified peuvent être dirigés vers les données d'une autre installation. Ce problème existe déjà entre plusieurs installations ou versions Claude; l'utilisation simultanée de deux hosts augmente l'exposition.
- Correction : résolution par host et session, pont uniquement lorsqu'il est nécessaire, wrappers stables qui reçoivent le contexte au lieu d'incorporer la dernière installation démarrée. Placer les données dans PLUGIN_DATA/alias documenté et garder une migration explicite pour les anciennes données.
- Certitude : lecture du code confirmée; la collision simultanée entre les deux applications installées n'a pas été provoquée pour ne pas modifier leur état.

### H7. P2 : le hook Sentry branché sur Stop ne peut pas atteindre sa fonction

- Localisation : `hooks/hooks.json:146`, `hooks/agent-sentry-context.sh:25`, `hooks/agent-sentry-context.sh:27`.
- Le script exige tool_input.file_path, mais le seul événement auquel il est branché est Stop, sans ce champ. Même avec Sentry configuré, le chemin normal termine avant la construction de la requête.
- La seule sortie prévue est systemMessage, alors que le commentaire promet additionalContext destiné au modèle.
- Correction : soit brancher une version acceptant les écritures normalisées sur PostToolUse, soit construire à Stop un ensemble de fichiers de la session. Émettre additionalContext sur un événement qui le livre au modèle. Ajouter un test avec un vrai payload Stop, pas un payload Write envoyé manuellement à un hook Stop.

## Ajustements de portage à inclure dans H1/H5, sans les compter deux fois

- `hooks/config-protection.sh:70` retourne permissionDecision=ask pour les propres fichiers de configuration du gate. Codex le documente explicitement comme parsé mais non pris en charge, avec poursuite de l'outil après signalement d'erreur. Une fois le parser apply_patch corrigé, il faut aussi traduire cette décision en mécanisme supporté, faute de quoi la protection restera ouverte.
- `hooks/pre-write-check.sh:161` retourne updatedInput avec content/file_path. Pour Codex apply_patch, le contrat attend command. Corriger uniquement les noms des outils ne suffira pas.
- `hooks/hooks.json` inclut TaskCompleted, PostToolUseFailure et FileChanged. Leur présence dans le manifeste n'est pas une preuve d'exécution Codex. Le manifeste par host doit refléter les événements vérifiés par le consommateur. Dans la doc consultée ces trois événements n'apparaissent pas parmi les événements Codex décrits; ce constat est une absence de documentation, pas à lui seul une preuve d'impossibilité.
- `hooks/tool-failure-tracker.sh:36` laisse le compteur Python sur stdout : les essais renvoient « 1 », puis « 2 ». `hooks/post-bash-test-verify.sh:84` laisse aussi « verified=true at ... » sur stdout. Ce ne sont pas des objets du protocole hook. Garder stdout pour le contrat JSON et stderr pour les diagnostics.
- Le matcher FileChanged reste limité aux extensions PHP/TS/TSX dans `hooks/hooks.json:100`, même si son script utilise le registre des packs. Ne pas promettre une couverture IDE des sept packs sur la seule base du dispatch.

## Compatibilité déjà étayée

- Les aliases de matcher Edit/Write pour apply_patch et Bash pour exec_command sont documentés. Ne pas les présenter comme manquants.
- Codex documente les aliases CLAUDE_PLUGIN_ROOT/CLAUDE_PLUGIN_DATA. Les commandes du manifeste utilisant CLAUDE_PLUGIN_ROOT ne sont donc pas incorrectes du seul fait de ce préfixe.
- La forme SessionStart additionalContext du script correspond au contrat Codex; la bannière active observée dans la session est cohérente avec cette partie fonctionnelle.
- Le coeur réutilise les mêmes packs et la même logique de miroir avant écriture. C'est une base appropriée pour l'adaptateur Codex, sous réserve de ne pas forker les règles.
- Des contrôles valides accompagnent les probes invalides : les résultats rouges ne proviennent pas simplement d'un script en panne.
- Garde de récursion CRAFTSMAN_HEADLESS_VERIFY, sorties 0/2 sur les contrôles, écritures de session atomiques et requêtes SQL paramétrées constituent des protections utiles à conserver.

## Essais exécutés et artefacts

Les trois scripts existants ont été exécutés sur une copie temporaire du dépôt, avec HOME/données séparés et un stub claude qui interdit tout appel modèle réel :

| Suite | Résultat |
|---|---|
| tests/core/test-hooks.sh | 141 pass, 0 fail |
| tests/core/test-agent-hooks.sh | 43 pass, 0 fail |
| tests/core/test-session-state-lib.sh | 21 pass, 0 fail |
| Total | 205 pass, 0 fail |

Ces suites utilisent des fixtures Claude historiques. Elles prouvent ces comportements internes; elles ne prouvent pas le contrat Codex. Les nouvelles probes font apparaître les écarts H1, H2, H3 et H4 malgré ce total vert.

Racine des preuves : `/var/folders/m0/dvzhx8xn2158tyvxywfskdc40000gn/T/craftsman-hook-audit-g5t0pp8l`.

- `probes.json` : Write versus apply_patch, protections configuration, vérification tests tool_response versus tool_result.
- `second-probes.json` : deux session_id et transcript parent/enfant.
- `test-hooks.sh.log`, `test-agent-hooks.sh.log`, `test-session-state-lib.sh.log` : logs complets.
- `repo/` : copie exacte utilisée par les essais, à l'exception de .git, .codex, AGENTS.md, graphify-out, caches et node_modules exclus pour l'isolation.

## Références officielles consultées

[Hooks Codex](https://learn.chatgpt.com/docs/hooks) : aliases des outils et variables, payloads apply_patch/PostToolUse/SubagentStop, limites des hooks asynchrones et décisions PreToolUse.

[Hooks Claude Code](https://code.claude.com/docs/en/hooks) : tool_response PostToolUse, agent_transcript_path SubagentStop, distinction parent/enfant et mode asyncRewake.

Les points de code et probes constituent les preuves principales. Les pages étaient les versions disponibles lors de la consultation; les contrats doivent être figés en fixtures de version pour éviter une nouvelle dérive.

## Couverture et limites

Tous les fichiers hooks/*.sh et le manifeste ont été parcourus avec leurs dépendances de frontière utiles : config, session files/state, miroir d'écriture, backend Haiku, profils et événements. Les bibliothèques de règles, sécurité de pack et CI n'ont pas fait l'objet d'un nouvel audit complet dans ce sous-périmètre, confié aux autres reviewers.

Pas de manipulation de l'UI Desktop, pas d'activation/confiance de hooks, pas de session réelle de génération Claude ou Codex, pas de campagne de performance, pas de test des MCP Sentry, pas de matrice Windows. Les labels « Hook N » et la confiance demandée par l'import sont traités par le reviewer principal. L'absence de nom dans hooks.json est confirmée; statusMessage est une description d'exécution, et sa présence ne doit pas être présentée sans test UI comme la garantie d'un nom d'élément dans l'inventaire.
