# Sources et emploi du méta-prompt d'implémentation

Préparé le 15 septembre 2026 pour [le prompt à coller dans Claude Code](meta-prompt-implementation-claude-code.md). Ce prompt pilote une campagne ; il n'installe ni ne lance les adaptateurs. Il ne dépend pas d'un nom de modèle particulier.

Les recommandations retenues sont une mission précise, des sources ciblées, des critères observables, une séparation explicite des instructions et du contexte, des délégations bornées et une reprise persistante. Elles sont adaptées au projet, sans promesse de gain chiffré ni de formulation universellement optimale. Aucun benchmark comparatif de ce prompt n'a été exécuté.

| Source officielle consultée | Application au prompt |
|---|---|
| [Anthropic : prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) | Instructions directes, balises cohérentes, contexte ciblé, tâche d'action explicite |
| [Anthropic : best practices Claude Code](https://code.claude.com/docs/en/best-practices) | Vérification exécutable, exploration ciblée avant modification, revue indépendante et maîtrise du contexte |
| [OpenAI : mode non interactif](https://learn.chatgpt.com/docs/non-interactive-mode) | codex exec, résultat final, mode éphémère, distinction JSONL/schéma et permissions |
| [xAI : headless et scripting](https://docs.x.ai/build/cli/headless-scripting) | grok -p et formats de sortie ; découverte locale avant de figer les flags |
| [xAI : présentation Grok Build](https://docs.x.ai/build/overview) | Distinguer l'application Grok Build et l'API de modèle |
| [xAI : sandbox](https://docs.x.ai/build/features/sandbox) | Profil read-only documenté et limites de protection, à vérifier dans le consommateur |

Vérifications locales sans appel modèle : `codex --version` donne `0.154.0` ; `grok --version` donne `1.0.30 (04b7ffed98c6) [stable]`. `codex exec --help`, `grok --help` et `grok agent --help` ont été consultés. L'aide Grok confirme `--prompt-file`, `--json-schema`, `--max-turns`, `--no-subagents` et `--sandbox`. La page sandbox documente le profil `read-only` ; le prompt exige sa vérification au moment de l'usage. Aucun test d'authentification, de sandbox ou d'exécution modèle n'est revendiqué.

Le contexte projet vient de l'[audit](audit-codex-claude-2026-09-15.md), de la [recherche d'interopérabilité](recherche-interoperabilite-2026-09-15.md), de l'[ADR-0029](../adr/0029-host-adapter-contract.md) et du backlog Craftsman relu localement. Les conventions de preuve RED/GREEN, de préservation du checkout et de non-publication implicite sont des exigences de la campagne, pas des capacités ajoutées par le prompt.

Pour démarrer une nouvelle conversation Claude Code dans ce dépôt, on peut simplement demander :

```text
Lis et exécute docs/reference/meta-prompt-implementation-claude-code.md.
Il constitue ma demande de réalisation pour cette campagne. Reprends l'état actuel
du backlog et commence l'implémentation du premier CR encore ouvert.
```

Le document reste une proposition de prompt tant qu'Alexandre ne l'a pas soumis à la session d'implémentation. Son invocation autorise les travaux décrits dans les limites des permissions et instructions applicables ; elle ne supprime aucune protection de la plateforme.
