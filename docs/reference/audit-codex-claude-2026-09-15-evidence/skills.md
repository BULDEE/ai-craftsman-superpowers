# Audit compatibilité Craftsman 4.10.3 : skills, agents, packaging

Date : 2026-09-15. Dépôt : `/Users/woprrr/Dev/claude/ai-craftsman-superpowers`, HEAD de départ `879e432`. Audit sans modification produit.

**Verdict : REQUEST_CHANGES.** L'import a conservé un plugin Claude Code largement lisible par Codex, mais il n'a pas rendu ses workflows équivalents. Deux ruptures prioritaires concernent l'orchestration et la boucle d'apprentissage. Trois skills de pack disparaissent silencieusement, et le contexte automatique de la revue n'est pas collecté dans cette session.

## Preuves runtime et portée

- Binaire de la sonde : **`codex-cli 0.154.0`**, obtenu par `codex --version`. Ce binaire global est distinct du binaire embarqué dans ChatGPT Desktop que le parent a identifié comme `0.154.0-alpha.6.2`. La sonde CLI confirme son propre consommateur, et le catalogue injecté de la session Desktop confirme également 19 skills Craftsman.
- Import installé : `/Users/woprrr/.codex/plugins/cache/ai-craftsman-superpowers/craftsman/4.10.3`.
- Comparaison des fichiers sous `skills`, `agents`, `knowledge`, `packs`, `scripts`, `.claude-plugin` : contenu source identique entre dépôt, cache Codex et cache Claude 4.10.3, hors deux fichiers Python compilés de développement. Les Markdown n'ont pas été convertis.
- Inventaire : 22 entrées de skills, dont 19 core et 3 liens de pack AI; 12 fichiers agents, dont 6 liens de packs; 41 Markdown de knowledge core; 38 Markdown de packs, dont 6 templates.
- `skills/list` avec `forceReload: true` : **19 skills Craftsman enabled, zéro erreur**. Absents : `agent-design`, `mlops`, `rag`.
- Fixture avec contrôle positif : un vrai `SKILL.md` et un dossier de skill symbolique apparaissent. Un fichier `SKILL.md` symbolique n'apparaît pas. Remplacer uniquement ce lien par le contenu identique fait apparaître le skill. Remettre le lien le fait disparaître. Aucun message d'erreur dans les trois états.
- Une fixture valide `.claude/skills/audit-claude-local/SKILL.md` reste absente; le témoin `.agents/skills/audit-regular/SKILL.md` est chargé.
- Aucune requête de modèle, aucun hook exécuté par la sonde, aucune modification de confiance ou activation. Le serveur local utilise une base SQLite temporaire via l'option documentée `sqlite_home`; seul le démarrage du processus a nécessité une exécution hors sandbox.

Fichiers de preuve :

- Programme : `/tmp/craftsman-skill-probe.py`.
- Schémas du consommateur : `/tmp/craftsman-skills-schema/`.
- Réponses filtrées : `/var/folders/m0/dvzhx8xn2158tyvxywfskdc40000gn/T/craftsman-skill-consumer-npe7rmk2/result-2.json` (liens), `result-3.json` (plugin importé), `result-4.json` (copie réelle), `result-5.json` (lien réintroduit).
- À la demande du parent, la même sonde a enregistré `/tmp/craftsman-live-hooks-list.json` : **14 handlers Craftsman enabled/trusted**, sans erreur ou warning Craftsman. L'état a évolué depuis les captures fournies. L'audit n'a activé aucun hook. Le parent traite la différence et les libellés UI.

## P1 : l'orchestration importée impose le protocole de Claude Code

**Emplacements :** `skills/team/SKILL.md:15`, `skills/team/SKILL.md:42`, `skills/team/SKILL.md:189`, `skills/team/SKILL.md:208`; `agents/team-lead.md:78`. La configuration locale importée ajoute `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"` dans `.codex/config.toml:5`.

**Problème :** le skill considère ce seul flag comme preuve de disponibilité d'une équipe Claude, interdit la dégradation quand il est présent et exige `TaskCreate`, `TaskUpdate`, `Agent`, `SendMessage` ainsi que les fichiers `~/.claude/teams/session-*/config.json`. Cette session Codex offre `collaboration.spawn_agent`, `send_message`, `followup_task`, `list_agents`, avec un contrat distinct. Le flag importé ne crée pas ces outils Claude.

Les 12 agents Markdown sont bien sur disque, mais aucun rôle `craftsman:*` n'est proposé dans les `agent_type` de cette session. Le dépôt et son cache ne contiennent pas d'export d'agents `.codex/agents/*.toml`. Le dispatch prescrit vers `craftsman:architect`, `craftsman:security-pentester`, `craftsman:team-lead` ne peut donc pas être exécuté tel qu'écrit ici. Lire leur prompt puis le transmettre à un agent générique reste possible; le plugin ne formalise pas ce chemin.

**Impact :** les workflows team, parallel et les délégations de challenge perdent leurs spécialistes et leur contrat de coordination. Un agent qui improvise le mapping peut omettre le contexte, les restrictions ou le contrat de livraison.

**Correction :** conserver les prompts de domaine partagés, ajouter une entrée d'orchestration par hôte qui sélectionne les outils réellement disponibles et exporte les rôles au format du consommateur. Pour Codex, produire des TOML `name`, `description`, `developer_instructions`, avec les paramètres de session appropriés, ou injecter explicitement le prompt du spécialiste dans un rôle générique. Vérifier un dispatch réel et son retour, y compris les droits et la visibilité du diff. Ne pas déduire la disponibilité de l'API d'un flag Claude copié.

**Source officielle :** [Subagents Codex](https://learn.chatgpt.com/docs/agent-configuration/subagents) décrit les agents TOML et les paramètres hérités. [Plugins reference Claude Code](https://code.claude.com/docs/en/plugins-reference) documente les agents Markdown et leurs champs propres. Le problème constaté est celui des rôles exposés dans cette installation, sans prétendre que Codex ne supporte pas les sous-agents.

## P1 : apprentissage et conventions écrivent dans une surface que Codex ne découvre pas

**Emplacements :** `skills/setup/SKILL.md:37`, `skills/metrics/SKILL.md:278`, `skills/metrics/SKILL.md:298`; `hooks/lib/instincts.py:280`.

**Problème :** setup génère les conventions dans `.claude/skills`, metrics approuve les apprentissages dans le même répertoire et promeut les apprentissages globaux dans `~/.claude/skills`. La fonction `_resolve_skills_dir` exige littéralement que le parent soit `.claude`. Elle refuse même la destination Codex documentée à l'intérieur du projet.

**Preuve :** appel direct de `_resolve_skills_dir` sans écriture : `<repo>/.claude/skills` accepté; `<repo>/.agents/skills` rejeté avec code 1 et message indiquant d'utiliser `.claude/skills`. La sonde `skills/list` ne découvre pas le témoin `.claude/skills`, tandis que son contrôle `.agents/skills` est chargé.

**Impact :** le développeur peut approuver une correction et voir un fichier généré, puis ne jamais bénéficier de son apprentissage dans Codex. Une fonctionnalité différenciante devient une écriture sans consommateur.

**Correction :** résoudre explicitement la destination par hôte en conservant les frontières de répertoire et les validations de provenance. Générer dans `.agents/skills` pour Codex et `.claude/skills` pour Claude Code. En environnement partagé, choisir une source unique plus des dossiers symboliques supportés, ou un export déterministe. Ajouter une preuve de découverte après approbation; une validation du seul chemin ou du YAML ne suffit pas.

**Source officielle :** [Build skills, emplacements locaux](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills). L'absence de découverte est également mesurée sur `codex-cli 0.154.0`.

## P2 : les liens symboliques de fichiers masquent les 3 skills du pack AI

**Emplacements :** `hooks/lib/pack-loader.sh:512`; `skills/agent-design/SKILL.md:1`, `skills/mlops/SKILL.md:1`, `skills/rag/SKILL.md:1` sont des liens vers `packs/ai-ml/commands/*.md`.

**Problème :** le packaging expose le point d'entrée `SKILL.md` comme fichier symbolique. Le consommateur Codex testé ignore cette forme alors qu'il suit les dossiers symboliques.

**Preuve :** les 3 fichiers cibles existent, leurs liens se résolvent et leurs corps sont identiques aux sources Claude. Ils sont absents de `skills/list` et du catalogue Desktop. La substitution fichier réel -> lien -> fichier réel a isolé la cause sans changer le contenu. Voir les résultats 2, 4 et 5.

**Impact :** le pack AI semble installé mais RAG, MLOps et agent-design ne sont pas découvrables. L'absence ne produit aucune erreur de chargement.

**Correction :** livrer un vrai `SKILL.md` généré de manière déterministe, ou réorganiser les sources sous forme de dossiers de skills puis lier les dossiers. Vérifier 22 entrées via le consommateur lors du packaging et réintroduire une fixture de fichier symbolique pour maintenir la preuve négative.

**Source officielle :** [Build skills](https://learn.chatgpt.com/docs/build-skills) documente le support des dossiers symboliques. La restriction des fichiers symboliques provient de l'expérience ci-dessus; il ne faut pas transformer cela en affirmation générale que Codex ne supporte aucun lien symbolique.

## P2 : challenge suppose un contexte dynamique qui est resté du texte

**Emplacements :** `skills/challenge/SKILL.md:30`, `skills/challenge/SKILL.md:105`, `skills/challenge/SKILL.md:110`.

**Problème :** le skill déclare cinq commandes `!` suivies de backticks pour injecter codemap, diff, commits et violations. Le contenu transmis dans cette session contient toujours les commandes littérales. Il affirme ensuite que les données sont déjà injectées et demande d'éviter leur collecte.

**Impact :** la revue peut être pondérée par un historique inexistant dans le contexte et omettre une collecte nécessaire. L'audit présent a dû réaliser explicitement ses lectures.

**Correction :** rendre le bootstrap explicite et idempotent : exécuter la collecte si les résultats ne sont pas présents, faire apparaître l'indisponibilité de chaque source et ne jamais prétendre qu'une commande affichée est son résultat. L'adaptateur Claude peut conserver son injection native; le chemin portable doit savoir collecter la même sortie.

**Source officielle :** [Skills Claude Code, dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context) documente cette extension. Pour Codex, le constat porte sur le contenu réellement reçu, sans extrapoler à toutes les versions ou voies d'invocation.

## P3 : autres adaptations à cadrer, sans faux verdict de support

- `skills/*/SKILL.md:2` et `.github/workflows/ci.yml:383` : modèles `opus`, `sonnet`, `haiku`, effort et 15 `disable-model-invocation: true` core restent inchangés. Le CI valide volontairement les alias Claude. Codex charge les 19 skills malgré ces métadonnées; cela ne prouve pas leur sémantique. Prévoir une table de correspondance testée et, pour le contrôle d'invocation, la politique Codex documentée `agents/openai.yaml: policy.allow_implicit_invocation`. Aucun appel modèle n'a été effectué pour mesurer le choix de modèle.
- `skills/setup/SKILL.md:242`, `skills/verify/SKILL.md:150`, `skills/metrics/SKILL.md:24` : les ponts `~/.claude/craftsman-*` et la configuration globale Claude constituent une dépendance d'installation à vérifier sur machine Codex seule. Ce poste a déjà Claude Code, donc son succès ne démontrerait pas l'absence de dépendance. Les alias `CLAUDE_PLUGIN_ROOT` et `CLAUDE_PLUGIN_DATA` sont documentés côté Codex et ne doivent pas être présentés comme des erreurs en eux-mêmes.
- `.github/PULL_REQUEST_TEMPLATE.md:21`, `.github/ISSUE_TEMPLATE/bug_report.md:15` : la preuve demandée reste uniquement Claude Code. Ajouter l'hôte, sa version, l'origine de l'import et des tests de découverte/invocation Codex. La suite statique ne suffit pas pour annoncer une parité.

## Points forts et décision de conception

- L'import legacy est réel : les 19 skills core sont reconnus et activés. L'absence de `.codex-plugin/plugin.json` n'est donc pas en elle-même une panne dans cette voie d'import.
- Les prompts méthodologiques et le corpus Markdown sont partageables; les pertes se concentrent aux frontières d'exécution et de découverte.
- `scripts/export-hermes-skills.sh:21` fournit déjà un export déterministe de prompts partagés avec références réécrites. C'est une couture réutilisable pour un export Codex ciblé, sans dupliquer les connaissances ni remplacer globalement chaque occurrence de Claude par Codex.
- Le contrat de livraison de challenge et les budgets explicites des agents protègent des revues silencieuses. Conserver ces comportements dans les agents Codex, même lorsque les champs d'hôte changent.
- `scripts/release-build.sh:47` utilise une archive Git et un gzip reproductible; `scripts/bump-version.sh` centralise les versions de la distribution actuelle. Une seconde distribution devra intégrer son manifeste à ce mécanisme et démontrer sa consommation.

## Limites de couverture

Lecture détaillée des frontières de discovery, team, challenge, setup, metrics, des frontmatters de tous les skills et agents, des manifestes et scripts de packaging concernés. Inventaire et recherche transversale du corpus knowledge/templates/packs pour les dépendances d'hôte. Ce rapport ne prétend pas avoir vérifié sémantiquement chaque exemple métier de ces 79 Markdown, ni exécuté les 22 workflows complets.

Non exécutés : dispatch des spécialistes inexistants dans le catalogue, requêtes de modèle pour model/effort, génération de conventions réelle dans le projet utilisateur, approbation d'instinct réel, nouveau packaging publié, matrice Windows/Linux, revalidation complète du runtime Claude Code. Les hooks shell et la UI des captures sont traités par les autres volets de l'audit.

**Bilan : 2 P1, 2 P2 confirmés, 3 axes P3 de compatibilité à vérifier. REQUEST_CHANGES avant de revendiquer la parité Codex et Claude Code.**
