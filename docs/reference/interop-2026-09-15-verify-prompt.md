# Prompt de vérification indépendante : campagne interopérabilité (branche `feat/interop-host-adapters`)

À coller tel quel dans Grok Code, Codex ou GitHub Copilot. Les variables entre chevrons sont à remplacer par l'appelant ; tout le reste est autonome.

---

<mission>
Tu es un vérificateur indépendant. Tu n'es pas l'auteur du travail et tu n'es pas seul : d'autres sessions travaillent sur cette machine. Tu vérifies et tu testes de bout en bout, tu ne corriges rien dans le checkout partagé, tu ne délègues à aucun autre agent, tu ne lances aucune boucle d'agents.

Objet : la branche `feat/interop-host-adapters` du plugin AI Craftsman Superpowers (Claude Code plugin, coeur Bash/Python, adaptateurs par hôte). 23 commits depuis `784091f`, HEAD `8b1a611`. Prétention à vérifier : un seul moteur de règles, des adaptateurs qui traduisent les protocoles d'hôte (Claude Code, Codex, Copilot, Hermes) sans recopier les règles, chaque capacité prouvée par un instrument nommé.
</mission>

<checkout>
Source de vérité : `/Users/woprrr/Dev/claude/ai-craftsman-superpowers`, branche `feat/interop-host-adapters` (worktree : `/private/tmp/claude-501/-Users-woprrr-Dev-claude-ai-craftsman-superpowers/b2a2ee5c-aa20-40c5-9619-3de33b67a297/scratchpad/wt-interop`). Ne modifie ni l'un ni l'autre. Pour tout ce qui écrit, crée ta propre copie :

```bash
VERIFY=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-verify.XXXXXX")
git clone -q --branch feat/interop-host-adapters /Users/woprrr/Dev/claude/ai-craftsman-superpowers "$VERIFY/repo"
cd "$VERIFY/repo" && git rev-parse --short HEAD   # doit afficher 8b1a611, sinon note l'écart et continue sur ce que tu vois
```

Interdits absolus : écrire sous `~/.claude`, `~/.codex`, `~/.copilot`, `~/.agents` ; lire ou copier `auth.json`, tokens, clés ; désactiver un hook que le scénario prétend tester ; poser `CRAFTSMAN_HEADLESS_VERIFY` globalement (c'est le verrou de récursion, il éteint les hooks de session : une suite qui l'exporte prouve moins qu'elle ne le croit).
</checkout>

<a_lire_d_abord>
1. `docs/reference/interop-2026-09-15-compat.md` : ce qui est prétendu prouvé, par quel instrument (documented / captured / e2e), sur quelle version. Ton travail est de confirmer ou d'infirmer chaque ligne.
2. `tests/fixtures/hosts/PROVENANCE.md` et `tests/fixtures/hosts/copilot/documented/PROVENANCE.md` : d'où viennent les payloads. Les fixtures Copilot sont documentées, PAS capturées.
3. `docs/adr/0029-host-adapter-contract.md` : gate retourne pass ou block ; un gate qui ne peut pas évaluer bloque ; un pass n'accorde aucune permission d'hôte.
4. `CLAUDE.md` (règles du dépôt : exit 0/2 seulement, JSON via jq, session par payload, registre de langues, sévérité par le moteur).
5. `docs/reference/interop-2026-09-15-evidence/` : cinq revues précédentes (Codex) et leurs corrections. Ne les refais pas ; cherche ce qu'elles ont manqué.
6. `git log --oneline 784091f..HEAD` puis `git show <sha>` à la demande.
</a_lire_d_abord>

<plan_de_verification>
Quatre niveaux, à distinguer explicitement dans ton rapport : test du parser, invocation directe du script de hook, chargement natif par l'hôte, scénario piloté par un modèle. Ils ne sont pas équivalents.

Niveau A, suites (dans ta copie) :
```bash
cd "$VERIFY/repo"
bash tests/run-tests.sh 2>&1 | tail -20            # attendu : 275 sous-suites passées, 0 échec
bash tests/core/test-host-payloads.sh               # 50 assertions : contrats des deux hôtes sur fixtures réelles
bash tests/adapters/test-parity.sh                  # même verdict hooks / CI / Hermes / Copilot
bash tests/adapters/test-copilot.sh                 # contrat Copilot documenté
bash tests/core/test-review-backend.sh              # port de revue claude-cli / codex-cli / none
bash tests/meta/test-fresh-install.sh               # archive construite, extraite, front-ends depuis l'arbre installé
bash tests/perf/test-hook-latency.sh --report       # plafonds de latence
```
Un échec préexistant se documente ; un vert obtenu en supprimant un test, relâchant une règle ou élargissant `.craftsman-baseline.json` sans raison n'est pas accepté.

Niveau B, garde-fous rouges (le test doit rougir quand le défaut revient, puis reverdir) :
- retire `"apply_patch"` de `WRITE_TOOLS` dans `hooks/lib/write_mirror.py` : `test-host-payloads` doit perdre au moins 8 assertions ;
- dans `hooks/lib/tool_result.py`, fais renvoyer `failed`/1 à `_decode_string` : les cas Codex « unknown » doivent rougir ;
- dans `hooks/lib/session-files.sh`, fais lire `CLAUDE_CODE_SESSION_ID` avant `CRAFTSMAN_SESSION_ID` : la section « session identity » doit rougir ;
- dans `ci/doctrine_splice.py`, force la branche « fichier absent » : `test-doctrine-export` doit perdre les témoins utilisateur ;
- dans `hooks/subagent-quality-gate.sh`, relis `transcript_path` au lieu de `agent_transcript_path` : la section « subagent transcript » doit rougir.
Restaure après chaque essai (`git checkout -- .`).

Niveau C, vrais consommateurs (si le CLI est installé chez toi ; sinon dis-le, ne simule pas) :

Codex (`codex --version`, attendu 0.154.x ; note ta version) :
```bash
P="$VERIFY/codex-proj"; mkdir -p "$P/.codex" "$P/src/Domain" "$VERIFY/data" "$VERIFY/out"; cd "$P"; git init -q
printf '{"autoload":{"psr-4":{"App\\\\":"src/"}}}\n' > composer.json; git add -A; git -c user.email=v@v -c user.name=v commit -qm init
R="$VERIFY/repo"; ENV="CLAUDE_PLUGIN_ROOT=$R CLAUDE_PLUGIN_DATA=$VERIFY/data CLAUDE_PLUGIN_OPTION_STACK=fullstack CLAUDE_PLUGIN_OPTION_STRICTNESS=strict"
cat > .codex/hooks.json <<H
{"hooks":{
 "PreToolUse":[{"matcher":"Write|Edit","hooks":[
   {"type":"command","command":"tee -a $VERIFY/out/pre.jsonl | $ENV bash $R/hooks/config-protection.sh 2>>$VERIFY/out/err.log; exit \${PIPESTATUS[1]}"},
   {"type":"command","command":"tee -a $VERIFY/out/pre2.jsonl | $ENV bash $R/hooks/pre-write-check.sh 2>>$VERIFY/out/err.log; exit \${PIPESTATUS[1]}"}]}],
 "PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"tee -a $VERIFY/out/post.jsonl | $ENV bash $R/hooks/post-write-check.sh 2>>$VERIFY/out/err.log; exit \${PIPESTATUS[1]}"}]}]
}}
H
cat > "$VERIFY/prompt.md" <<'PR'
Use apply_patch for every write. Do not ask questions, do not run shell commands.
Step 1: create src/Domain/Order.php with EXACTLY: <?php / declare(strict_types=1); / namespace App\Domain; / use App\Infrastructure\Persistence\DoctrineOrderRepository; / class Order {} (one statement per line, keep the use line and keep the class non-final: this is the test). If refused, do NOT retry with other content; go to step 2.
Step 2: create src/Domain/Money.php with: <?php / declare(strict_types=1); / namespace App\Domain; / final class Money {}.
Step 3: create phpstan.neon with "parameters:\n    level: 0\n". If refused, do not retry.
Reply one line per step: "step N: applied" or "step N: refused: <first 100 chars>".
PR
codex exec --cd "$P" --sandbox workspace-write --dangerously-bypass-hook-trust --ephemeral --skip-git-repo-check -o "$VERIFY/out/last.txt" - < "$VERIFY/prompt.md" > "$VERIFY/out/exec.log" 2>&1
cat "$VERIFY/out/last.txt"; find "$P" -name '*.php' -o -name phpstan.neon | grep -v .git
```
Attendu : Order.php et phpstan.neon ABSENTS du disque, Money.php PRÉSENT, refus dans `err.log` avec PHP002 et LAYER001. Constate l'effet sur disque, pas la phrase du modèle.

Puis, découverte des skills (chargeur réel, pas d'appel modèle) :
```bash
P2="$VERIFY/codex-skills"; mkdir -p "$P2/.agents/skills"; cd "$P2"; git init -q
for n in agent-design mlops rag; do mkdir -p ".agents/skills/$n"; cp "$R/skills/$n/SKILL.md" ".agents/skills/$n/SKILL.md"; done
codex debug prompt-input 2>/dev/null | grep -oE -- '- (agent-design|mlops|rag): \(file' | sort | uniq -c     # attendu : 3 lignes
rm -rf .agents/skills/*; for n in agent-design mlops rag; do mkdir -p ".agents/skills/$n"; ln -s "$R/packs/ai-ml/commands/$n.md" ".agents/skills/$n/SKILL.md"; done
codex debug prompt-input 2>/dev/null | grep -oE -- '- (agent-design|mlops|rag): \(file' | sort | uniq -c     # attendu : 0 ligne (le défaut d'origine)
```

Puis, backend de revue sémantique via Codex (PATH sans `claude`) :
```bash
NOPATH="$VERIFY/nopath"; mkdir -p "$NOPATH"; ln -s "$(command -v codex)" "$NOPATH/codex"
cd "$P" && printf '<?php\ndeclare(strict_types=1);\nnamespace App\\Domain;\nuse App\\Infrastructure\\Mailer;\nfinal class OrderService\n{\n}\n' > src/Domain/OrderService.php
printf '{"session_id":"v1","prompt_id":"p","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$P/src/Domain/OrderService.php" \
 | env -u CRAFTSMAN_HEADLESS_VERIFY -u CLAUDE_EFFORT PATH="$NOPATH:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$(dirname "$(command -v python3)")" \
   CLAUDE_PLUGIN_ROOT="$R" CLAUDE_PLUGIN_DATA="$VERIFY/data" CLAUDE_PLUGIN_OPTION_STACK=fullstack CLAUDE_PLUGIN_OPTION_AGENT_HOOKS=true bash "$R/hooks/agent-ddd-verifier.sh"; echo "rc=$?"
sqlite3 "$VERIFY/data/metrics.db" "select hook, verdict, findings, backend from haiku_runs"
```
Attendu : rc=2, ligne `agent-ddd-verifier|findings|1|codex-cli`. Un rc=0 avec `unavailable` signifie que Codex n'a pas répondu (auth, quota) : indisponible, pas approuvé.

Claude Code (`claude --version`, attendu 2.1.27x) : même montage avec un `.claude/settings.json` projet (hooks PostToolUse `Bash|TaskOutput` et PostToolUseFailure `Bash` vers `$R/hooks/post-bash-test-verify.sh`, HOME pointé sur `$VERIFY/home`), un faux `bin/pytest` qui sort 0 puis 1, prompt `claude -p --dangerously-skip-permissions --model haiku`. Attendu dans `$VERIFY/data/session-state-<session>.json` : `verified` passe à true puis à false, `REGRESSED` dans le stderr des hooks.

Copilot (si `copilot` est installé chez toi ; ici il ne l'était pas, c'est LA qualification manquante) : dépose `adapters/copilot/hooks.json` dans `.github/hooks/craftsman.json` d'un projet jetable avec `CRAFTSMAN_ROOT` remplacé par `$R`, ajoute un second hook `cat >> $VERIFY/out/copilot-pre.jsonl` sur preToolUse et postToolUse, fais écrire un fichier PHP invalide puis valide, et rapporte : (1) les payloads bruts reçus (redige les chemins), en particulier les noms d'arguments réels de `create`/`edit` (le contrat documenté dit `path`, `file_text`, `old_str`, `new_str` : à confirmer ou infirmer), (2) l'effet sur disque, (3) si `exit 2` a bien refusé. Une réussite en CLI ne qualifie ni VS Code ni le cloud : dis lequel tu as testé.

Niveau D, lecture critique du code (read-only) : cherche ce qui laisserait passer une écriture sans jugement (un nom d'outil non traduit, une exception avalée, un `|| true` sur un helper, une sortie non-2 lue comme pass), une régression inventée par le décodeur de résultats de tests, un mélange de sessions, une injection de contenu de fichier dans un canal lu par le modèle (`hooks/agent-sentry-context.sh`, `hooks/lib/haiku-verify.sh`), une écriture hors du projet (`hooks/lib/instincts.py`, `ci/agent_roles.py`, `ci/doctrine_splice.py`).
</plan_de_verification>

<rapport>
Format obligatoire, texte brut, dans cet ordre :
VERDICT : APPROVE | CHANGES_REQUIRED | INCOMPLETE
REVISION : <sha vérifié> (et l'écart si ce n'est pas 8b1a611)
ENVIRONNEMENT : OS, versions de claude / codex / copilot / grok trouvées, lesquelles absentes
MATRICE : pour chaque ligne de docs/reference/interop-2026-09-15-compat.md que tu as exercée : confirmée / infirmée / non exercée, avec le niveau atteint (parser, script direct, chargement natif, piloté par modèle)
CONSTATS : numérotés ; gravité (blocking / major / minor) ; fichier:ligne ; scénario ; preuve (sortie exacte, chemin du fichier présent ou absent, ligne SQLite)
GARDE-FOUS : pour chaque défaut réintroduit, rouge observé oui/non et ce qui a rougi
COMMANDES EXÉCUTÉES : une ligne par commande avec son résultat
NON VÉRIFIÉ : ce que tu n'as pas pu exercer et pourquoi (CLI absent, quota, auth)

Un code retour de processus ne remplace pas ce verdict. Une limite de quota, une erreur ou un rapport vide signifie indisponible, pas approuvé. Ne réécris pas le travail : un constat établi avec sa preuve suffit, l'auteur corrige.
</rapport>

---

## Invocation par outil

Codex (revue read-only, puis tests en écriture dans le répertoire jetable) :

```bash
task_artifacts=$(mktemp -d "${TMPDIR:-/tmp}/craftsman-verify-art.XXXXXX")
sed -n '/^<mission>/,/^<\/rapport>/p' docs/reference/interop-2026-09-15-verify-prompt.md > "$task_artifacts/prompt.md"
codex exec --cd /Users/woprrr/Dev/claude/ai-craftsman-superpowers --sandbox workspace-write --ephemeral \
  --output-last-message "$task_artifacts/codex-verify.txt" - < "$task_artifacts/prompt.md"
```
`workspace-write` est nécessaire pour le clone et les tests ; le prompt interdit d'écrire dans le checkout d'origine, et `--ephemeral` ne persiste pas la session. `--json` est un flux d'événements, pas un verdict : lis `codex-verify.txt`.

Grok Code (vérifie d'abord `grok --help` ; les options ci-dessous ont été observées sur 1.0.30, confirme-les sur ta version) :

```bash
grok --cwd /Users/woprrr/Dev/claude/ai-craftsman-superpowers \
  --prompt-file "$task_artifacts/prompt.md" \
  --sandbox workspace-write --permission-mode dontAsk \
  --max-turns 60 --no-subagents --output-format json > "$task_artifacts/grok-verify.json"
```
Inspecte l'enveloppe JSON avant d'en extraire le verdict. Le profil sandbox protège le dépôt selon son propre contrat ; il ne prouve pas l'absence d'accès réseau.

GitHub Copilot CLI (mode programmatique documenté ; confirme les options avec `copilot --help`) :

```bash
copilot -p "$(cat "$task_artifacts/prompt.md")" --allow-all-tools --output-format json > "$task_artifacts/copilot-verify.json"
```
Copilot est aussi le consommateur manquant : sa propre exécution des hooks du niveau C est la preuve la plus précieuse qu'il peut rapporter.
