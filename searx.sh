# searx.sh - SearXNG CLI search with optional OpenRouter AI summary
# SPDX-License-Identifier: MIT
#
# Source this file from ~/.bashrc:
#   source /path/to/searx.sh
#
# Requires: bash, curl, jq, python3, a running SearXNG instance with JSON output enabled,
#           and (for -a) the OPENROUTER_API_KEY environment variable.
# Optional: python-rich (nicer terminal rendering of the AI answer).
# See README.md for details.

# Renders markdown nicely in the terminal.
# Uses Python "rich" if installed (tables, bold, italic, colors, code blocks),
# otherwise falls back to a basic ANSI formatter (bold, italic, headings, code, links).
# Install rich on Arch: sudo pacman -S python-rich
_searx_render() {
    # Pick an interpreter that has rich: the default python3 may be a venv/pyenv/conda one
    local PY=python3
    if ! python3 -c "import rich" 2>/dev/null && /usr/bin/python3 -c "import rich" 2>/dev/null; then
        PY=/usr/bin/python3
    fi
    SEARX_MD="$1" "$PY" - <<'PY'
import os, re, sys

text = os.environ.get("SEARX_MD", "")

SUP = str.maketrans("0123456789+-=()ni", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ")
SUB = str.maketrans("0123456789+-=()", "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎")
SUP_OK = set("0123456789+-=()ni")
SUB_OK = set("0123456789+-=()")

def conv(m, table, ok):
    inner = m.group(1)
    if inner and set(inner) <= ok:
        return inner.translate(table)      # e.g. m<sup>2</sup> -> m²
    return " " + inner                      # not convertible (e.g. citation links): keep content

# Terminals cannot do real super/subscript, so convert to Unicode where possible
text = re.sub(r"<br\s*/?>", " ", text, flags=re.I)
text = re.sub(r"<sup>(.*?)</sup>", lambda m: conv(m, SUP, SUP_OK), text, flags=re.I | re.S)
text = re.sub(r"<sub>(.*?)</sub>", lambda m: conv(m, SUB, SUB_OK), text, flags=re.I | re.S)
text = re.sub(r"</?[a-zA-Z][^>]*>", "", text)   # strip any other leftover HTML tags

import shutil, textwrap

def strip_inline(s):
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)   # links -> text
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])", r"\1", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    return s.strip()

def draw_table(rows):
    n = max(len(r) for r in rows)
    rows = [r + [""] * (n - len(r)) for r in rows]
    term = shutil.get_terminal_size((100, 24)).columns
    avail = max(term - (3 * n + 1), n * 6)
    widths = [max(len(r[i]) for r in rows) for i in range(n)]
    while sum(widths) > avail:
        i = widths.index(max(widths))
        if widths[i] <= 6:
            break
        widths[i] -= 1
    def line(l, m, r):
        return l + m.join("─" * (w + 2) for w in widths) + r
    out = [line("┌", "┬", "┐")]
    for ri, row in enumerate(rows):
        wrapped = [textwrap.wrap(c, widths[i]) or [""] for i, c in enumerate(row)]
        height = max(len(w) for w in wrapped)
        for k in range(height):
            cells = []
            for i, w in enumerate(wrapped):
                piece = w[k] if k < len(w) else ""
                piece = piece.ljust(widths[i])
                if ri == 0:
                    piece = "\x1b[1;36m" + piece + "\x1b[0m"
                cells.append(" " + piece + " ")
            out.append("│" + "│".join(cells) + "│")
        out.append(line("├", "┼", "┤") if ri < len(rows) - 1 else line("└", "┴", "┘"))
    return "\n".join(out)

def render_tables(src):
    sep = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")
    lines, out, i = src.split("\n"), [], 0
    while i < len(lines):
        if lines[i].lstrip().startswith("|") and i + 1 < len(lines) and sep.match(lines[i + 1]):
            block = [lines[i]]
            i += 2
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                block.append(lines[i])
                i += 1
            rows = [[strip_inline(c) for c in b.strip().strip("|").split("|")] for b in block]
            out.append(draw_table(rows))
        else:
            out.append(lines[i])
            i += 1
    return "\n".join(out)

try:
    from rich.console import Console
    from rich.markdown import Markdown
    Console().print(Markdown(text))
except ImportError:
    B, I, R = "\x1b[1m", "\x1b[3m", "\x1b[0m"
    text = render_tables(text)
    text = re.sub(r"^(#{1,6})\s+(.*)$", "\x1b[1;36m\\2" + R, text, flags=re.M)
    text = re.sub(r"\*\*(.+?)\*\*", B + "\\1" + R, text)
    text = re.sub(r"(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])", I + "\\1" + R, text)
    text = re.sub(r"`([^`]+)`", "\x1b[33m\\1" + R, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", "\x1b[4;34m\\1" + R + " (\\2)", text)
    print(text)
PY
}

searx() {
    # Local SearXNG instance
    local SEARX_URL="http://localhost:8888"

    local AI_MODEL="openai/gpt-oss-20b"   # default model
    local ENGINES=""
    local CATEGORIES=""
    local QUERY=""
    local AI_SUMMARY=false
    local RAW_OUTPUT=false

    show_help() {
        echo -e "SearXNG CLI Query Tool"
        echo -e "Usage: searx [options] <search query>\n"
        echo -e "Options:"
        echo -e "  -e, --engines <list>     Comma-separated list of engines (e.g., google,wikipedia)"
        echo -e "  -c, --categories <list>  Comma-separated list of categories (e.g., images,science)"
        echo -e "  -a, --ai                 Summarize the results using OpenRouter AI"
        echo -e "  -m, --model <string>     Specify a different OpenRouter model slug"
        echo -e "  -r, --raw                Print the AI answer as plain markdown (no rendering)"
        echo -e "  -h, --help               Show this help message\n"
    }

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                return 0
                ;;
            -a|--ai)
                AI_SUMMARY=true
                shift
                ;;
            -r|--raw)
                RAW_OUTPUT=true
                shift
                ;;
            -m|--model)
                AI_MODEL="$2"
                shift 2
                ;;
            -e|--engines)
                ENGINES="$2"
                shift 2
                ;;
            -c|--categories)
                CATEGORIES="$2"
                shift 2
                ;;
            -*)
                echo "Error: Unknown option $1" >&2
                show_help >&2
                return 1
                ;;
            *)
                QUERY="$*"
                break
                ;;
        esac
    done

    if [[ -z "$QUERY" ]]; then
        echo -e "Error: Missing search query.\n" >&2
        show_help >&2
        return 1
    fi

    # 1. Fetch from local SearXNG (printf avoids encoding a trailing newline)
    local SEARX_API_URL="${SEARX_URL}/search?format=json&q=$(printf '%s' "$QUERY" | jq -sRr @uri)"
    [[ -n "$ENGINES" ]] && SEARX_API_URL="${SEARX_API_URL}&engines=$(printf '%s' "$ENGINES" | jq -sRr @uri)"
    [[ -n "$CATEGORIES" ]] && SEARX_API_URL="${SEARX_API_URL}&categories=$(printf '%s' "$CATEGORIES" | jq -sRr @uri)"

    local RAW_JSON
    RAW_JSON=$(curl -sL "$SEARX_API_URL")

    if [[ -z "$RAW_JSON" ]] || ! echo "$RAW_JSON" | jq -e '.results and (.results | length > 0)' >/dev/null 2>&1; then
        echo "No results found from SearXNG at $SEARX_URL."
        return 0
    fi

    # Route 1: AI summary mode via Python
    if [ "$AI_SUMMARY" = true ]; then
        if [[ -z "$OPENROUTER_API_KEY" ]]; then
            echo -e "\u001b[31mError: OPENROUTER_API_KEY is not set.\u001b[0m Falling back to raw results...\n" >&2
            AI_SUMMARY=false
        else
            echo -e "\u001b[33mFetching results and generating AI summary via ($AI_MODEL)...\u001b[0m\n"

            local SEARCH_CONTEXT
            SEARCH_CONTEXT=$(echo "$RAW_JSON" | jq -r '.results[:10][] | "Title: \(.title)\nURL: \(.url)\nContent: \(.content)\n---"')

            local SYSTEM_PROMPT="You are a terminal-optimized search assistant. Synthesize the search results to answer the user request: \"$QUERY\". Provide a concise markdown response containing a summary answer and references to key URLs found in the text. Be brief. Formatting rules: use standard markdown only (headings, **bold**, *italic*, bullet lists, and tables where comparing things). Never use HTML tags such as <br>, <sup> or <sub>. For superscripts and subscripts use Unicode characters directly (e.g. m², H₂O). Put source links inline as normal markdown links or in a final list of links, not in superscripts."

            local AI_OUTPUT
            local PYTHON_ERR_FILE
            PYTHON_ERR_FILE=$(mktemp)

            export TARGET_AI_MODEL="$AI_MODEL"
            export TARGET_SYSTEM_PROMPT="$SYSTEM_PROMPT"
            export TARGET_SEARCH_CONTEXT="$SEARCH_CONTEXT"

            AI_OUTPUT=$(python3 -c '
import urllib.request
import urllib.error
import json
import os
import sys

try:
    key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    model_name = os.environ.get("TARGET_AI_MODEL", "").strip()
    system_p = os.environ.get("TARGET_SYSTEM_PROMPT", "")
    context = os.environ.get("TARGET_SEARCH_CONTEXT", "")

    url = "https://openrouter.ai/api/v1/chat/completions"

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
        "HTTP-Referer": "https://github.com",
        "X-Title": "SearxNG-Terminal-Client",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }

    payload = {
        "model": model_name,
        "max_tokens": 2000,
        "messages": [
            {"role": "system", "content": system_p},
            {"role": "user", "content": context}
        ]
    }

    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=90) as response:
        raw_body = response.read().decode("utf-8")
        res_data = json.loads(raw_body)
        choices = res_data.get("choices") or []
        if choices:
            content = (choices[0].get("message") or {}).get("content")
            if content and content.strip():
                print(content)
            else:
                print(f"Model returned an empty response: {raw_body}", file=sys.stderr)
                sys.exit(1)
        else:
            print(f"API Backend Warning: {raw_body}", file=sys.stderr)
            sys.exit(1)
except urllib.error.HTTPError as e:
    err_body = e.read().decode("utf-8", errors="ignore")
    print(f"HTTP Error {e.code}: {err_body}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Local runtime error: {str(e)}", file=sys.stderr)
    sys.exit(1)
' 2>"$PYTHON_ERR_FILE")

            local EXIT_STATUS=$?
            local ERR_LOG
            ERR_LOG=$(cat "$PYTHON_ERR_FILE")
            rm -f "$PYTHON_ERR_FILE"

            if [[ $EXIT_STATUS -eq 0 && -n "$AI_OUTPUT" ]]; then
                if [ "$RAW_OUTPUT" = true ]; then
                    printf '%s\n' "$AI_OUTPUT"
                else
                    _searx_render "$AI_OUTPUT"
                fi
                return 0
            else
                echo -e "\u001b[31mOpenRouter pipeline error:\u001b[0m" >&2
                echo -e "\u001b[90m${ERR_LOG:-Unknown Execution Error}\u001b[0m\n" >&2
                echo -e "Falling back to raw results...\n" >&2
                AI_SUMMARY=false
            fi
        fi
    fi

    # Route 2: Default raw terminal output
    echo "$RAW_JSON" | jq -r '
        .results[] | "\u001b[32m\(.title)\u001b[0m\nURL: \(.url)\nSnippet: \(.content // "No snippet available.")\n"
    '
}

# Shortcut: `sa "query"` gives an AI summary directly
alias sa='searx -a'
