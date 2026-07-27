# AI Craftsman Superpowers

<div align="center">

[🇬🇧 English](README.md) | 🇫🇷 **Français**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.218-blueviolet)](https://code.claude.com)
[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)
[![Skills](https://img.shields.io/badge/Skills-21-orange)](COMMANDS-QUICK-REF.md)
[![Agents](https://img.shields.io/badge/Agents-12-red)](#agents-spécialisés)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Transformez Claude en Senior Software Craftsman discipliné**

[Démarrage rapide](#démarrage-rapide) •
[Commandes](#commandes) •
[Sécurité](#sécurité) •
[Contribution](#contribution)

</div>

> [!WARNING]
> N'installez ce plugin que depuis les sources officielles listées ci-dessous. Ne faites pas confiance aux forks, miroirs, ou "copies améliorées" distribuées ailleurs : voir [Vérification avant installation](#vérification-avant-installation).

---

## Un prompt demande. Ceci impose.

Vous pouvez écrire « toujours des classes final » dans votre `CLAUDE.md`. Claude
va s'y tenir, jusqu'à ce que le contexte se remplisse, ou que la tâche
s'allonge, ou qu'arrive le dixième fichier d'un refactor. Les instructions se
délitent. Ce n'est pas un problème de discipline, c'est un problème
d'architecture : rien dans la boucle ne vérifie.

Craftsman met la vérification dans la boucle. Les mêmes règles tournent en
hooks à chaque Write, en gate dans votre CI, et comme critères lus par les
agents de revue. Une violation n'est pas un rappel poli au paragraphe suivant :
les violations de couche et l'absence de `strict_types` sont refusées avant que
l'écriture n'aboutisse, le reste revient directement à Claude comme un constat
dont il doit répondre, et la même règle fait échouer votre pipeline si elle
atteint une pull request.

Trois conséquences en découlent, et ce sont elles qui distinguent ce plugin
d'un prompt bien écrit :

| | |
|---|---|
| **Il bloque** | Un seul rules engine, appliqué à l'identique en hooks et en CI. Aucune dérive entre ce que votre éditeur autorise et ce que votre pipeline refuse. |
| **Il apprend** | Chaque violation que vous corrigez est enregistrée. Un motif qui se répète sur plusieurs fichiers devient un instinct candidat que vous approuvez, et Claude cesse de commettre l'erreur au lieu qu'on la lui rappelle. |
| **Il prouve** | « Terminé » exige des preuves. Une tâche ne peut pas être marquée complète sans trace de vérification, et un test qui échoue révoque une trace existante. |

Le tout sur le modèle le moins cher capable de faire le travail : le mécanique
sur Haiku, l'application de patterns sur Sonnet, le jugement architectural sur
Opus. Vous ne choisissez pas, et vous ne payez pas le tarif Opus pour formater
un message de commit.

## Pourquoi Craftsman ? - Différenciateurs clés

Ce qui rend ce plugin réellement unique dans l'écosystème Claude Code :

1. **Correction Learning System (boucle fermée)** : enregistre chaque correction de violation, injecte les tendances au démarrage de session, et promeut les corrections récurrentes (3+ sur 3+ fichiers) en instincts candidats que vous validez dans `/craftsman:metrics`. Les instincts approuvés deviennent des skills projet avec provenance : Claude cesse de faire l'erreur au lieu d'en être rappelé.
2. **Rules Engine avec héritage à 3 niveaux** : surcharges Global → Projet → Répertoire. Forme courte (`PHP001: warn`) ou forme longue (règles regex custom). Le code legacy coexiste avec du code neuf strict via la relaxation par répertoire.
3. **Détecteur de biais cognitifs** : détection en temps réel du biais d'accélération, du scope creep et de la sur-optimisation dans vos prompts, bilingue FR/EN, contextuel pour réduire les faux positifs.
4. **Quality Gate temps réel** : validation progressive sur chaque Write/Edit : regex (<50ms, toujours actif) → sémantique LSP (en direct, si votre serveur de langage est installé) → analyse statique et architecture (PHPStan/ESLint/deptrac, activation explicite par machine car exécuter les analyseurs d'un projet revient à exécuter son code, voir [SECURITY.md](SECURITY.md)). Dégradation gracieuse sans aucun outil installé.
5. **Pipeline CI multi-provider** : la CI charge les mêmes validateurs de pack et le même rules engine que les hooks, et résout la sévérité fichier par fichier, donc un `.craft-rules.yml` de répertoire s'applique des deux côtés. GitHub Actions, GitLab CI et Bitbucket Pipelines ont des annotations natives ; Jenkins passe par l'adaptateur générique.
6. **Métriques & analyse de tendances** : suivi SQLite des violations, corrections et sessions, avec vues de tendances à 7 et 30 jours pour identifier vos règles les plus violées.
7. **Cliquet structurel** : un baseline committé enregistre le high-water mark structurel de chaque fichier (complexité, taille, plus longue fonction, fan-out d'imports, nombre de suppressions). Un fichier que vous touchez peut s'améliorer ou rester égal, jamais régresser : la marque se resserre automatiquement au passage vert et ne se desserre que par une suppression documentée et comptée. Appliqué à l'identique dans les hooks et en CI ; le legacy non touché n'est jamais puni pour une dette qu'il avait déjà.
8. **Panel de contradiction au design** : trois contradicteurs (YAGNI, invariants et frontières, faisabilité) attaquent le design pendant `/craftsman:design`, avant qu'une ligne existe. Chaque objection atterrit dans une table retenue ou écartée : le silence n'est pas une option. Contredire un design coûte bien moins cher que contredire le code bâti dessus.
9. **Sécurité et onboarding situationnel** : SEC001-003 (secrets en dur, eval dynamique, SQL par concaténation) vérifiés dans les hooks et en CI avec routage de la doctrine au blocage ; le setup observe le dépôt et pose au plus quatre questions en langage courant, et le mode guidé fait que chaque blocage s'explique.
10. **Tiering de modèle par tâche** : chaque skill déclare le modèle le moins cher capable de faire son travail et l'effort de réflexion associé, appliqué le temps de son exécution. Formater un commit tourne sur Haiku en effort `low` ; une revue d'architecture sur Opus en `high`. Les paliers sont des alias, donc ils suivent les sorties de modèles, et une variable d'environnement suffit à remapper un palier entier. Voir [Model Tiering Explained](docs/guides/model-tiering-explained.md).

> Aucun autre plugin Claude Code ne combine tout cela : apprentissage des erreurs passées, personnalisation des règles de niveau entreprise, protection cognitive, validation temps réel, zéro dérive CI, tendances qualité mesurables, et économie de modèle par tâche.


## Ouvrir un dépôt non fiable

Les hooks du plugin s'exécutent automatiquement : un dépôt cloné est donc une entrée non fiable (noms de fichiers, contenus, fichiers de config, et tout outil qu'il embarque). Deux capacités qui exécuteraient du code fourni par le dépôt sont éteintes sauf si **vous** les autorisez dans votre propre `~/.claude/.craft-config.yml`, et un fichier projet ne peut jamais les accorder :

| Capacité | Pourquoi elle est verrouillée |
|----------|-------------------------------|
| `trust_project_tools: true` | Le Level 2 exécute `vendor/bin/phpstan`, `node_modules/.bin/eslint` et les configs qu'ils découvrent seuls. La config plate d'ESLint est du JavaScript exécutable par conception ; `bootstrapFiles` de PHPStan charge du PHP arbitraire. |
| `packs.external[].path` | Les validators d'un pack externe sont sourcés comme du code shell. |

Tout le reste continue de fonctionner sur un dépôt non fiable : rules engine, règles de couches, de persistence et de sécurité, cliquet structurel, métriques et gate CI sont notre propre code. `tests/core/test-hostile-repo.sh` rejoue chaque attaque de ce modèle et vérifie qu'elle échoue. Détail complet : [SECURITY.md](SECURITY.md).

## Prérequis

- Claude Code v2.1.218 ou plus récent (`claude --version` pour vérifier). Versions plus anciennes : installez la branche gelée 3.9.x.
- `python3` 3.9 ou plus récent. Ce plancher est celui de `/usr/bin/python3` sur un Mac sans homebrew ; la CI importe chaque bibliothèque de hook sous 3.9, donc le plancher ne peut pas remonter en silence.
- `bash`, `grep`, `jq`, `sqlite3`. GNU coreutils n'est pas requis : le plugin fonctionne sur un macOS d'origine.

## Installation

```bash
# 1. Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Install the plugin
/plugin install craftsman@ai-craftsman-superpowers

# 3. Restart Claude Code
exit
claude
```

<details>
<summary>Installer depuis un clone local</summary>

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git /path/to/ai-craftsman-superpowers
/plugin marketplace add /path/to/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```
</details>

<details>
<summary>Vérifier l'installation</summary>

```bash
/plugin
# "Installed" tab → craftsman plugin should appear
# "Errors" tab → check here if skills don't appear
```
</details>

## Démarrage rapide

```bash
# Design a new entity (follows DDD phases)
/craftsman:design
I need to create a User entity for an e-commerce platform.

# Debug an issue systematically (ReAct pattern)
/craftsman:debug
I have a memory leak in my Node.js app.

# Review code for architecture issues
/craftsman:challenge
[paste your code]

# Run the full development workflow (design → spec → plan → implement → test → verify → commit)
/craftsman:workflow
I need to add a forgot password feature.

# Quick setup (zero questions, smart defaults)
/craftsman:setup --quick
```

Nouveau sur la méthodologie ? Commencez par le [guide débutant](docs/guides/beginner.md) : il présente les concepts DDD et les commandes de base avec des exemples travaillés. Voir [`/examples`](examples/) pour des exemples d'usage détaillés avec les sorties attendues, et [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md) pour la liste complète des commandes.

## Modèle de coût API (optionnel)

Les différenciateurs ci-dessus fonctionnent avec **zéro coût API** au-delà de votre usage normal de Claude Code : validation regex, rules engine, détection de biais, export CI et métriques sont tous locaux.

Une couche optionnelle ajoute une analyse sémantique plus profonde via des hooks agents Haiku (violations de couches DDD, contexte d'erreur Sentry, revue d'architecture) : ~0,15-0,30 $ par session (50 opérations Write/Edit).

**Désactivation :** définissez `agent_hooks: false` dans la config du plugin. Tout le reste continue de fonctionner.

## Commandes

Toutes les commandes s'invoquent explicitement avec `/craftsman:nom-de-commande`. Référence complète : [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md). En v4 elles deviennent des skills avec exécution forkée et injection de contexte en direct, invocations inchangées : voir [ADR-0017](docs/adr/0017-skills-over-commands.md).

| Catégorie | Commandes |
|-----------|-----------|
| Méthodologie de base | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| Ingénierie AI/ML | `rag`, `mlops`, `agent-design` |
| Utilitaires | `metrics`, `setup`, `team`, `healthcheck` |
| CI/CD | `ci` |

Les scaffolders proposent une variante de template avant de générer le code (ex. `bounded-context` vs `event-sourced` pour les entités) : voir [Template Variants](skills/scaffold/SKILL.md#template-variants-v210).

## Agents spécialisés

Agents core (d'autres se chargent automatiquement avec les packs) : `team-lead` (orchestrateur), `architect` (DDD/Clean Architecture, sans Write/Edit), `doc-writer` (ADR, README, CHANGELOG), `security-pentester`, `legacy-surgeon`, `ui-ux-director` : plus des reviewers/craftsmen spécifiques pour Symfony, React et AI/ML. Liste complète et model tiering : [référence des agents](docs/reference/agents.md).

## Rules Engine

Surchargez n'importe quelle règle par projet ou par répertoire avec l'héritage de config à 3 niveaux :

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Forme courte : `PHP001: warn` / `TS001: ignore`. Forme longue : règles custom avec regex, sévérité, langages. Suppression ponctuelle en ligne avec `// craftsman-ignore: RULE_ID`.

## Intégration CI/CD

La CI charge les mêmes validateurs de pack et le même rules engine que les
hooks : une règle ne peut pas vouloir dire une chose sur votre machine et une
autre dans le pipeline.

| Provider | Template | Adaptateur |
|----------|----------|------------|
| GitHub Actions | `craftsman-quality-gate.yml` | Natif : annotations inline et commentaire de PR |
| GitLab CI | `.gitlab-ci.craftsman.yml` | Natif : rapport code-quality et note de MR |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Natif : rapport de build |
| Jenkins | `Jenkinsfile.craftsman` | Générique : sortie de log et fichier markdown, sans annotations natives |

Utilisez `/craftsman:ci export` ou `craftsman-ci.sh init --provider` en CLI.

Également appliqué par des hooks : le [Circuit Breaker](docs/reference/hooks.md#circuit-breaker-v210) protège l'intégration Sentry pendant les pannes, et l'[Iron Law Pattern](docs/reference/hooks.md#iron-law-pattern-v210) bloque les changements d'architecture impulsifs faits sans passage préalable par `/craftsman:design`. Comportement complet des hooks, codes de sortie et IDs de règles : [référence des hooks](docs/reference/hooks.md).

## Le knowledge en bundle OKF

Le savoir méthodologique du plugin (Clean Architecture, DDD, persistence, legacy, refactoring) est livré en bundle [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) : du Markdown curé avec frontmatter YAML, versionné dans git, relu en PR. Un lookup déterministe route chaque règle vers le concept qui l'explique (un blocage LAYER004 pointe vers le doc repository-pattern), sans embedding, sans index, sans service externe. Vos propres outils de mémoire (Obsidian, claude-mem, tout consommateur OKF) lisent le bundle directement : c'est du Markdown sur disque.

## Configuration CLAUDE.md

Ordre de priorité : instruction utilisateur explicite → `CLAUDE.md` de projet → plugin (skills, hooks, knowledge) → `CLAUDE.md` global (`~/.claude/CLAUDE.md`).

Mettez le profil DISC/style de communication/biais personnels dans votre CLAUDE.md **global**, l'architecture/entités clés/règles projet dans votre CLAUDE.md **projet**, et laissez le **plugin** gérer l'application des règles de code et les design patterns. Guide complet : [CLAUDE.md Best Practices Guide](docs/guides/claude-md-best-practices.md).

## Nouveautés v4.0.0 - Le système craftsman auto-apprenant

v4 est une **rupture nette** ciblant Claude Code >= 2.1.218, sans rétrocompatibilité (la branche 3.9.x reste disponible et gelée). Les grandes lignes :

- **Boucle d'apprentissage fermée** : les corrections récurrentes deviennent des instincts candidats que vous validez dans `/craftsman:metrics` ; les instincts approuvés sont codifiés en skills projet. La détection reste automatique, la codification reste validée par un humain.
- **Architecture native-first** : les workflows deviennent des skills forkés avec injection de contexte en direct, et la vérification s'appuie sur `asyncRewake` et un gate `TaskCompleted`. La vérification sémantique tourne sur Haiku dans des sous-processus headless derrière des hooks `command` conditionnés, et non via les types de hooks natifs `agent`/`prompt` : ceux-ci n'offrent aucun gating par option de plugin et vous retireraient la possibilité de désactiver la vérification ([ADR-0018](docs/adr/0018-native-prompt-agent-hooks.md)).
- **Niveau 1.5 sémantique** : validation LSP entre le gate regex et l'analyse statique, activée uniquement sur les serveurs de langage déjà installés : le plugin orchestre l'outillage de votre stack, il ne s'y substitue jamais.
- **Discipline de contexte** : chaque injection plafonnée par des budgets configurables, chaque hook désactivable individuellement.

Plan complet et phases : [docs/v4-roadmap.md](docs/v4-roadmap.md). Décisions : ADR [0016](docs/adr/0016-v4-clean-break-native-first.md) à [0023](docs/adr/0023-deterministic-verification-loop.md). Changements cassants : [MIGRATION.md](MIGRATION.md).

## Décisions d'architecture

28 ADR couvrent le raisonnement derrière chaque choix de conception majeur : voir [`/docs/adr`](docs/adr/). Commencez par [ADR-0016: v4 Clean Break](docs/adr/0016-v4-clean-break-native-first.md) et [ADR-0005: Knowledge-First Architecture](docs/adr/0005-knowledge-first-architecture.md) si vous évaluez la conception du plugin.

## Utilisation avec le plugin Superpowers

Craftsman et [Superpowers](https://github.com/anthropics/claude-code-plugins/tree/main/superpowers) sont complémentaires et se chargent simultanément sans conflit. Superpowers gère l'orchestration de workflow (brainstorming, planification, TDD, développement piloté par subagents) ; Craftsman gère l'application de la qualité spécifique au domaine (règles DDD, validation architecturale, correction learning).

```
1. /superpowers:brainstorming     → Design the solution collaboratively
2. /superpowers:writing-plans     → Create implementation plan
3. /superpowers:subagent-driven-development → Execute with fresh subagents
   ├── Craftsman hooks fire on every Write/Edit (real-time quality gate)
   ├── /craftsman:design           → DDD modeling when domain entities appear
   └── /craftsman:challenge        → Architecture review at milestones
4. /craftsman:verify              → Evidence-based verification before commit
5. /superpowers:finishing-a-development-branch → PR and merge
```

## Philosophie

> "Des semaines de code peuvent économiser des heures de planification."

Design avant le code. Test-first. Débogage systématique plutôt que correctifs au hasard. YAGNI. Clean Architecture : les dépendances pointent vers l'intérieur. Make it work, make it right, make it fast, dans cet ordre.

Pragmatisme plutôt que dogmatisme : 80 % de couverture sur les chemins critiques vaut mieux que 100 % partout ; DDD pour les domaines complexes, pas pour tous ; concret d'abord, abstraction quand réellement nécessaire.

## Sécurité

Les command hooks n'écrivent que dans la base de métriques locale et l'état de session. Les agent hooks (Haiku) ne modifient jamais de fichiers. La détection de biais avertit seulement (exit 0). Les violations de couche et `strict_types` sont refusées avant l'écriture ; les autres règles remontent la violation à Claude après coup et font échouer la CI sur une pull request.

Chaque agent déclare son propre périmètre d'outils dans `tools:`. La plupart des craftsmen détiennent `Write`/`Edit`/`Bash` parce que leur métier est de modifier du code ; `architect` et `team-lead` n'ont ni `Write` ni `Edit`. Lisez la frontmatter de l'agent plutôt que de déduire un périmètre de son nom.

**Pas de télémétrie, pas d'analytics, pas de phone-home.** Avec `agent_hooks: false` et sans config Sentry, zéro activité réseau. Le contenu des fichiers édités n'atteint l'API Anthropic que si `agent_hooks: true` (défaut) ; Sentry n'est interrogé que si configuré ; les métriques ne quittent jamais votre machine. Détail complet : [SECURITY.md](SECURITY.md#data--network-transparency).

### Vérification avant installation

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git
cd ai-craftsman-superpowers

# Review hooks - the only executable code
cat hooks/bias-detector.sh hooks/post-write-check.sh hooks/pre-write-check.sh hooks/session-metrics.sh

# Verify no network calls
grep -r "curl\|wget\|fetch\|http" hooks/
# Should return nothing (hooks are 100% local)
```

## Limitations connues

**Par conception :** les violations de règles de code bloquent, la détection de biais avertit seulement ; pas d'auto-commit ; les commandes sont explicitement invoquées, jamais auto-déclenchées ; la méthodologie est opinionated (DDD/Clean Architecture).

**Contraintes actuelles :** PHP/TypeScript ont une couverture de règles complète, les autres langages n'ont qu'un support basique ; les métriques sont locales à la machine, pas partagées entre équipiers ; les patterns de détection de biais sont EN/FR uniquement ; la correction automatique des violations et les plugins IDE ne sont pas supportés par conception.

Plus de détails dans la [FAQ](FAQ.md).

## Contribution

Les contributions sont bienvenues : c'est un projet open source.

1. Forkez le dépôt
2. Créez une branche de feature
3. Suivez la méthodologie craftsman (`/craftsman:design` d'abord !)
4. Ajoutez des tests pour les nouvelles fonctionnalités
5. Soumettez une PR

Voir [CONTRIBUTING.md](CONTRIBUTING.md) pour les directives détaillées. Envie de contribuer ? Nouvelles skills pour d'autres frameworks (Django, Rails, Go), support de langages additionnels pour les hooks, exemples et documentation, tests d'intégration, et traductions sont tous bienvenus.

## Dépannage

Déplacé vers [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Licence

Apache License 2.0 : voir [LICENSE](LICENSE)

## Support

- Discord : [rejoignez la communauté](https://discord.gg/eBpgHAGu)
- Issues : [GitHub Issues](https://github.com/BULDEE/ai-craftsman-superpowers/issues)
- Discussions : [GitHub Discussions](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)
- Documentation : [Claude Code Plugins](https://code.claude.com/docs/en/plugins)

## Sponsors

| Sponsor | Description |
|---------|-------------|
| **[BULDEE](https://buldee.com)** | Construire le futur du développement assisté par IA |
| **[Time Hacking Limited](https://thelabio.com)** | Maximiser la productivité des développeurs |

Envie de sponsoriser ? [Contactez-nous](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)

## Remerciements

Construit selon les [directives officielles des plugins Anthropic](https://code.claude.com/docs/en/discover-plugins), inspiré des principes DDD, Clean Architecture et TDD. Merci à tous les contributeurs et sponsors !

---

**Fait avec craftsmanship par [Alexandre Mallet](https://github.com/woprrr)**

*Sponsorisé par [BULDEE](https://buldee.com) & [Time Hacking Limited](https://thelabio.com)*
