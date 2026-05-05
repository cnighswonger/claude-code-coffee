# claude-code-coffee

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](https://opensource.org/licenses/MIT) [![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-blue)](https://github.com/anthropics/claude-code)

A [Claude Code](https://github.com/anthropics/claude-code) skill that keeps your prompt cache warm while you're away. Prevents expensive cold cache rebuilds when you return from a break.

## The problem

When you step away from a Claude Code session, the prompt cache expires after its TTL (5 minutes under overage pricing, 1 hour normally). Returning to a large context forces a full cache rebuild at $10/MTok (1h write) instead of a cache read at $0.50/MTok. A 460k token context costs ~$3.86 to rebuild from scratch.

## The solution

`/coffee 30` schedules lightweight periodic pings that keep the cache in the "read" state while you're away. Each ping costs ~17x less than a cold rebuild.

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
| `/coffee overnight` | Until 8 AM | Overnight warmer |
| `/coffee overnight 7` | Until 7 AM | Custom wake time |

When invoked, the skill:
1. Detects your current cache TTL tier (5min or 1h)
2. Estimates your context size
3. Shows a cost breakdown (ping cost vs cold start cost vs savings)
4. Schedules recurring keepalive pings at the right interval
5. Schedules an auto-cleanup that stops pings when your break/night is over

To cancel early, ask Claude to delete the keepalive cron job.

## Cost model

| Rate | Claude Opus 4.6/4.7 |
|------|---------------------|
| Cache read (what pings cost) | $0.50/MTok |
| Cache creation 1h (what cold starts cost) | $10.00/MTok |
| Cache creation 5m (overage cold starts) | $6.25/MTok |

### Per-ping vs cold start at common context sizes

| Context | Ping cost | Cold start (1h) | Pings per cold start |
|---------|-----------|-----------------|---------------------|
| 200K | $0.10 | $2.00 | ~20 |
| 460K | $0.23 | $4.60 | ~20 |
| 900K | $0.45 | $9.00 | ~20 |

One cold start buys ~20 warmer pings at 50-minute intervals — enough to cover ~16 hours of idle time.

### When the warmer earns its keep

**Daytime breaks (coffee, lunch, meetings):** Clear win. 1-4 pings vs 1 cold start. Each break you take without the warmer costs $2-9 depending on context size.

**Overnight (8-10 hours):** At 50-minute intervals, ~9-10 pings per overnight. Costs ~40% less than a morning cold start at typical context sizes. On subscription plans, there's an additional benefit: overnight pings burn Q5h in idle quota windows, preserving headroom for morning work.

**During active work:** Not needed — your real turns keep the cache warm. The warmer adds the most value when you're away from the keyboard.

### Real-world data (10-day session)

From a metered 10-day session on Max 5x with ~460K context:

| Metric | Value |
|--------|-------|
| Total warmer pings | 429 |
| Avg ping cost | $0.23 |
| Avg cold start cost | $3.86 |
| Per-ping ROI | 16.8x |
| Cache hit rate during pings | 99.8%+ |
| Clean overnight pings (per night) | 9-10 |
| Overnight cost (per night) | $2.07-$2.30 |
| Cold start it prevents | $3.86 |

The warmer's overnight value is also **Q5h timing** on subscription plans: pings during idle hours burn quota in windows you won't use, preserving your fresh morning Q5h budget.

Full analysis: [What We Learned from a 10-Day Session](https://veritassuperaitsolutions.com)

## Stale cache safety

Each warmer ping checks the timestamp of the last API call before executing. If the gap exceeds the cache TTL (65 minutes for 1h tier, 6 minutes for 5m tier), the ping **skips** and warns instead of triggering an expensive cold rebuild.

This protects against:
- **Resume after overnight**: if you `/exit` with a warmer running and `--continue` the next morning, the first warmer fire sees the multi-hour gap and skips instead of rebuilding your full context at cold-start rates
- **Stale sessions**: any scenario where the cache has already expired by the time the ping fires
- **Unexpected interruptions**: network drops, system sleep, or service restarts that cause a gap longer than the TTL

When a skip occurs, the warmer recommends `/compact` before continuing — reducing the inevitable cold-start cost from the full context size down to the compacted summary.

## Known limitations

- **Subagent/teammate cache TTL**: Subagents and teammates receive a **5-minute ephemeral cache TTL**, not the 1-hour TTL that the main session gets. The default 50-minute ping interval does not keep subagent caches warm. Subagents would need `*/4` cron intervals.
- **Context drift on first ping**: The first keepalive ping after scheduling typically has a lower cache hit rate because the context has shifted slightly since the last real interaction. Subsequent pings hit 99.8%+ cache read rates.
- **Cannot suppress during active work**: The warmer doesn't detect whether you're actively using the session. If left running 24/7, daytime pings during active work are redundant. Use `/coffee` per-break or `/coffee overnight` rather than running it continuously.

## Cache TTL detection

The skill reads cache-fix's quota-status file to detect your cache TTL tier:
- **1h tier** — normal operation (Q5h quota < 100%)
- **5m tier** — overage pricing active (Q5h quota >= 100%)

Path varies by cache-fix version:
- **v3.5.0+** (proxy mode, per-session split): `~/.claude/quota-status/account.json`
- **v3.4.x and earlier** (or preload mode): `~/.claude/quota-status.json`

The skill tries the v3.5.0+ path first and falls back to the legacy path. If neither file is available, the skill conservatively assumes the 5min tier.

For accurate TTL detection, install [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix), which writes the quota status file from API response headers.

## Requirements

- Claude Code with cron scheduling support (CronCreate tool)
- Node.js >= 18

## Related

- [claude-code-cache-fix](https://github.com/cnighswonger/claude-code-cache-fix) — Prompt cache interceptor (140+ stars)
- [claude-code-meter](https://github.com/cnighswonger/claude-code-meter) — Community cost analytics with [live dashboard](https://meter.veritassuperaitsolutions.com)
- [VS Code extension](https://github.com/cnighswonger/claude-code-cache-fix-vscode) — One-click activation for VS Code users

## Support

If this tool saved you money, consider buying us a coffee:

<a href="https://buymeacoffee.com/vsits" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## License

[MIT](LICENSE)
