<div align="center">

<a href="https://ai-craftsman.dev">
  <img src="https://raw.githubusercontent.com/BULDEE/ai-craftsman-superpowers/main/.github/assets/github-banner.png" alt="AI Craftsman Superpowers - un prompt demande, ceci impose" width="100%">
</a>

[🇬🇧 English](README.md) | 🇫🇷 **Français**

[![Version](https://img.shields.io/github/v/release/BULDEE/ai-craftsman-superpowers?label=version)](CHANGELOG.md)
[![CI](https://img.shields.io/github/actions/workflow/status/BULDEE/ai-craftsman-superpowers/ci.yml?label=CI)](.github/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

[![Claude Code](https://img.shields.io/badge/Claude%20Code-%E2%89%A52.1.218-blueviolet?logo=claude)](#claude-code)
[![Codex](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FBULDEE%2Fai-craftsman-superpowers%2Fmain%2Fhooks%2Fhost-capabilities.json&query=%24.hosts.codex.version&prefix=v&label=Codex%20qualified&logo=openai&color=412991)](docs/guides/codex-quickstart.md)
[![Grok](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2FBULDEE%2Fai-craftsman-superpowers%2Fmain%2Fhooks%2Fhost-capabilities.json&query=%24.hosts.grok.version&prefix=v&label=Grok%20qualified&logo=x&color=000000)](docs/guides/grok-quickstart.md)
[![Hermes](https://img.shields.io/badge/Hermes-native%20plugin-6f42c1)](docs/guides/hermes-quickstart.md)

**Votre agent écrit le code. Vos règles d'architecture décident de ce qui atterrit.**

Pour les équipes qui font tourner des agents de code sur une base où une
violation de couche coûte plus cher que la fonctionnalité elle-même.

[Installation](#installation) •
[Dix premières minutes](#vos-dix-premières-minutes) •
[Commandes](#commandes) •
[Exemples](examples/) •
[Hôtes](#support-des-hôtes) •
[Docs](https://ai-craftsman.dev/docs)

</div>

---

## Un prompt demande. Ceci impose.

Vous pouvez écrire « toujours des classes final » dans votre `CLAUDE.md` ou
votre `AGENTS.md`. Le modèle va s'y tenir, jusqu'à ce que le contexte se
remplisse, que la tâche s'allonge, ou qu'arrive le dixième fichier d'un
refactor. Les instructions se dégradent. Ce n'est pas un problème de
discipline, c'est un problème d'architecture : rien dans la boucle ne vérifie.

Craftsman met la vérification dans la boucle. Les mêmes règles tournent en
hooks sur chaque écriture, en garde-fou dans votre CI, et comme critères lus
par un agent relecteur. Les violations de couche et l'absence de
`strict_types` sont refusées avant que l'écriture atterrisse, le reste est
rendu directement au modèle comme un constat auquel il doit répondre, et la
même règle fait échouer votre pipeline si elle atteint une pull request.

## Voyez-le refuser

Le modèle tente d'écrire une entité qui importe depuis la couche
infrastructure. Le fichier n'atteint jamais votre disque :

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

Ce n'est pas une maquette : l'enregistrement fait passer deux fichiers d'essai
dans `hooks/pre-write-check.sh` et montre ce qui en sort. Le code de sortie 2
est le refus.

</details>

Le modèle lit les deux mêmes lignes que vous, corrige l'import et réécrit. La
correction est enregistrée ; si cette règle revient sur plusieurs fichiers,
elle vous est proposée comme instinct candidat dans `/craftsman:metrics`. Et si
la violation atteint une pull request à la place, la règle identique fait
échouer le pipeline : un seul moteur, un seul verdict, zéro dérive entre votre
éditeur et votre CI.

## Installation

> [!WARNING]
> N'installez ce plugin que depuis les sources officielles ci-dessous. Ne faites
> pas confiance aux forks, miroirs ou copies « améliorées » distribués ailleurs.
> Étapes de vérification : [SECURITY.md](SECURITY.md#pre-installation-verification).

Choisissez votre hôte. Chaque bloc est complet : après lui, le garde-fou
refuse les mauvaises écritures.

### Claude Code

```bash
/plugin marketplace add BULDEE/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
# redémarrez Claude Code, puis :
/craftsman:setup --quick
```

### Codex

```bash
codex plugin marketplace add BULDEE/ai-craftsman-superpowers
codex plugin add craftsman@ai-craftsman-superpowers
codex    # puis /hooks : relisez et approuvez les handlers craftsman
```

Installer n'approuve pas les hooks : tant que vous ne les avez pas relus dans
`/hooks`, ils sont chargés et ne tournent pas. Détail et limites :
[guide Codex](docs/guides/codex-quickstart.md).

### Grok

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/src/ai-craftsman-superpowers
bash ~/src/ai-craftsman-superpowers/bin/craftsman-grok-install
```

Grok n'exécute aucun des hooks embarqués d'un plugin dans un processus frais :
l'installeur écrit donc aussi le garde-fou global `~/.grok/hooks/craftsman.json`
(la même écriture que `craftsman-ci export --target grok-hooks --into ~/.grok/hooks`).
Relancez-le pour mettre à jour. Détail et limites :
[guide Grok](docs/guides/grok-quickstart.md).

### Hermes

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers ~/.hermes/plugins/craftsman
hermes plugins enable craftsman
```

Le garde-fou s'applique à la conclusion : l'agent ne peut pas conclure un tour
de code qui laisse des violations critiques. Détail :
[guide Hermes](docs/guides/hermes-quickstart.md).

### Vérifier que ça marche

Lancez `/craftsman:healthcheck` (sur Grok : `/healthcheck`), ou depuis un
shell `bash <racine du plugin>/bin/craftsman-healthcheck --report`. Chaque
ligne qui n'est pas `ok` nomme la commande qui la corrige.

<details>
<summary>Prérequis et installation locale</summary>

<br>

**Prérequis**

- Claude Code v2.1.218 ou plus (`claude --version`). Versions antérieures : installez la ligne 3.9.x gelée.
- `python3` 3.9 ou plus. C'est le plancher parce que c'est ce qu'est `/usr/bin/python3` sur un Mac sans homebrew ; la CI importe chaque bibliothèque de hook sous 3.9 pour que le plancher ne remonte pas en silence.
- `bash`, `grep`, `jq`, `sqlite3`. GNU coreutils n'est pas requis : le plugin tourne sur un macOS d'origine.

**Installer depuis un clone local (Claude Code)**

```bash
git clone https://github.com/BULDEE/ai-craftsman-superpowers.git /path/to/ai-craftsman-superpowers
/plugin marketplace add /path/to/ai-craftsman-superpowers
/plugin install craftsman@ai-craftsman-superpowers
```

`/plugin` affiche alors craftsman dans l'onglet « Installed » ; l'onglet
« Errors » dit pourquoi un skill n'apparaît pas.

</details>

## Vos dix premières minutes

**1. Configurer** (lit votre dépôt, ne pose aucune question) :

```text
/craftsman:setup --quick
```

**2. Le voir refuser.** Demandez exprès quelque chose que les règles
interdisent :

```text
Create src/Domain/Order/Order.php, a class that uses App\Infrastructure\Doctrine\OrderRepository.
```

L'écriture est refusée avant le disque, `LAYER001` parmi les raisons, et le
modèle réécrit la classe derrière une interface de repository dans le domaine.
Cet aller-retour, c'est le produit.

**3. Construire une fonctionnalité avec le cycle complet** (design, spec,
plan, implémentation, tests, vérification, commit) :

```text
/craftsman:workflow
I need to add a forgot password feature.
```

**4. Prouver avant de dire que c'est fini :**

```text
/craftsman:verify
```

Vous ne voulez qu'une étape du cycle ? `/craftsman:design` (modélisation DDD),
`/craftsman:debug` (investigation systématique), `/craftsman:challenge` (revue
d'architecture). Nouveau dans la méthodologie ? Le
[guide débutant](docs/guides/beginner.md) parcourt le DDD avec des exemples
commentés.

## Support des hôtes

Quatre hôtes, un seul moteur. Ce que chaque hôte charge et observe est mesuré
sur la vraie CLI et consigné dans
[`hooks/host-capabilities.json`](hooks/host-capabilities.json) (provenance :
[`tests/fixtures/hosts/PROVENANCE.md`](tests/fixtures/hosts/PROVENANCE.md)).

| | Claude Code | Codex | Grok | Hermes |
|---|---|---|---|---|
| Installation | `/plugin install` | `codex plugin add` | `craftsman-grok-install` | `hermes plugins enable` |
| Étape en plus | aucune | approuver les hooks dans `/hooks` | aucune (garde-fou global) | aucune |
| Garde-fou avant le disque | `Write`, `Edit` | `apply_patch` | `write`, `search_replace` | optionnel `write_gate: on`, SEC001 et LAYER001 |
| Preuve exigée avant de clore une tâche | oui (`TaskCompleted`) | non, événement non émis | non, événement non émis | oui (`pre_verify`) |
| Décision `ask` | oui | non, refuse à la place | oui | sans objet |
| Preuve de test (accordée et révoquée) | oui | non, pas de code de sortie dans l'événement shell | oui | sans objet |
| Skills | 22 | 22 | 22 (`/name`) | 7 plus `/craftsman` |

Sur tous les hôtes, le garde-fou juge les outils d'écriture de l'hôte. Un
fichier écrit par une commande shell que lance le modèle (`printf > file`,
`sed -i`, un script) n'est pas contrôlé avant le disque : la CI
(`ci/craftsman-ci.sh`) et le garde-fou pre-push le rattrapent. GitHub Copilot
a un adaptateur pour son contrat de hooks documenté ; aucune surface Copilot
n'est encore qualifiée, donc pas de badge.

## Commandes

Quinze commandes ne démarrent que si vous les tapez ; sept (`challenge`,
`debug`, `test`, `team`, `rag`, `mlops`, `agent-design`) peuvent être lancées
par le modèle quand le contexte s'y prête. Chaque commande a un exemple
commenté avec sa sortie attendue : [COMMANDS-QUICK-REF.md](COMMANDS-QUICK-REF.md).

| Catégorie | Commandes |
|-----------|-----------|
| Méthodologie | `design`, `debug`, `plan`, `challenge`, `verify`, `workflow`, `spec`, `refactor`, `legacy`, `test`, `git`, `parallel`, `loop` |
| Scaffolding | `scaffold entity/usecase/component/hook/api-resource/pack` |
| Ingénierie IA/ML | `rag`, `mlops`, `agent-design` |
| Utilitaires | `setup`, `healthcheck`, `metrics`, `team` |
| CI/CD | `ci` |

Agents derrière ces commandes : `team-lead`, `architect` (sans Write/Edit),
`doc-writer`, `security-pentester`, `legacy-surgeon`, `ui-ux-director`, plus
des relecteurs propres aux packs Symfony, React et IA/ML. Les 12 missions
d'agents sont livrées comme des fichiers ordinaires. Liste complète :
[référence des agents](docs/reference/agents.md).

## Face à ce que vous avez déjà

Votre vraie alternative n'est pas un autre plugin. C'est le `CLAUDE.md` ou
l'`AGENTS.md` que vous avez déjà écrit, et les linters que vous faites déjà
tourner.

| | Fichier d'instructions seul | Linter et CI | Craftsman |
|---|---|---|---|
| Tient encore au fichier 300 d'un refactor | non | oui | oui |
| Le modèle voit la violation *avant* d'écrire | non | non | oui |
| Même verdict sur votre machine et dans le pipeline | n/a | partiel | oui |
| Empêche le modèle de refaire la même erreur | non | non | oui |
| Avertit quand un modèle de domaine est écrit sans passe de design | non | non | oui |

## Ce qu'il fait vraiment

**Il bloque.** Un seul moteur de règles, appliqué à l'identique en hooks et en
CI. Aucune dérive entre ce que votre éditeur autorise et ce que votre pipeline
refuse. GitHub, GitLab, Bitbucket et Jenkins reçoivent tous des annotations
natives.

**Il apprend.** Chaque violation corrigée est enregistrée localement. Une
correction qui revient 3 fois sur 3 fichiers devient un instinct candidat que
vous validez dans `/craftsman:metrics`, puis un skill projet avec provenance.
La détection est automatique, la codification reste sous contrôle humain.

**Il prouve.** « Terminé » exige des preuves. Une tâche ne peut pas être
marquée complète sans trace de vérification, et un test qui échoue révoque une
trace existante.

Et sur Claude Code, chaque travail tourne sur le modèle le moins cher qui en
est capable : formater un commit sur Haiku en effort faible, une revue
d'architecture sur Opus en effort élevé.

<details>
<summary><b>Sept autres mécanismes</b> : le moteur de règles, le cliquet structurel, le panel de design adverse, la détection de biais, et trois autres</summary>

<br>

1. **Moteur de règles à 3 niveaux d'héritage** : Global, Projet, Répertoire. Forme courte (`PHP001: warn`) ou forme longue (règles regex personnalisées). Le code hérité coexiste avec du code strict via une relaxation au niveau répertoire.
2. **Cliquet structurel** : une baseline committée enregistre le plus haut niveau structurel de chaque fichier (complexité, taille, plus longue fonction, fan-out d'imports, nombre de suppressions). Un fichier que vous touchez peut s'améliorer ou rester égal, jamais régresser : la marque se resserre automatiquement sur un passage vert et ne se desserre que par une suppression documentée et comptée. Le code hérité non touché n'est jamais puni pour une dette qu'il avait déjà.
3. **Panel de design adverse** : trois contradicteurs (YAGNI, invariants et frontières, faisabilité) attaquent un design pendant `/craftsman:design`, avant qu'une ligne de code existe. Chaque objection atterrit dans un tableau retenue ou écartée : le silence n'est pas une option.
4. **Détecteur de biais cognitifs** : détection en temps réel du biais d'accélération, du scope creep et de la sur-optimisation dans vos prompts. Les patterns curés en anglais vous avertissent directement ; toutes les autres langues confient la décision au modèle qui lit déjà votre prompt, lequel la remonte ou l'écarte en silence avec toute la session en contexte. Aucun second modèle, aucun appel réseau. Les tags de langue suivent BCP 47. Les lexiques non anglais sont des ébauches orientées rappel qu'aucun locuteur natif n'a encore relues.
5. **Contrôle qualité en temps réel** : validation progressive sur chaque écriture faite par un outil d'écriture de l'hôte : regex (toujours active, coût mesuré par `tests/perf/test-hook-latency.sh`), puis sémantique LSP (via le plugin LSP officiel de votre langage), puis analyse statique et architecture (PHPStan, ESLint, deptrac : à activer machine par machine parce que lancer les analyseurs d'un projet exécute son code, voir [SECURITY.md](SECURITY.md)). Se dégrade proprement sans aucun outil installé.
6. **Métriques et tendances** : suivi SQLite des violations, corrections et sessions, avec des vues 7 jours et 30 jours pour identifier vos règles les plus violées.
7. **Règles de sécurité** : SEC001-003 (secrets en dur, eval dynamique, SQL par concaténation) vérifiées en hooks et en CI, avec leur doctrine routée vers le modèle au blocage.

</details>

## Moteur de règles

Surchargez n'importe quelle règle par projet ou par répertoire, avec un
héritage de configuration à 3 niveaux :

```
~/.claude/.craft-config.yml          ← Valeurs globales par défaut
  └─ {project}/.craft-config.yml     ← Surcharges projet
      └─ {dir}/.craft-rules.yml      ← Surcharges répertoire
```

Forme courte : `PHP001: warn` / `TS001: ignore`. Forme longue : règles
personnalisées avec regex, sévérité, langages. Supprimez une occurrence
isolée avec `// craftsman-ignore: RULE_ID`, sauf les règles de sécurité
(`SEC*`), qu'aucun marqueur ne fait taire, sur aucun front.

## Intégration CI/CD

La CI charge les mêmes validateurs de packs et le même moteur de règles que
les hooks : une règle ne peut pas vouloir dire une chose sur votre machine et
une autre dans le pipeline. Exportez un pipeline avec `/craftsman:ci export`
([exemple](examples/ci/01-export-github-gate.md)).

| Fournisseur | Modèle | Adaptateur |
|-------------|--------|------------|
| GitHub Actions | `craftsman-quality-gate.yml` | Natif : annotations en ligne et commentaire de PR |
| GitLab CI | `.gitlab-ci.craftsman.yml` | Natif : rapport code-quality et note de MR |
| Bitbucket Pipelines | `bitbucket-pipelines.craftsman.yml` | Natif : rapport de build |
| Jenkins | `Jenkinsfile.craftsman` | Natif : rapport Checkstyle lu par Warnings Next Generation |

## Coût et confidentialité

Tout ce qui précède fonctionne **sans coût d'API** au-delà de votre usage
normal du modèle : validation regex, moteur de règles, détection de biais,
export CI et métriques sont locaux. Une couche optionnelle ajoute une analyse
sémantique par une revue headless (Haiku sur Claude Code), pour environ
0,15 à 0,30 $ par session de 50 écritures. Désactivez-la avec
`agent_hooks: false` et tout le reste continue de fonctionner.

**Aucune télémétrie, aucune analytique, aucun appel sortant.** Les métriques
ne quittent jamais votre machine, et chaque hôte et chaque session gardent
leur propre stockage. Le contenu des fichiers édités n'atteint une API de
modèle que si `agent_hooks: true`.

Un dépôt cloné est une entrée non fiable : les deux capacités qui
exécuteraient du code fourni par le dépôt (`trust_project_tools` et les
chemins de packs externes) restent coupées tant que **vous** ne les activez
pas dans votre propre configuration globale, et un fichier projet ne peut
jamais les accorder. `tests/core/test-hostile-repo.sh` reproduit chaque
attaque que ce modèle couvre et vérifie qu'elle échoue. Détail complet :
[SECURITY.md](SECURITY.md).

## Limites connues

**Par conception :** les violations de règles de code bloquent, la détection
de biais se contente d'avertir ; pas d'auto-commit ; la méthodologie est
assumée (DDD/Clean Architecture).

**Contraintes actuelles :** PHP, TypeScript, Python, Go, Rust et Bash ont une
couverture de règles complète, les autres langages un support de base ; les
métriques sont par machine, pas partagées dans une équipe ; les fichiers écrits
par le shell sont rattrapés par la CI et le garde-fou pre-push, pas avant le
disque ; les écarts propres à chaque hôte sont listés dans
[Support des hôtes](#support-des-hôtes).

Plus de détails dans la [FAQ](FAQ.md) et [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Pour aller plus loin

| | |
|---|---|
| [Commandes et exemples](COMMANDS-QUICK-REF.md) | Chaque commande, qui la lance, et un exemple commenté avec sa sortie attendue. |
| Guides [Codex](docs/guides/codex-quickstart.md), [Grok](docs/guides/grok-quickstart.md), [Hermes](docs/guides/hermes-quickstart.md) | Installation, vérification, limites et désinstallation par hôte. |
| [Décisions d'architecture](docs/adr/) | Chaque choix de conception majeur. Commencez par [ADR-0016](docs/adr/0016-v4-clean-break-native-first.md) et [ADR-0029](docs/adr/0029-host-adapter-contract.md) (adaptateurs d'hôtes, un seul cœur). |
| [Bundle de connaissances](knowledge/) | La méthodologie est livrée comme bundle [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) : du Markdown versionné dans git. Zéro embedding, zéro index, zéro service externe. |
| [Pour les non-développeurs](docs/guides/for-non-developers.md) | Ce que fait ce plugin, en langage clair, et les trois questions à poser à votre équipe. |
| [Bonnes pratiques CLAUDE.md](docs/guides/claude-md-best-practices.md) | Ce qui a sa place dans votre fichier global, dans votre fichier projet, et ce que le plugin doit porter à la place. |
| [Référence des hooks](docs/reference/hooks.md) | Chaque hook, code de sortie et identifiant de règle. |
| [Migration](MIGRATION.md) | Changements cassants entre versions majeures. |

## Avec le plugin Superpowers

Craftsman et [Superpowers](https://github.com/obra/superpowers) se chargent
ensemble sans conflit. Superpowers orchestre le workflow (brainstorming,
planification, TDD, développement piloté par sous-agents) ; Craftsman impose
la qualité à l'intérieur.

<details>
<summary>La boucle combinée, étape par étape</summary>

```
1. /superpowers:brainstorming     → Concevoir la solution en collaboration
2. /superpowers:writing-plans     → Créer le plan d'implémentation
3. /superpowers:subagent-driven-development → Exécuter avec des sous-agents neufs
   ├── Les hooks Craftsman se déclenchent sur chaque écriture (contrôle qualité en temps réel)
   ├── /craftsman:design           → Modélisation DDD quand des entités de domaine apparaissent
   └── /craftsman:challenge        → Revue d'architecture aux jalons
4. /craftsman:verify              → Vérification fondée sur des preuves avant le commit
5. /superpowers:finishing-a-development-branch → PR et merge
```

</details>

## Philosophie

> « Des semaines de code peuvent économiser des heures de planification. »

Concevoir avant de coder. Tests d'abord. Débogage systématique plutôt que
correctifs au hasard. YAGNI. Clean Architecture, les dépendances pointent vers
l'intérieur. Faire marcher, faire bien, faire vite, dans cet ordre.

Pragmatisme plutôt que dogmatisme : 80 % de couverture sur les chemins
critiques vaut mieux que 100 % partout ; le DDD pour les domaines complexes,
pas pour tous ; le concret d'abord, l'abstraction quand elle est réellement
nécessaire.

## Contribution

Les contributions sont bienvenues. Forkez, branchez, suivez la méthodologie
(`/craftsman:design` d'abord), ajoutez des tests, ouvrez une PR. Détails dans
[CONTRIBUTING.md](CONTRIBUTING.md). `bash tests/run-tests.sh` lance toute la
suite, dont `tests/core/test-command-docs.sh`, qui échoue quand une commande
perd son exemple.

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
