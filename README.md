# searx: SearXNG + OpenRouter in your terminal

A small Bash function that searches your own [SearXNG](https://github.com/searxng/searxng) instance from the command line and can optionally summarize the results with an AI model through [OpenRouter](https://openrouter.ai). The AI answer is rendered in the terminal with tables, bold, italic, colors and code highlighting.

## Features

- Search a local SearXNG instance from the shell and print colored results (title, URL, snippet)
- Filter by engines (`-e`) and categories (`-c`)
- AI summary of the top 10 results via OpenRouter (`-a`), with any model slug (`-m`)
- Markdown rendering in the terminal: tables, bold, italic, headings, code blocks, links
- Superscript and subscript HTML tags are converted to Unicode (m², H₂O)
- Graceful fallbacks: raw results if the AI call fails, a built-in formatter if `rich` is not installed
- `sa` alias for a quick AI search

## Dependencies

| Dependency | Required | Purpose |
|---|---|---|
| Bash 4.2+ | Yes | The script is a Bash function (not compatible with zsh/fish as-is) |
| `curl` | Yes | Queries the SearXNG API |
| `jq` | Yes | URL-encodes the query and parses the JSON results |
| `python3` | Yes | Calls the OpenRouter API (standard library only) and renders output |
| [SearXNG](https://github.com/searxng/searxng) instance | Yes | The search backend, with JSON output enabled (see below) |
| OpenRouter API key | Only for `-a` | AI summaries |
| `python-rich` | Optional (recommended) | Full markdown rendering. Without it a simpler built-in formatter is used |

### Install the packages

**Arch Linux**

```bash
sudo pacman -S curl jq python python-rich
```

**Debian / Ubuntu**

```bash
sudo apt install curl jq python3 python3-rich
```

**Fedora**

```bash
sudo dnf install curl jq python3 python3-rich
```

**macOS (Homebrew)**

```bash
brew install bash curl jq python rich
```

If your distribution does not package `rich`, use `pip install rich` in the Python environment that your `python3` command points to.

## Setup

### 1. Enable JSON output in SearXNG

The script uses `/search?format=json`, which SearXNG disables by default. In your SearXNG `settings.yml`, make sure `json` is listed under `search.formats`:

```yaml
search:
  formats:
    - html
    - json
```

Restart SearXNG after changing it. If you get HTTP 403 responses from SearXNG, this setting is the usual cause.

### 2. Set the SearXNG address

The default is `http://localhost:8888`. Change it at the top of the `searx()` function if your instance uses another host or port:

```bash
local SEARX_URL="http://localhost:8888"
```

### 3. Add your OpenRouter API key

Create a key at <https://openrouter.ai/keys> and export it in your shell, for example in `~/.bashrc`:

```bash
export OPENROUTER_API_KEY="sk-or-..."
```

Never commit your key to the repository. A safer option is to keep it in a separate file that is not tracked by Git:

```bash
# ~/.bashrc
[ -f ~/.openrouter_key ] && source ~/.openrouter_key
```

### 4. Load the script

Clone the repo (or copy `searx.sh`) and source it from `~/.bashrc`:

```bash
echo 'source /path/to/searx.sh' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```text
searx [options] <search query>
```

| Option | Description |
|---|---|
| `-e, --engines <list>` | Comma-separated SearXNG engines, e.g. `google,wikipedia` |
| `-c, --categories <list>` | Comma-separated categories, e.g. `science,news` |
| `-a, --ai` | Summarize the top 10 results with OpenRouter |
| `-m, --model <slug>` | OpenRouter model slug (default: `openai/gpt-oss-20b`) |
| `-r, --raw` | Print the AI answer as plain markdown, without rendering |
| `-h, --help` | Show help |

### Examples

```bash
# Plain results
searx "arch linux wiki pacman"

# Only some engines
searx -e wikipedia,duckduckgo "histamine"

# AI summary
searx -a "antihistamines"

# AI summary with a different model
searx -a -m "openai/gpt-oss-120b" "how does a heat pump work"

# Shortcut alias (defined at the end of searx.sh)
sa "best terminal file managers"

# Plain markdown output, useful for piping or copying
searx -a -r "docker vs podman" > answer.md
```

## Configuration

| Setting | Where | Default |
|---|---|---|
| SearXNG URL | `SEARX_URL` in `searx()` | `http://localhost:8888` |
| Default model | `AI_MODEL` in `searx()` | `openai/gpt-oss-20b` |
| Max response tokens | `max_tokens` in the Python payload | `2000` |
| Request timeout | `timeout` in `urlopen` | `90` seconds |
| Results sent to the AI | `.results[:10]` in the `jq` filter | `10` |
| Code block theme | `Markdown(text, code_theme="...")` in `_searx_render` | rich default |
| Alias | last line of `searx.sh` | `sa` = `searx -a` |

## How it works

1. The query is URL-encoded with `jq` and sent to your SearXNG instance with `curl`.
2. Without `-a`, the JSON results are printed as colored title, URL and snippet.
3. With `-a`, the top 10 results are sent to OpenRouter's chat completions endpoint (`https://openrouter.ai/api/v1/chat/completions`) with a system prompt asking for a short markdown answer.
4. The reply is cleaned up (`<br>`, `<sup>`, `<sub>` and other HTML tags are converted or removed) and rendered with `rich`, or with the built-in formatter if `rich` is not available.
5. If anything fails in the AI step, the script prints the error and falls back to the plain results.

The script shares only the search results and your query with OpenRouter. Keep that in mind for sensitive searches.

## Troubleshooting

| Problem | Likely cause and fix |
|---|---|
| `No results found from SearXNG` | SearXNG is not running, the URL or port is wrong, or JSON output is not enabled in `settings.yml` |
| `OPENROUTER_API_KEY is not set` | Export the key in your shell and run `source ~/.bashrc` |
| `HTTP Error 401` | The API key is invalid |
| `HTTP Error 404` | The model slug does not exist or is not available to your account |
| `HTTP Error 429` | Rate limit reached. Wait or use another model |
| Empty response from the model | Reasoning models can use the token budget on reasoning. Increase `max_tokens` or pick another model |
| Tables show as raw markdown or look plain | `rich` is not importable. Run `python3 -c "import rich"`. If it fails, your `python3` may be a venv, pyenv or conda interpreter. Install `rich` there, or install the system package (the script also tries `/usr/bin/python3`) |
| Odd characters or broken colors | Use a terminal with UTF-8 and ANSI color support |

## License

Released under the [MIT License](LICENSE).
