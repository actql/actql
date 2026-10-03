# Optional local command hooks

The shared policy in `scripts/local-checks-policy.mjs` distinguishes explicit
Moon package/file selections from whole-project checks. The optional hooks add
pre-launch friction for three command families: unscoped `moon test`, unscoped
`moon build`, and known-heavy `local-checks.mjs run` jobs. They do not run tests,
inspect test results, or start background checks.

Use the execution wrapper for the actual bounded run. From the checkout root:

```sh
node scripts/local-checks.mjs changed
node scripts/local-checks.mjs test moon -- --target js -p execution_relation
node scripts/local-checks.mjs test node -- scripts/local-checks-policy.test.mjs
node scripts/local-checks.mjs build moon -- --target js src/execution_relation
```

Prefer the smallest relevant check and leave complete verification to CI. When
a full local run is deliberately needed, the wrapper accepts an explicit
override and time budget, for example:

```sh
node scripts/local-checks.mjs test moon --allow-heavy --timeout-seconds 180 -- --target js
node scripts/local-checks.mjs build moon --allow-heavy --timeout-seconds 180 -- --target js
node scripts/local-checks.mjs run core --allow-heavy --target js
```

The last example uses the job's workflow timeout; it also accepts
`--timeout-seconds`. These examples are not recommended budgets for every
machine. `--allow-heavy` is deliberate friction, not proof of human approval,
an authorization token, or permission to bypass the client's normal controls.

## What the policy recognizes

- Concrete test packages (`-p`/`--package`) and positional package/file paths
  are focused. Positional package paths also focus builds. `.` and `src` select
  the whole project, including normalized forms such as `./src/`.
- `--target`, `--release`, `--jobs`, `--filter`, and test indices alone do not
  scope a build. A name filter can still compile the complete project.
- Known option values are consumed as values, never guessed to be package
  paths. Unknown Moon options remain unclassified; the wrapper rejects them
  until the shared policy explicitly supports them.
- Heavy jobs are an explicit reviewed list: `core`, `host`, `native`,
  `session-evidence`, `pipeline-evidence`, `client-packages`,
  `client-distribution`, `client-packed`, `client-salesforce`, `workers`,
  `connector-addition`, `duckdb-node`, and `spec`. `lint` does not need a heavy
  override. An unfamiliar job is not assumed cheap or heavy from its timeout.
- Help, dry-run, `list`, and `changed` are reporting operations. Focused Node
  file tests are unaffected. A focused classification is about selection, not
  a runtime guarantee; execution budgets still matter.

## Optional Codex configuration

[Codex's documented hook protocol](https://learn.chatgpt.com/docs/hooks)
supports `PreToolUse`, the `Bash` matcher, JSON stdin with
`tool_input.command`, and a `hookSpecificOutput.permissionDecision` of `deny`.
This adapter never emits `ask`: Codex currently treats that response as an
unsupported hook result and continues the tool call.

The inactive example is
[`examples/codex-local-checks-hooks.json`](examples/codex-local-checks-hooks.json).
If you opt in, merge its entry into your personal `~/.codex/hooks.json`, replace
`/absolute/path/to/actql` with this checkout's path, and review/trust it using
Codex's `/hooks` interface. Preserve existing entries. No configuration is
installed by this repository.

This applies to supported locally orchestrated Codex/Work sessions.
Cloud-orchestrated dots and Work Cloud do not load personal/local command
hooks, even when their tools execute locally. Use the wrapper there; the
personal example does not enable cloud hook enforcement.

## Optional Claude Code configuration

[Claude Code's hook reference](https://code.claude.com/docs/en/hooks)
independently documents the `PreToolUse`/`Bash` input fields and the deny
response used by `scripts/claude-local-checks-hook.mjs`. Its supported response
set differs from Codex's; this adapter deliberately emits only deny or nothing.

The inactive example is
[`examples/claude-local-checks-settings.json`](examples/claude-local-checks-settings.json).
If you opt in, merge its entry into your personal `~/.claude/settings.json`,
replace the absolute checkout path, and inspect it with Claude Code's `/hooks`
interface. Preserve your other settings. Claude cloud sessions do not inherit
your laptop's personal settings file.

Both examples invoke client-named adapters; both adapters are tested with
JSON stdin. Neither modifies tool inputs or emits an `allow` decision. Check
that your actual client loads the entry before relying on the reminder.

## Deliberately limited command matching

The initial hook grammar accepts a single unquoted literal command with words
made of letters, digits, `_ . / : @ % + = , -`, separated by spaces or tabs.
Executables must be literally `moon` or `node`, and the wrapper path must be
`scripts/local-checks.mjs` or `./scripts/local-checks.mjs`. The hook applies
only when the event's absolute `cwd` lies within this checkout. Another
checkout needs its own opt-in entry.

Quotes, globs, shell expansion, aliases, absolute executable paths, `cd`/`env`
prefixes, pipelines, redirects, comments, newlines, and compound commands are
outside this initial grammar. For example, `moon test && echo --allow-heavy`
is **unclassified**, not approved or considered safe. No substring in such a
command acts as an override. The shared wrapper still validates its own
arguments when it is actually used.

A matching wrapper override must be an option before the `--` delimiter, not
a Moon argument or a flag from a different command. Malformed/unknown hook
events and unsupported commands produce no decision. Invalid JSON is reported
on stderr with no stdout decision. No decision lets the normal client flow
continue; it does not certify a command. Hook startup failures and timeouts may
also let tools proceed. This is an opt-in convenience guard, not a universal
shell parser or security boundary.

## Focused tests

```sh
node --test scripts/local-checks-policy.test.mjs scripts/local-checks-hook.test.mjs
```

These tests exercise classification and both adapters without launching Moon,
running workflow jobs, or installing client configuration.
