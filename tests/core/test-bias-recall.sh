#!/usr/bin/env bash
# =============================================================================
# What the bias detector actually catches, on a labelled corpus.
#
# The detector runs on EVERY prompt, on the blocking path, and nobody had
# measured what it returns for that. An adoption review tried four biased
# prompts and three went through: `BIAS_EN_SCOPE_CREEP` required
# "while we're at it" with the apostrophe, so "while you are at it" was not
# seen, and "optimize this loop for maximum performance" matched nothing.
#
# A fixed cost on every turn with unmeasured recall is the same shape as an
# unmeasured Level 2. So the corpus is labelled and the numbers are printed:
# recall on prompts that should warn, and the false-positive rate on ordinary
# requests, which is the number that decides whether users keep the feature on.
#
# Adding a language means adding its two lists. A language with no corpus is
# reported as unmeasured rather than assumed to work.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "$SCRIPT_DIR/../lib/test-helpers.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/craftsman-bias-recall.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export CLAUDE_PLUGIN_ROOT="$ROOT_DIR"
export CLAUDE_PLUGIN_DATA="$WORK/data"
mkdir -p "$CLAUDE_PLUGIN_DATA"

echo "=== Bias detector recall ==="

# Prompts a senior reviewer would flag. Each one is a real shape: an absolute
# ("maximum performance"), a deferral ("skip the tests"), an addition beyond
# the ask ("also add"), a generality nobody asked for ("make it configurable").
BIASED_EN=(
    "refactor everything while you are at it"
    "while we're at it also add caching"
    "optimize this loop for maximum performance"
    "make the report as fast as possible"
    "skip the tests, we ship today"
    "just do it, no time"
    "make it generic for future needs"
    "also add a cache layer"
    "let's also change the schema"
    "make it configurable so we never touch it again"
)

# Ordinary requests. A warning on any of these is the reason a user turns the
# detector off, so this list matters more than the one above.
NEUTRAL_EN=(
    "fix the failing test in OrderTest"
    "why does this query return null"
    "add a value object for the invoice total"
    "explain the layer rules"
    "rename UserService to AccountService"
    "optimize this query, it is slow"
    "the build fails on main, find out why"
    "write a test for the refund path"
    "extract this method, it does two things"
    "update the changelog for 4.9.0"
    "the docs recommend a HashMap here for best performance, is that right?"
    "why is this endpoint slow, the client asked for maximum performance in the SLA"
    "we micro-optimized this last year and it was a mistake"
    "why does the bias detector flag 'while we are at it'?"
    "the ticket says skip the tests, is that wise?"
    "our team lead keeps saying just do it - how do I push back?"
)

# Two output contracts, and a harness that knew only one would report 0% for
# twelve of the thirteen shipped languages. `curated` mode (English only, where
# the model's own language makes precision affordable) emits a direct warning;
# every other language emits a signal note the main model adjudicates.
_warns() {
    local prompt="$1" output
    output=$(printf '{"prompt":%s}' "$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
        | bash "$ROOT_DIR/hooks/bias-detector.sh" 2>&1)
    # `domain_modeling` is not a bias, it is an offer to run /craftsman:design,
    # and counting it here made "add a value object for the invoice total" a
    # false positive on a corpus that calls it an ordinary request. The three
    # categories this measures are the ones that claim the user is about to
    # make a mistake.
    printf '%s' "$output" \
        | grep -viE "domain_modeling|domain modeling" \
        | grep -qE "bias:|Bias signal \("
}

_measure_language() {
    local lang="$1" biased_list="$2" neutral_list="$3"
    local prompt caught=0 false_positives=0 total_biased total_neutral

    eval "local biased=(\"\${${biased_list}[@]}\")"
    eval "local neutral=(\"\${${neutral_list}[@]}\")"
    total_biased=${#biased[@]}
    total_neutral=${#neutral[@]}

    for prompt in "${biased[@]}"; do
        if _warns "$prompt"; then
            caught=$((caught + 1))
        else
            echo "  [$lang] missed: $prompt"
        fi
    done
    for prompt in "${neutral[@]}"; do
        if _warns "$prompt"; then
            false_positives=$((false_positives + 1))
            echo "  [$lang] false positive: $prompt"
        fi
    done

    local recall fp_rate
    recall=$(python3 -c "print(int(round(100 * $caught / $total_biased)))")
    fp_rate=$(python3 -c "print(int(round(100 * $false_positives / $total_neutral)))")
    echo ""
    echo "  ${lang}: recall ${recall}% (${caught}/${total_biased}), false positives ${fp_rate}% (${false_positives}/${total_neutral})"
    echo ""

    if [[ "$recall" -ge 90 ]]; then
        log_pass "$lang recall is at least 90% (${recall}%)"
    else
        log_fail "$lang recall is at least 90%" "${recall}%, ${caught}/${total_biased}"
    fi
    if [[ "$false_positives" -eq 0 ]]; then
        log_pass "$lang flags no ordinary request"
    else
        log_fail "$lang flags no ordinary request" "${false_positives} of ${total_neutral}"
    fi
}

# The user's own language is not an afterthought here: this plugin is used in
# French every day, and `signal` mode is where twelve of thirteen languages
# live, so measuring one of them measures the mode.
BIASED_FR=(
    "refactorise tout tant qu'on y est"
    "et aussi ajoute un cache"
    "rends le service configurable pour plus tard"
    "fais vite, on livre ce soir"
    "code direct, pas le temps"
    "ajoutons aussi la pagination"
    "généraliser ce composant pour le futur"
    "on saute les tests pour cette fois"
    "fais-le maintenant, on verra après"
    "et aussi, ajoute un cache"
    "profites-en pour refactorer le reste"
)

NEUTRAL_FR=(
    "corrige le test qui échoue dans OrderTest"
    "pourquoi cette requête renvoie null"
    "renomme UserService en AccountService"
    "explique les règles de couches"
    "écris un test pour le remboursement"
    "extrais cette méthode, elle fait deux choses"
    "le ticket dit qu'on saute les tests, c'est raisonnable ?"
    "pourquoi le détecteur signale 'tant qu'on y est' ?"
)

_measure_language "en" BIASED_EN NEUTRAL_EN
_measure_language "fr" BIASED_FR NEUTRAL_FR

# Every other shipped language is unmeasured, and that is stated rather than
# left to be discovered by a user in that language.
measured="en fr"
unmeasured=""
for conf in "$ROOT_DIR/hooks/lib/bias-patterns"/*.conf; do
    lang="$(basename "$conf" .conf)"
    case " $measured " in *" $lang "*) continue ;; esac
    unmeasured="${unmeasured}${lang} "
done
echo "  unmeasured languages: ${unmeasured:-none}"
if [[ -n "$unmeasured" ]]; then
    log_pass "the languages with no corpus are named, not assumed to work"
else
    log_pass "every shipped language has a corpus"
fi

test_summary
