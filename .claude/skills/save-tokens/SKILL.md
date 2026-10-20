---
name: save-tokens
description: Work with fewer tokens in this repository. Use at the start of any scan, refactor, review or multi-file edit, and when the context gets long, or when the user asks to save tokens, be cheaper or be shorter.
---

# Save tokens

Spend tokens on facts that change the answer. Follow these rules in order.

## Find before you read

- Use `Grep` or `git grep -n` to find the line, then `Read` with `offset` and `limit` for that range. Never read a whole course page to find one block.
- Use `wc -l`, `head`, `tail` and `sort | uniq -c` to size or compare files. Compare copies with `diff -q` or `md5 -r`, not by reading both.
- Pipe long command output through `tail -n 20` or `grep`. Never print a full `astrona`, `helm` or `kubectl` log.
- Use one `find` or `git ls-files` per question. Do not list the same folder twice.

## Read once

- Do not re-read a file you just edited. A failed `Edit` already tells you.
- Do not re-read `AGENTS.md`. It is loaded at the start of the session.
- Keep facts you found (paths, counts, line numbers) in your notes and reuse them.

## Batch the work

- Send independent tool calls in one turn.
- Change many similar files with one small script (`python3`, `sed`), then check with `git diff --stat`, not by opening each file.
- Run `astrona validate -c <path>` before `astrona test`. It is fast and needs no cluster.

## Delegate wide scans

- A scan over a whole section or the whole repository goes to an `Explore` agent. Ask for a short table of `path:line` and counts, not file contents.
- Do small scans yourself. A subagent starts cold and re-reads context.

## Write short

- Plan first in a few lines, then do the work. Do not narrate each tool call.
- Final answer: what changed, what you did not check, the one open question. Use a table only for real comparisons.
- Never paste file contents you just wrote. Give the path.

## Keep the context small

- Write scratch files to the scratchpad folder, not to the repository.
- Do one module or one section per task. Do not load several sections "to compare".
- When the context is long, summarize the decisions in five lines and continue from there.
