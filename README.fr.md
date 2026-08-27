<div align="center">

<a href="https://ai-craftsman.dev">
  <img src="https://raw.githubusercontent.com/BULDEE/ai-craftsman-superpowers/main/.github/assets/github-banner.png" alt="AI Craftsman Superpowers - un prompt demande, ceci impose" width="100%">
</a>

[🇬🇧 English](README.md) | 🇫🇷 **Français**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.218-blueviolet?logo=claude)](https://code.claude.com)
[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)

**Claude écrit le code. Vos règles d'architecture décident de ce qui atterrit.**

Pour les équipes qui font tourner Claude Code sur une base où une violation de
couche coûte plus cher que la fonctionnalité elle-même.

[Site](https://ai-craftsman.dev) •
[Installation](#installation) •
[Commandes](#commandes) •
[Docs](https://ai-craftsman.dev/docs) •
[Contribution](#contribution)

</div>

---

## Un prompt demande. Ceci impose.

Vous pouvez écrire « toujours des classes final » dans votre `CLAUDE.md`. Claude
va s'y tenir, jusqu'à ce que le contexte se remplisse, que la tâche s'allonge, ou
qu'arrive le dixième fichier d'un refactor. Les instructions se dégradent. Ce
n'est pas un problème de discipline, c'est un problème d'architecture : rien dans
la boucle ne vérifie.

Craftsman met la vérification dans la boucle. Les mêmes règles tournent en hooks
sur chaque Write, en garde-fou dans votre CI, et comme critères lus par un agent
relecteur. Les violations de couche et l'absence de `strict_types` sont refusées
avant que l'écriture atterrisse, le reste est rendu directement à Claude comme un
constat auquel il doit répondre, et la même règle fait échouer votre pipeline si
elle atteint une pull request.

## Voyez-le refuser

Claude tente d'écrire une entité qui importe depuis la couche infrastructure. Le
fichier n'atteint jamais votre disque :

<img src="https://raw.githubusercontent.com/BULDEE/ai-craftsman-superpowers/main/.github/assets/craftsman-demo.gif" alt="Le hook pre-write refuse une entité domaine qui importe l'infrastructure, puis accepte le fichier corrigé" width="100%">

<details>
<summary>La même exécution, en texte</summary>

```console
$ ./check.sh User.before.php.txt /srv/app/src/Domain/User/User.php

🚫 BLOCKED by AI Craftsman - 2 violation(s) detected before write:
  ✗ LAYER001: Domain imports Infrastructure - DDD layer violation
  ✗ PHP001: Missing declare(strict_types=1) in class file
Fix these before writing. Use // craftsman-ignore: <RULE_ID> to suppress.
exit=2
```

Ce n'est pas une maquette : l'enregistrement fait passer deux fichiers d'essai dans
`hooks/pre-write-check.sh` et montre ce qui en sort. Le code de sortie 2 est le
refus.

</details>

Claude lit les deux mêmes lignes que vous, corrige l'import et réécrit. La
correction est enregistrée ; si cette règle revient sur plusieurs fichiers, elle
vous est proposée comme instinct candidat dans `/craftsman:metrics`. Et si la
violation atteint une pull request à la place, la règle identique fait échouer le
pipeline : un seul moteur, un seul verdict, zéro dérive entre votre éditeur et
votre CI.

## Face à ce que vous avez déjà

Votre vraie alternative n'est pas un autre plugin. C'est le `CLAUDE.md` que vous
avez déjà écrit, et les linters que vous faites déjà tourner.

| | CLAUDE.md seul | Linter et CI | Craftsman |
|---|---|---|---|
| Tient encore au fichier 300 d'un refactor | non | oui | oui |
| Claude voit la violation *avant* d'écrire | non | non | oui |
| Même verdict sur votre machine et dans le pipeline | n/a | partiel | oui |
| Empêche Claude de refaire la même erreur | non | non | oui |
| Bloque une décision d'architecture prise sans passe de design | non | non | oui |

## Ce qu'il fait vraiment

**Il bloque.** Un seul moteur de règles, appliqué à l'identique en hooks et en CI.
Aucune dérive entre ce que votre éditeur autorise et ce que votre pipeline
refuse. GitHub, GitLab et Bitbucket reçoivent des annotations natives ; Jenkins
passe par l'adaptateur générique.

**Il apprend.** Chaque violation corrigée est enregistrée localement. Une
correction qui revient 3 fois sur 3 fichiers devient un instinct candidat que
vous validez dans `/craftsman:metrics`, puis un skill projet avec provenance. La
détection est automatique, la codification reste sous contrôle humain.

**Il prouve.** « Terminé » exige des preuves. Une tâche ne peut pas être marquée
complète sans trace de vérification, et un test qui échoue révoque une trace
existante.

Et chaque travail tourne sur le modèle le moins cher qui en est capable :
formater un commit sur Haiku en effort faible, une revue d'architecture sur Opus
en effort élevé. Vous ne payez jamais le tarif Opus pour un message de commit.

<details>
<summary><b>Sept autres mécanismes</b> : le moteur de règles, le cliquet structurel, le panel de design adverse, la détection de biais, et trois autres</summary>

<br>

1. **Moteur de règles à 3 niveaux d'héritage** : Global → Projet → Répertoire. Forme courte (`PHP001: warn`) ou forme longue (règles regex personnalisées). Le code hérité coexiste avec du code strict via une relaxation au niveau répertoire.
2. **Cliquet structurel** : une baseline committée (`.craftsman-baseline.json`) enregistre le plus haut niveau structurel de chaque fichier (complexité, taille, plus longue fonction, fan-out d'imports, nombre de suppressions). Un fichier que vous touchez peut s'améliorer ou rester égal, jamais régresser : la marque se resserre automatiquement sur un passage vert et ne se desserre que par une suppression documentée et comptée. Le code hérité non touché n'est jamais puni pour une dette qu'il avait déjà.
3. **Panel de design adverse** : trois contradicteurs (YAGNI, invariants et frontières, faisabilité) attaquent un design pendant `/craftsman:design`, avant qu'une ligne de code existe. Chaque objection atterrit dans un tableau retenue ou écartée : le silence n'est pas une option. Contredire un design coûte bien moins cher que contredire le code bâti dessus.
4. **Détecteur de biais cognitifs** : détection en temps réel du biais d'accélération, du scope creep et de la sur-optimisation dans vos prompts. Cascade linguistique à deux étages : les patterns curés en anglais vous avertissent directement, et toutes les autres langues occupent un seul et même étage derrière, avec des lexiques de rappel (CJK, cyrillique et thaï inclus) qui confient la décision au modèle lisant déjà votre prompt, lequel la remonte ou l'écarte en silence avec toute la session en contexte. Aucun second modèle, aucun appel réseau. Les tags de langue suivent BCP 47, donc `fr-CA` ou `zh-Hant` s'enregistrent comme n'importe quel autre. Ajouter une langue, c'est deux fichiers de données et zéro ligne de code.
5. **Contrôle qualité en temps réel** : validation progressive sur chaque Write/Edit : regex (<50ms, toujours active) → sémantique LSP (via le plugin LSP officiel de votre langage) → analyse statique et architecture (PHPStan/ESLint/deptrac, à activer machine par machine parce que lancer les analyseurs d'un projet exécute son code, voir [SECURITY.md](SECURITY.md)). Se dégrade proprement sans aucun outil installé.
6. **Métriques et tendances** : suivi SQLite des violations, corrections et sessions, avec des vues 7 jours / 30 jours pour identifier vos règles les plus violées.
7. **Règles de sécurité** : SEC001-003 (secrets en dur, eval dynamique, SQL par concaténation) vérifiées en hooks et en CI, avec leur doctrine routée vers Claude au blocage. `/craftsman:setup` observe le dépôt et pose au plus quatre questions en langage clair.

</details>

## Installation

> [!WARNING]
> N'installez ce plugin que depuis les sources officielles ci-dessous. Ne faites
> pas confiance aux forks, miroirs ou « copies améliorées » distribuées ailleurs.
> Étapes de vérification : [SECURITY.md](SECURITY.md#pre-installation-verification).

```bash
# 1. Ajouter la marketplace
/plugin marketplace add BULDEE/ai-craftsman-superpowers

# 2. Installer le plugin
/plugin install craftsman@ai-craftsman-superpowers

# 3. Redémarrer Claude Code, puis configurer
exit
claude
/craftsman:setup --quick
```

**Vous faites tourner des agents [Hermes](https://hermes-agent.nousresearch.com) au lieu de (ou à côté de) Claude Code ?** Le même dépôt est un plugin Hermes natif :

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman
hermes plugins enable craftsman
```

Votre agent autonome reçoit la même porte (impossible de conclure un tour de code qui laisse des violations critiques), la boucle d'apprentissage des corrections, `/craftsman` à la demande et sept skills craftsman sélectionnées selon la situation. Prise en main en cinq minutes : [Hermes quickstart](docs/guides/hermes-quickstart.md) ; un tour complet bloqué-corrigé-appris : [examples/hermes-agent](examples/hermes-agent/01-blocked-turn.md) ; conception et modèle de menace : [adapters/hermes/README.md](adapters/hermes/README.md). Le guide [For non-developers](docs/guides/for-non-developers.md) explique la valeur du plugin sans jargon, pour les profils non techniques.

C'est toute l'installation. `--quick` lit votre dépôt et choisit les défauts ;
lancez `/craftsman:setup` sans l'option pour répondre à quatre questions en
langage clair.

<details>
<summary>Prérequis, installation locale, et vérification</summary>

<br>

**Prérequis**

- Claude Code v2.1.218 ou plus (`claude --version`). Versions antérieures : installez la ligne 3.9.x gelée.
- `python3` 3.9 ou plus. C'est le plancher parce que c'est ce que `/usr/bin/python3` fournit sur un Mac sans homebrew ; la CI importe chaque bibliothèque de hook sous 3.9 pour que le plancher ne monte pas en silence.
- `bash`, `grep`, `jq`, `sqlite3`. GNU coreutils n'est pas requis : le plugin tourne sur un macOS d'origine.

**Installation depuis un clone local**

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git /chemin/vers/ai-craftsman-superpowers
/plugin marketplace add /chemin/vers/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```

**Vérifier**

```bash
/plugin
# Onglet "Installed" → le plugin craftsman doit apparaître
# Onglet "Errors" → à consulter si les skills n'apparaissent pas
```

</details>

## Démarrage rapide

```bash
# Le cycle complet : design → spec → plan → implémentation → tests → vérification → commit
/craftsman:workflow
Je dois ajouter une fonctionnalité de mot de passe oublié.
```

À ce stade tous les hooks tournent déjà. Points d'entrée individuels quand vous
ne voulez pas le cycle entier : `/craftsman:design` (modélisation DDD),
`/craftsman:debug` (investigation systématique), `/craftsman:challenge` (revue
d'architecture), `/craftsman:verify` (preuves avant de déclarer terminé).

Nouveau sur la méthodologie ? Le [guide débutant](docs/guides/beginner.md)
déroule les concepts DDD avec des exemples travaillés, et
[`/examples`](examples/) montre chaque commande avec sa sortie attendue.

## Commandes

Toutes les commandes sont invoquées explicitement, jamais déclenchées
automatiquement. Référence complète : [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md).

| Catégorie | Commandes |
|-----------|-----------|
| Méthodologie | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| Ingénierie AI/ML | `rag`, `mlops`, `agent-design` |
| Utilitaires | `metrics`, `setup`, `team`, `healthcheck` |
| CI/CD | `ci` |

Les générateurs (`/craftsman:scaffold`) proposent une variante de gabarit avant de générer le code
(`bounded-context` ou `event-sourced` pour une entité, par exemple). Les agents
derrière ces commandes : `team-lead`, `architect` (sans Write/Edit),
`doc-writer`, `security-pentester`, `legacy-surgeon`, `ui-ux-director`, plus les
agents relecteurs spécifiques aux packs Symfony, React et AI/ML. Liste complète :
[référence des agents](docs/reference/agents.md).

## Moteur de règles

Surchargez n'importe quelle règle par projet ou par répertoire, avec 3 niveaux
d'héritage :

```
~/.claude/.craft-config.yml          ← Défauts globaux
  └─ {projet}/.craft-config.yml      ← Surcharges projet
      └─ {dir}/.craft-rules.yml      ← Surcharges répertoire
```

Forme courte : `PHP001: warn` / `TS001: ignore`. Forme longue : règles
personnalisées avec regex, sévérité, langages. Supprimez une occurrence unique
en ligne avec `// craftsman-ignore: RULE_ID`.

## Intégration CI/CD

La CI source les mêmes validateurs de pack et le même moteur de règles que les
hooks, donc une règle ne peut pas vouloir dire une chose sur votre machine et
une autre dans le pipeline. Exportez un pipeline avec `/craftsman:ci export`.

| Fournisseur | Template | Adaptateur |
|-------------|----------|------------|
| GitHub Actions | `craftsman-quality-gate.yml` | Natif : annotations inline et commentaire de PR |
| GitLab CI | `.gitlab-ci.craftsman.yml` | Natif : rapport code-quality et note de MR |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Natif : rapport de build |
| Jenkins | `Jenkinsfile.craftsman` | Générique : log brut et fichier markdown |

## Coût et confidentialité

Tout ce qui précède fonctionne à **coût API nul** au-delà de votre usage normal
de Claude Code : validation regex, moteur de règles, détection de biais, export CI et
métriques sont locaux. Une couche optionnelle ajoute de l'analyse sémantique via
des agent hooks Haiku, autour de 0,15 à 0,30 dollar par session de 50 opérations
Write/Edit. Désactivez-la avec `agent_hooks: false`, tout le reste continue.

**Aucune télémétrie, aucune analytique, aucun phone-home.** Les métriques ne
quittent jamais votre machine. Le contenu des fichiers édités n'atteint l'API
Anthropic que si `agent_hooks: true`. Les command hooks n'écrivent que dans la
base de métriques locale et l'état de session.

Un dépôt cloné est une entrée non fiable, donc les deux capacités qui
exécuteraient du code fourni par le dépôt (`trust_project_tools` et les chemins
de packs externes) restent désactivées tant que **vous** ne les activez pas dans
votre config globale, et un fichier projet ne peut jamais les accorder.
`tests/core/test-hostile-repo.sh` reproduit chaque attaque couverte par ce modèle
et vérifie qu'elle échoue. Détail complet : [SECURITY.md](SECURITY.md).

## Limites connues

**Par choix :** les violations de règles bloquent, la détection de biais se
contente d'avertir ; pas d'auto-commit ; les commandes sont invoquées
explicitement, jamais déclenchées seules ; la méthodologie assume ses partis
pris (DDD/Clean Architecture).

**Contraintes actuelles :** PHP et TypeScript ont une couverture de règles
complète, les autres langages un support de base ; la détection de biais
avertit directement en anglais et laisse le modèle arbitrer toutes les autres
langues en contexte ; les métriques sont par machine, pas partagées en
équipe ; l'auto-correction des violations et les plugins IDE ne sont pas
supportés, par choix.

Plus de détail dans la [FAQ](FAQ.md).

## Pour aller plus loin

| | |
|---|---|
| [Nouveautés v4](https://github.com/BULDEE/ai-craftsman-superpowers/releases/latest) | Rupture nette visant Claude Code >= 2.1.218 : boucle d'apprentissage fermée, skills natifs, Level 1.5 sémantique, budgets de contexte. Changements cassants dans [MIGRATION.md](MIGRATION.md). |
| [Décisions d'architecture](docs/adr/) | 28 ADR couvrant chaque choix majeur. Commencez par [ADR-0016](docs/adr/0016-v4-clean-break-native-first.md) et [ADR-0005](docs/adr/0005-knowledge-first-architecture.md). |
| [Bundle de connaissance](knowledge/) | La méthodologie est livrée en bundle [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) : du Markdown versionné dans git, lisible par Obsidian ou n'importe quel consommateur OKF. Zéro embedding, zéro index, zéro service externe. |
| [Guide CLAUDE.md](docs/guides/claude-md-best-practices.md) | Ce qui va dans votre fichier global, dans votre fichier projet, et ce que le plugin doit porter à la place. |
| [Référence des hooks](docs/reference/hooks.md) | Chaque hook, code de sortie et identifiant de règle, dont le Circuit Breaker et l'Iron Law Pattern. |
| [Dépannage](TROUBLESHOOTING.md) | Quand un skill n'apparaît pas, qu'un hook ne se déclenche pas, ou qu'une règle se déclenche trop. |

## Avec le plugin Superpowers

Craftsman et [Superpowers](https://github.com/anthropics/claude-code-plugins/tree/main/superpowers)
se chargent simultanément sans conflit. Superpowers orchestre l'enchaînement
(brainstorming, planification, TDD, développement par sous-agents) ; Craftsman
impose la qualité à l'intérieur.

<details>
<summary>La boucle combinée, étape par étape</summary>

```
1. /superpowers:brainstorming     → Concevoir la solution en collaboration
2. /superpowers:writing-plans     → Créer le plan d'implémentation
3. /superpowers:subagent-driven-development → Exécuter avec des sous-agents frais
   ├── Les hooks Craftsman se déclenchent sur chaque Write/Edit
   ├── /craftsman:design           → Modélisation DDD quand des entités apparaissent
   └── /craftsman:challenge        → Revue d'architecture aux jalons
4. /craftsman:verify              → Vérification par preuves avant commit
5. /superpowers:finishing-a-development-branch → PR et merge
```

</details>

## Philosophie

> « Des semaines de code peuvent économiser des heures de planification. »

Concevoir avant de coder. Tests d'abord. Débogage systématique plutôt que
correctifs au hasard. YAGNI. Clean Architecture, les dépendances pointent vers
l'intérieur. Faire marcher, faire bien, faire vite, dans cet ordre.

Pragmatisme plutôt que dogmatisme : 80 % de couverture sur les chemins critiques
vaut mieux que 100 % partout ; le DDD pour les domaines complexes, pas pour tous ;
le concret d'abord, l'abstraction quand elle est réellement nécessaire.

## Contribution

Les contributions sont bienvenues. Forkez, branchez, suivez la méthodologie
(`/craftsman:design` d'abord), ajoutez des tests, ouvrez une PR. Détails dans
[CONTRIBUTING.md](CONTRIBUTING.md).

Vous cherchez par où commencer ? Les [good first issues](https://github.com/BULDEE/ai-craftsman-superpowers/labels/good%20first%20issue)
sont du vrai travail, pas des tâches d'occupation : nouveaux packs de langage,
couverture de règles, exemples, traductions.

## Contributeurs

<table>
  <tr>
    <td align="center" width="180">
      <a href="https://github.com/woprrr"><img src="https://github.com/woprrr.png" width="72" alt="" style="border-radius:50%"><br><b>Alexandre Mallet</b></a><br>
      <sub>Auteur et mainteneur</sub><br>
      <sub><a href="https://buldee.com">BULDEE</a></sub>
    </td>
    <td align="center" width="180">
      <a href="https://github.com/Lucr4m"><img src="https://github.com/Lucr4m.png" width="72" alt="" style="border-radius:50%"><br><b>Marc Lucas</b></a><br>
      <sub>Architecture des hooks et résolution de config</sub><br>
      <sub>CEO, <a href="https://www.malucasfire.dev">M.A. LucasFireDev</a></sub>
    </td>
  </tr>
</table>

[**Marc Lucas**](https://github.com/Lucr4m) ([LinkedIn](https://www.linkedin.com/in/marc-lucas-75a012120/)), CEO de [M.A. LucasFireDev](https://www.malucasfire.dev), contribue activement au plugin : la migration des agent hooks vers des command hooks conditionnés, le fallback vers le `~/.claude/.craft-config.yml` global, la résolution des chemins de hooks, et les tests qui les couvrent. M.A. LucasFireDev est une société de conseil PHP/Symfony : audit de code, maintenance et coaching d'équipe.

Votre nom a sa place ici aussi.

## Sponsors

| Sponsor | Description |
|---------|-------------|
| **[BULDEE](https://buldee.com)** | Construire le futur du développement assisté par IA |
| **[M.A. LucasFireDev](https://www.malucasfire.dev)** | Conseil PHP/Symfony, sponsor du plugin en temps d'ingénierie |

Envie de sponsoriser ? [Contactez-nous](https://github.com/BULDEE/ai-craftsman-superpowers/discussions)

## Support

[Discord](https://discord.gg/eBpgHAGu) •
[Issues](https://github.com/BULDEE/ai-craftsman-superpowers/issues) •
[Discussions](https://github.com/BULDEE/ai-craftsman-superpowers/discussions) •
[Changelog](CHANGELOG.md)

Apache License 2.0, voir [LICENSE](LICENSE).

---

<div align="center">

**Si Craftsman a refusé une écriture que vous auriez mergée, mettez une étoile.**
<br>
C'est la seule métrique que ce projet collecte.

<br>

Forgé par [Alexandre Mallet](https://github.com/woprrr) · Sponsorisé par [BULDEE](https://buldee.com) & [M.A. LucasFireDev](https://www.malucasfire.dev)

[ai-craftsman.dev](https://ai-craftsman.dev)

</div>
