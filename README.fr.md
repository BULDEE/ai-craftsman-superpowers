# AI Craftsman Superpowers

<div align="center">

[🇬🇧 English](README.md) | 🇫🇷 **Français**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A51.0.33-blueviolet)](https://code.claude.com)
[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)
[![Commands](https://img.shields.io/badge/Commands-18%2B-orange)](COMMANDS-QUICK-REF.md)
[![Agents](https://img.shields.io/badge/Agents-6%2B-red)](#agents-spécialisés)
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

DDD, Clean Architecture et méthodologie TDD appliquées via des hooks, des commandes et un rules engine : pas seulement suggéré dans un prompt, mais réellement bloqué en cas de violation.

## Pourquoi Craftsman ? - 6 différenciateurs clés

Ce qui rend ce plugin réellement unique dans l'écosystème Claude Code :

1. **Correction Learning System** : enregistre chaque correction de violation que vous effectuez et injecte les tendances de correction au démarrage de la session suivante. Boucle de feedback adossée à SQLite qui apprend progressivement à Claude les patterns exacts que votre codebase rejette. La détection inter-fichiers suggère des corrections à l'échelle du projet quand 3 fichiers ou plus partagent la même violation.
2. **Rules Engine avec héritage à 3 niveaux** : surcharges Global → Projet → Répertoire. Forme courte (`PHP001: warn`) ou forme longue (règles regex custom). Le code legacy coexiste avec du code neuf strict via la relaxation par répertoire.
3. **Détecteur de biais cognitifs** : détection en temps réel du biais d'accélération, du scope creep et de la sur-optimisation dans vos prompts, bilingue FR/EN, contextuel pour réduire les faux positifs.
4. **Quality Gate temps réel** : validation progressive à 3 niveaux sur chaque Write/Edit : regex (<50ms, toujours actif) → analyse statique (<2s, PHPStan/ESLint) → architecture (<2s, deptrac/dependency-cruiser). Dégradation gracieuse sans aucun outil installé.
5. **Pipeline CI multi-provider** : le même rules engine tourne dans les hooks (temps réel) et en CI (pipeline) avec zéro dérive, sur GitHub Actions, GitLab CI, Bitbucket Pipelines et Jenkins.
6. **Métriques & analyse de tendances** : suivi SQLite des violations, corrections et sessions, avec vues de tendances à 7 et 30 jours pour identifier vos règles les plus violées.

> Aucun autre plugin Claude Code ne combine les 6 : apprentissage des erreurs passées, personnalisation des règles de niveau entreprise, protection cognitive, validation temps réel, zéro dérive CI, et tendances qualité mesurables.

## Prérequis

- Claude Code v1.0.33 ou plus récent (`claude --version` pour vérifier)

## Installation

```bash
# 1. Add the marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Install the plugin
/plugin install craftsman@BULDEE-ai-craftsman-superpowers

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

Les 6 différenciateurs ci-dessus fonctionnent avec **zéro coût API** au-delà de votre usage normal de Claude Code : validation regex, rules engine, détection de biais, export CI et métriques sont tous locaux.

Une couche optionnelle ajoute une analyse sémantique plus profonde via des hooks agents Haiku (violations de couches DDD, contexte d'erreur Sentry, revue d'architecture) : ~0,15-0,30 $ par session (50 opérations Write/Edit).

**Désactivation :** définissez `agent_hooks: false` dans la config du plugin. Tout le reste continue de fonctionner.

## Commandes

Toutes les commandes s'invoquent explicitement avec `/craftsman:nom-de-commande` (voir [ADR-0007](docs/adr/0007-commands-over-skills.md) pour la justification). Référence complète : [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md).

| Catégorie | Commandes |
|-----------|-----------|
| Méthodologie de base | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| Ingénierie AI/ML | `rag`, `mlops`, `agent-design` |
| Utilitaires | `metrics`, `setup`, `team`, `healthcheck`, `knowledge` |
| CI/CD | `ci` |

Les scaffolders proposent une variante de template avant de générer le code (ex. `bounded-context` vs `event-sourced` pour les entités) : voir [Template Variants](commands/scaffold.md#template-variants-v210).

## Agents spécialisés

Agents core (d'autres se chargent automatiquement avec les packs) : `team-lead` (orchestrateur), `architect` (DDD/Clean Architecture, lecture seule), `doc-writer` (ADR, README, CHANGELOG), `security-pentester`, `legacy-surgeon`, `ui-ux-director` : plus des reviewers/craftsmen spécifiques pour Symfony, React et AI/ML. Liste complète et model tiering : [référence des agents](docs/reference/agents.md).

## Rules Engine

Surchargez n'importe quelle règle par projet ou par répertoire avec l'héritage de config à 3 niveaux :

```
~/.claude/.craft-config.yml          ← Global defaults
  └─ {project}/.craft-config.yml     ← Project overrides
      └─ {dir}/.craft-rules.yml      ← Directory overrides
```

Forme courte : `PHP001: warn` / `TS001: ignore`. Forme longue : règles custom avec regex, sévérité, langages. Suppression ponctuelle en ligne avec `// craftsman-ignore: RULE_ID`.

## Intégration CI/CD

Même rules engine, zéro dérive entre hooks locaux et CI, 4 providers :

| Provider | Template |
|----------|----------|
| GitHub Actions | `craftsman-quality-gate.yml` |
| GitLab CI | `.gitlab-ci.craftsman.yml` |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` |
| Jenkins | `Jenkinsfile.craftsman` |

Utilisez `/craftsman:ci export` ou `craftsman-ci.sh init --provider` en CLI.

Également appliqué par des hooks : le [Circuit Breaker](docs/reference/hooks.md#circuit-breaker-v210) protège l'intégration Sentry pendant les pannes, et l'[Iron Law Pattern](docs/reference/hooks.md#iron-law-pattern-v210) bloque les changements d'architecture impulsifs faits sans passage préalable par `/craftsman:design`. Comportement complet des hooks, codes de sortie et IDs de règles : [référence des hooks](docs/reference/hooks.md).

## Avancé : Knowledge Base RAG (optionnel)

Un serveur MCP **optionnel** ajoute du RAG sur vos documents locaux. Totalement inerte tant que le pack `ai-ml` n'est pas activé : zéro erreur pour les utilisateurs qui n'en ont pas besoin.

```bash
brew install ollama && ollama pull nomic-embed-text
ollama serve

mkdir -p ~/.claude/ai-craftsman-superpowers/knowledge
cp ~/your-docs/*.pdf ~/.claude/ai-craftsman-superpowers/knowledge/
```

Voir le [guide Local RAG](docs/guides/local-rag-ollama.md) et la [référence MCP](docs/reference/mcp-servers.md) pour la mise en place complète, et [ADR-0002](docs/adr/0002-ollama-over-openai.md) pour la justification d'Ollama plutôt qu'un provider cloud.

## Configuration CLAUDE.md

Ordre de priorité : instruction utilisateur explicite → `CLAUDE.md` de projet → plugin (skills, hooks, knowledge) → `CLAUDE.md` global (`~/.claude/CLAUDE.md`).

Mettez le profil DISC/style de communication/biais personnels dans votre CLAUDE.md **global**, l'architecture/entités clés/règles projet dans votre CLAUDE.md **projet**, et laissez le **plugin** gérer l'application des règles de code et les design patterns. Guide complet : [CLAUDE.md Best Practices Guide](docs/guides/claude-md-best-practices.md).

## Décisions d'architecture

16 ADR couvrent le raisonnement derrière chaque choix de conception majeur : voir [`/docs/adr`](docs/adr/). Commencez par [ADR-0007: Commands over Skills](docs/adr/0007-commands-over-skills.md) et [ADR-0005: Knowledge-First Architecture](docs/adr/0005-knowledge-first-architecture.md) si vous évaluez la conception du plugin.

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

Les command hooks et agents reviewers sont en lecture seule, sauf pour la base de métriques locale et l'état de session. Les agent hooks (Haiku) ne modifient jamais de fichiers. Les violations bloquent (exit 2) ; la détection de biais avertit seulement (exit 0).

**Pas de télémétrie, pas d'analytics, pas de phone-home.** Avec `agent_hooks: false` et sans config Sentry, zéro activité réseau. Le contenu des fichiers édités n'atteint l'API Anthropic que si `agent_hooks: true` (défaut) ; Sentry n'est interrogé que si configuré ; les métriques et embeddings RAG ne quittent jamais votre machine. Détail complet : [SECURITY.md](SECURITY.md#data--network-transparency).

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

**Contraintes actuelles :** PHP/TypeScript ont une couverture de règles complète, les autres langages n'ont qu'un support basique ; le RAG exige Ollama (aucun provider d'embeddings cloud) ; les patterns de détection de biais sont EN/FR uniquement ; la correction automatique des violations et les plugins IDE ne sont pas supportés par conception.

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
