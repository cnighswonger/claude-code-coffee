# claude-code-coffee

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](https://opensource.org/licenses/MIT) [![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://github.com/anthropics/claude-code)

A [Claude Code](https://github.com/anthropics/claude-code) skill that keeps your prompt cache warm while you're away. Prevents expensive cold cache rebuilds when you return from a break.

## The problem

When you step away from a Claude Code session, the prompt cache expires after its TTL (5 minutes under overage pricing, 1 hour normally). Returning to a large context forces a full cache rebuild at $3.75/MTok instead of a cache read at $0.30/MTok. A 100k token context costs ~$0.38 to rebuild from scratch.

## The solution

`/coffee 30` schedules lightweight periodic pings that keep the cache in the "read" state while you're away. Each ping costs ~12.5x less than a cold rebuild.

## Installation

**One-liner:**

```bash
mkdir -p ~/.claude/skills/coffee && curl -fsSL https://raw.githubusercontent.com/cnighswonger/claude-code-coffee/main/SKILL.md -o ~/.claude/skills/coffee/SKILL.md
```

**Or clone and install:**

```bash
git clone https://github.com/cnighswonger/claude-code-coffee.git
cd claude-code-coffee
bash install.sh
```

Restart Claude Code after installing to pick up the new skill.

## Usage

```
/coffee [duration]
```

| Command | Duration | Description |
|---------|----------|-------------|
| `/coffee` | 30 min | Default coffee break |
| `/coffee 15` | 15 min | Quick break |
| `/coffee 1h` | 1 hour | Meeting |
| `/coffee 2h` | 2 hours | Long lunch |

When invoked, the skill:
1. Detects your current cache TTL tier (5min or 1h)
2. Estimates your context size
3. Shows a cost breakdown (ping cost vs cold start cost vs savings)
4. Schedules recurring keepalive pings at the right interval
5. Schedules an auto-cleanup that stops pings when your break is over

To cancel early, ask Claude to delete the keepalive cron job.

## Cost model

| Rate | Claude Opus |
|------|-------------|
| Cache read (what pings cost) | $0.30/MTok |
| Cache creation (what cold starts cost) | $3.75/MTok |

### Example: 100k context, 30min break

| TTL Tier | Pings | Ping Cost | Cold Start | Savings |
|----------|-------|-----------|------------|---------|
| 1h (normal) | 1 | ~$0.03 | ~$0.38 | ~$0.35 (92%) |
| 5m (overage) | 7 | ~$0.21 | ~$0.38 | ~$0.17 (44%) |

A single ping is always 12.5x cheaper than a cold rebuild. The break-even is guaranteed.

### Real-world results

Empirical data from 18 pings across 3 sessions (~150 minutes total):

| Metric | Observed |
|--------|----------|
| Warm ping cache read rate | 99.8% |
| Warm ping cost | ~$0.011/ping |
| First ping cost (context drift) | $0.04-0.08 |
| Break-even context size | ~35-40k tokens (single return) |
| ROI at 100k context | ~47% savings vs cold start |
| ROI at 200k+ context | Scales dramatically higher |
| TTL tier maintained | 1h throughout all tests |

The technique is most valuable at **80k+ context** — the kind of context you build during research sessions, long debugging runs, or extended feature work. Below ~35-40k tokens, a single keepalive ping roughly breaks even with one cold start, though latency benefits still apply (warm cache responses are faster).

## Known limitations

- **Subagent/teammate cache TTL**: Subagents and teammates receive a **5-minute ephemeral cache TTL**, not the 1-hour TTL that the main session gets. The default 50-minute ping interval (designed for the 1h TTL) does not keep subagent caches warm. Subagents would need `*/4` cron intervals to maintain their cache, but the skill currently only manages the main session's cache.
- **Context drift on first ping**: The first keepalive ping after scheduling typically has a lower cache hit rate ($0.04-0.08 vs ~$0.011) because the context has shifted slightly since the last real interaction. Subsequent pings hit 99.8%+ cache read rates.

## Cache TTL detection

The skill reads `~/.claude/quota-status.json` to detect your cache TTL tier:
- **1h tier** — normal operation (Q5h quota < 100%)
- **5m tier** — overage pricing active (Q5h quota >= 100%)

If the quota file is not available, the skill conservatively assumes the 5min tier (pings more often, costs slightly more, but always cheaper than a cold start).

For accurate TTL detection, install [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix), which writes the quota status file from API response headers.

## Requirements

- Claude Code with cron scheduling support (CronCreate tool)
- Node.js >= 18

## Related

- [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) — Fixes the prompt cache regression bug that causes up to 20x cost increase on resumed sessions

## Support

If this tool saved you money, consider buying me a coffee:

<a href="https://buymeacoffee.com/vsits" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## License

[MIT](LICENSE)
