---
name: coffee
description: Keep prompt cache warm during idle periods to avoid expensive cold rebuilds. Use when stepping away from a session.
version: 1.1.0
---

# /coffee — Cache Keepalive

You are executing the `/coffee` skill. This keeps the prompt cache warm while the user is away by scheduling lightweight periodic pings that trigger cache reads instead of expensive cache rebuilds.

## Parse Input

The user's input is: `$ARGUMENTS`

**Parsing rules:**
- If empty, `--help`, or `help`: show the **Usage** section below and STOP — do not create any cron jobs.
- If `overnight` or `overnight N`: overnight mode. N is the wake hour in local time (default: 8 = 8:00 AM). Calculate the number of minutes from now until the next occurrence of that hour. If that hour has already passed today, target tomorrow morning. Minimum overnight duration: 60 minutes. Maximum: 840 minutes (14 hours).
- If a bare number (e.g. `30`): treat as minutes.
- If suffixed (e.g. `30m`, `1h`, `2h`): parse accordingly. Convert hours to minutes.
- Default if not specified: 30 minutes.
- Minimum: 5 minutes. Maximum: 480 minutes (8 hours) for non-overnight mode.

## Usage (show this if no args or --help)

```
/coffee [duration]

Keep your prompt cache warm while you're away.

Duration: number of minutes (default: 30). Accepts: 15, 30m, 1h, 2h, overnight
Examples:
  /coffee           — 30 minute coffee break
  /coffee 15        — quick 15 minute break
  /coffee 1h        — hour-long meeting
  /coffee 2h        — long lunch
  /coffee overnight  — warmer until 8:00 AM local, then auto-stop
  /coffee overnight 7 — warmer until 7:00 AM local

How it works:
  Schedules periodic minimal API calls that keep your prompt cache in the
  "cache read" state ($0.30/MTok) instead of letting it expire and forcing
  a full "cache creation" rebuild ($3.75/MTok) when you return.

  The skill detects your current cache TTL tier (5min or 1h) and sets the
  ping interval accordingly. A one-shot cleanup job auto-cancels the pings
  when your break is over.

Cost model (Claude Opus):
  Cache read:     $0.30 / MTok  (what pings cost)
  Cache creation:  $3.75 / MTok  (what a cold start costs)
  A single ping costs ~12.5x less than a cold rebuild.

  Example: 100k context, 30min break, 1h TTL tier:
    1 ping  = ~$0.03
    Cold start = ~$0.38
    Savings: ~$0.35 (92%)
```

If showing usage, STOP HERE. Do not proceed to the steps below.

---

## Step 1: Detect Cache TTL Tier

Read the file `~/.claude/quota-status.json` using the Read tool.

- If the file exists and is valid JSON:
  - Extract `five_hour.pct` (the Q5h quota percentage)
  - If `pct >= 100` OR `overage_status` is present and NOT `"allowed"`: TTL tier = **5 minutes**
  - Otherwise: TTL tier = **1 hour**
  - Note the `five_hour.pct` value for the cost display
- If the file does not exist or cannot be read:
  - TTL tier = **5 minutes** (conservative default)
  - Note: "TTL detection unavailable — using conservative 5min estimate. Install claude-code-cache-fix for accurate TTL detection."

Set the ping interval:
- 5min TTL → ping every **4 minutes** (cron: `*/4 * * * *`)
- 1h TTL → ping every **50 minutes** (cron: `*/50 * * * *`)

## Step 2: Estimate Context Size

You have access to the current conversation context. Estimate the total input token count from the most recent API usage you can observe. If you cannot determine the exact count, use the following heuristic:
- Small context (short conversation): ~20k tokens
- Medium context (moderate conversation): ~60k tokens  
- Large context (long conversation with many tool results): ~120k tokens

Use your best judgment based on the conversation length and complexity you can see.

## Step 3: Calculate and Display Cost Estimates

Using these rate constants:
- **Cache read rate**: $0.30 per million tokens
- **Cache creation rate**: $3.75 per million tokens
- **Output tokens per ping**: ~10 tokens (~$0.001, negligible)

Calculate:
- `duration_minutes` = parsed duration from input
- `ping_interval` = 4 (if 5min TTL) or 50 (if 1h TTL)
- `num_pings` = ceiling(duration_minutes / ping_interval)
- `ping_cost_each` = context_tokens / 1,000,000 * 0.30
- `total_ping_cost` = num_pings * ping_cost_each
- `cold_start_cost` = context_tokens / 1,000,000 * 3.75
- `savings` = cold_start_cost - total_ping_cost

**Context size guidance** (add to display):
- If estimated context is **below 50k tokens**, add a note: "At this context size, cost savings are marginal (~break-even at 35-40k). Latency benefit still applies — warm cache responses are faster."
- If estimated context is **80k+ tokens**, add a note: "Large context — keepalive is highly cost-effective here (47%+ ROI at 100k, scales higher with size)."

Display to the user in this format:

```
Coffee break: {duration} minutes

Cache TTL tier: {tier} {quota_note}
Est. context: ~{context}k tokens
Ping interval: every {interval}min ({num_pings} pings total)

Cost estimate:
  Keepalive pings: ~${total_ping_cost}
  Cold start:       ~${cold_start_cost}
  Savings:          ~${savings} ({savings_pct}%)

Scheduling keepalive...
```

If quota pct >= 80, add a warning: "Quota at {pct}% — consider compacting before your break."
If quota pct >= 100 or overage is active, add: "OVERAGE PRICING ACTIVE — cache keepalive is especially valuable right now."

**Overnight mode additional display:** If the input was `overnight`, add after the cost estimate:
```
Overnight note: Warmer pings during overnight hours burn Q5h in
windows you won't use, preserving headroom for your morning work
session. At 50-min intervals, ~9-10 pings per 8-hour overnight
costs ~40% less than a morning cold start at typical context sizes.
```

## Step 4: Schedule Keepalive Pings

Use the CronCreate tool to create a **recurring** cron job:
- `cron`: the ping interval expression from Step 1 (e.g., `*/4 * * * *` or `*/50 * * * *`)
- `prompt`: "Cache keepalive ping. First, read ~/.claude/quota-status.json and check the timestamp field. If the gap between the timestamp and now is longer than 65 minutes (1h TTL tier) or longer than 6 minutes (5m TTL tier), the cache has already expired. In that case, DO NOT respond with ok. Instead respond: 'Warmer SKIPPED — cache expired (gap: Xm). A ping now would trigger a full cold rebuild. Recommend /compact before continuing.' Otherwise, respond with: ok"
- `recurring`: true

Record the returned job ID — you will need it for the cleanup job.

## Step 5: Schedule Auto-Cleanup

Calculate the cleanup time: current time + duration_minutes.

Use the CronCreate tool to create a **one-shot** cron job that fires at the cleanup time:
- `cron`: the 5-field cron expression for that specific minute/hour/day/month
- `prompt`: "Coffee break is over. Delete the recurring keepalive cron job with ID {ping_job_id} using CronDelete. Then tell the user: 'Coffee break over — cache keepalive stopped. Your cache is warm and ready.'"
- `recurring`: false

## Step 6: Confirm

Tell the user:

For regular breaks:
```
Keepalive active! {num_pings} pings scheduled over {duration}min.
Cache will stay warm until auto-cleanup at {cleanup_time}.

To cancel early: ask me to delete cron job {ping_job_id}
Enjoy your break!
```

For overnight mode:
```
Overnight warmer active! ~{num_pings} pings until {wake_hour}:00.
Cache will stay warm until auto-cleanup at {cleanup_time}.

To cancel early: ask me to delete cron job {ping_job_id}
Good night!
```
