#!/usr/bin/env python3
"""Per-phase time/token/cost report for the two-profile benchmark (see protocol.md).

Reads Claude Code transcript JSONL from one project directory per worktree and,
optionally, Codex CLI rollout logs for the implementation phase. Phases are delimited
by driver prompts starting with a "[BENCH <ID>]" marker.

Usage:
  python3 bench_report.py --label two-role \
      --claude-dir ~/.claude/projects/-Users-luca-Projects-AgentsWorkflowTests-bench-two \
      --codex-cwd /Users/luca/Projects/AgentsWorkflowTests-bench-two
"""

import argparse
import datetime as dt
import glob
import json
import os
from collections import defaultdict

# USD per 1M tokens: (input, output). Cache read = 0.1x input.
# Cache write = 1.25x input (5m TTL) or 2x input (1h TTL) — Claude Code uses 1h.
CLAUDE_PRICES = {
    "claude-fable-5": (10.0, 50.0),
    "claude-opus-5": (5.0, 25.0),
    "claude-sonnet-5": (2.0, 10.0),  # intro pricing through 2026-08-31 (sticker: 3/15)
    "claude-haiku-4-5": (1.0, 5.0),
}
CACHE_READ_FACTOR = 0.1
CACHE_W5M_FACTOR = 1.25
CACHE_W1H_FACTOR = 2.0

MARKER = "[BENCH "


def parse_ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def load_claude_entries(claude_dir):
    entries = []
    for path in glob.glob(os.path.join(os.path.expanduser(claude_dir), "*.jsonl")):
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = e.get("timestamp")
                if not isinstance(ts, str):
                    continue
                try:
                    e["_ts"] = parse_ts(ts)
                except ValueError:
                    continue
                entries.append(e)
    entries.sort(key=lambda e: e["_ts"])
    return entries


def phase_windows(entries):
    """[BENCH <ID>] user prompts (main session only) delimit the phases."""
    markers = []
    for e in entries:
        if e.get("type") != "user" or e.get("isSidechain"):
            continue
        text = text_of((e.get("message") or {}).get("content")).lstrip()
        if text.startswith(MARKER):
            pid = text[len(MARKER):].split("]", 1)[0].strip()
            markers.append((e["_ts"], pid))
    windows = []
    for i, (ts, pid) in enumerate(markers):
        end = markers[i + 1][0] if i + 1 < len(markers) else None
        windows.append((pid, ts, end))
    return windows


def is_user_prompt(e):
    """A prompt typed by the human (incl. slash commands) — not tool results,
    not sidechain (subagent) prompts, not harness meta entries."""
    if e.get("type") != "user" or e.get("isSidechain") or e.get("isMeta"):
        return False
    content = (e.get("message") or {}).get("content")
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        return not any(
            isinstance(b, dict) and b.get("type") == "tool_result" for b in content
        )
    return False


def is_work_event(e):
    """Model/tool activity: assistant output, tool results coming back, file
    edits landing. Everything else the harness writes (attachments batched with
    the next prompt, away summaries, hook logs, a new session's preamble) is
    bookkeeping — it must not close a gap as if the machine had been working."""
    t = e.get("type")
    if t in ("assistant", "file-history-delta"):
        return True
    if t == "user" and not e.get("isMeta"):
        content = (e.get("message") or {}).get("content")
        return isinstance(content, list) and any(
            isinstance(b, dict) and b.get("type") == "tool_result" for b in content
        )
    return False


def accumulate_phases(entries, windows, max_gap=None):
    """Active time: work runs from each human prompt to the last work event of
    its turn; the wait before the next human prompt is idle. Only work events
    close a gap as work — every work-closed gap counts, whatever its length
    (long thinking stretches included). `max_gap`, when set, additionally caps
    work-closed gaps (safety valve for crashed sessions). Windows sharing a
    phase ID (rework loops that reuse a marker) are summed."""
    phases = {}
    for pid, start, end in windows:
        span = [e for e in entries if e["_ts"] >= start and (end is None or e["_ts"] < end)]
        active = 0.0
        prev = None
        usage = defaultdict(lambda: defaultdict(int))
        seen_msg_ids = set()  # a multi-block assistant message repeats its usage per line
        for e in span:
            if is_user_prompt(e):
                prev = e["_ts"]  # a turn starts here; the wait before it was idle
            elif is_work_event(e) and prev is not None:
                delta = (e["_ts"] - prev).total_seconds()
                if delta >= 0 and (max_gap is None or delta <= max_gap):
                    active += delta
                prev = e["_ts"]
            if e.get("type") != "assistant":
                continue
            msg = e.get("message") or {}
            u = msg.get("usage")
            model = msg.get("model") or ""
            if not u or not model or model.startswith("<"):
                continue
            msg_id = msg.get("id") or e.get("requestId") or e.get("uuid")
            if msg_id in seen_msg_ids:
                continue
            seen_msg_ids.add(msg_id)
            m = usage[model]
            m["input"] += u.get("input_tokens") or 0
            m["output"] += u.get("output_tokens") or 0
            m["cache_read"] += u.get("cache_read_input_tokens") or 0
            cc = u.get("cache_creation")
            if isinstance(cc, dict):
                m["cache_w5m"] += cc.get("ephemeral_5m_input_tokens") or 0
                m["cache_w1h"] += cc.get("ephemeral_1h_input_tokens") or 0
            else:
                m["cache_w5m"] += u.get("cache_creation_input_tokens") or 0
        if pid in phases:  # marker reused (rework loop) — merge into the phase
            phases[pid]["active_s"] += active
            for model, m in usage.items():
                dst = phases[pid]["usage"][model]
                for k, v in m.items():
                    dst[k] += v
        else:
            phases[pid] = {"active_s": active, "usage": usage}
    return phases


def claude_cost(model, m):
    price = None
    for prefix, p in CLAUDE_PRICES.items():
        if model.startswith(prefix):
            price = p
            break
    if price is None:
        return None
    pin, pout = price
    return (
        m["input"] * pin
        + m["cache_read"] * pin * CACHE_READ_FACTOR
        + m["cache_w5m"] * pin * CACHE_W5M_FACTOR
        + m["cache_w1h"] * pin * CACHE_W1H_FACTOR
        + m["output"] * pout
    ) / 1_000_000


def _find_values(obj, key):
    """Recursively yield every value for `key` in a nested JSON structure."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == key:
                yield v
            else:
                yield from _find_values(v, key)
    elif isinstance(obj, list):
        for item in obj:
            yield from _find_values(item, key)


def codex_sessions(sessions_root, cwd, since, gap):
    """Codex rollouts matching the worktree cwd: (times, cumulative usage) per session."""
    results = []
    pattern = os.path.join(os.path.expanduser(sessions_root), "**", "rollout-*.jsonl")
    for path in glob.glob(pattern, recursive=True):
        if dt.datetime.fromtimestamp(os.path.getmtime(path)) < since:
            continue
        timestamps, last_usage, session_cwd = [], None, None
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if session_cwd is None:
                    for v in _find_values(e, "cwd"):
                        session_cwd = v
                        break
                ts = e.get("timestamp")
                if isinstance(ts, str):
                    try:
                        timestamps.append(parse_ts(ts))
                    except ValueError:
                        pass
                for v in _find_values(e, "total_token_usage"):
                    last_usage = v  # cumulative — the last one wins
        if session_cwd != cwd or last_usage is None or not timestamps:
            continue
        timestamps.sort()
        active = sum(
            d for d in (
                (b - a).total_seconds() for a, b in zip(timestamps, timestamps[1:])
            ) if 0 <= d <= gap
        )
        results.append({"path": path, "start": timestamps[0], "active_s": active,
                        "usage": last_usage})
    results.sort(key=lambda r: r["start"])
    return results


def fmt_time(seconds):
    return f"{int(seconds // 60):d}m{int(seconds % 60):02d}s"


def fmt_tokens(n):
    return f"{n / 1000:.1f}k" if n >= 1000 else str(n)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--label", default="")
    ap.add_argument("--claude-dir", required=True)
    ap.add_argument("--codex-cwd", default=None)
    ap.add_argument("--codex-sessions", default="~/.codex/sessions")
    ap.add_argument("--codex-price-in", type=float, default=None, help="USD per 1M input")
    ap.add_argument("--codex-price-out", type=float, default=None, help="USD per 1M output")
    ap.add_argument("--since", default=None,
                    help="YYYY-MM-DD; bound the Codex rollout scan (default: 7 days ago)")
    ap.add_argument("--gap", type=float, default=120.0,
                    help="Codex idle threshold in seconds (default 120)")
    ap.add_argument("--max-gap", type=float, default=None,
                    help="optional cap for machine-closed gaps in Claude transcripts")
    args = ap.parse_args()

    since = (dt.datetime.strptime(args.since, "%Y-%m-%d") if args.since
             else dt.datetime.now() - dt.timedelta(days=7))

    entries = load_claude_entries(args.claude_dir)
    windows = phase_windows(entries)
    phases = accumulate_phases(entries, windows, args.max_gap)

    title = f"Benchmark report — {args.label or args.claude_dir}"
    print(title)
    print("=" * len(title))
    if not phases:
        print("No [BENCH <ID>] markers found — nothing to report yet.")

    header = (f"{'phase':<8} {'active':>8} {'model':<22} {'input':>9} {'output':>9} "
              f"{'cache_r':>10} {'cache_w':>10} {'cost USD':>9}")
    total_cost, cost_complete = 0.0, True
    if phases:
        print(header)
        print("-" * len(header))
    for pid, data in phases.items():
        first = True
        for model, m in sorted(data["usage"].items()):
            cost = claude_cost(model, m)
            if cost is None:
                cost_complete = False
            else:
                total_cost += cost
            cache_w = m["cache_w5m"] + m["cache_w1h"]
            print(f"{pid if first else '':<8} "
                  f"{fmt_time(data['active_s']) if first else '':>8} "
                  f"{model:<22} {fmt_tokens(m['input']):>9} {fmt_tokens(m['output']):>9} "
                  f"{fmt_tokens(m['cache_read']):>10} {fmt_tokens(cache_w):>10} "
                  f"{f'{cost:.2f}' if cost is not None else 'n/d':>9}")
            first = False
        if first:  # marker seen but no assistant usage in the window
            print(f"{pid:<8} {fmt_time(data['active_s']):>8} {'—':<22}")

    if args.codex_cwd:
        sessions = codex_sessions(args.codex_sessions, args.codex_cwd, since, args.gap)
        if not sessions:
            print(f"\nIMPL: no Codex rollout found for cwd {args.codex_cwd} "
                  f"(since {since.date()})")
        for i, s in enumerate(sessions):
            u = s["usage"]
            tin = u.get("input_tokens", 0)
            tout = u.get("output_tokens", 0)
            cached = u.get("cached_input_tokens", 0)
            cost = None
            if args.codex_price_in is not None and args.codex_price_out is not None:
                # cached input billed as input here unless a cached rate is known
                cost = (tin * args.codex_price_in + tout * args.codex_price_out) / 1e6
                total_cost += cost
            else:
                cost_complete = False
            label = "IMPL" if len(sessions) == 1 else f"IMPL{i + 1}"
            print(f"{label:<8} {fmt_time(s['active_s']):>8} {'codex':<22} "
                  f"{fmt_tokens(tin):>9} {fmt_tokens(tout):>9} {fmt_tokens(cached):>10} "
                  f"{'—':>10} {f'{cost:.2f}' if cost is not None else 'n/d':>9}")

    print(f"\nTotal estimated cost: "
          f"{'$%.2f' % total_cost}{'' if cost_complete else ' (incomplete — some rows n/d)'}")


if __name__ == "__main__":
    main()
