# Debugging and troubleshooting

This page is for the moment something does not work: a Program is refused at
check time, a Run fails or stops, or a result is not what you expected. It
goes through the places to look, in the order you will meet them.

## The order of things

Problems surface at four points, and each has its own tool:

| Where | Tool | Reads data? |
| --- | --- | --- |
| The Program itself | `actql check` | no |
| The plan and limits | `actql explain` | no |
| The Run | `actql status`, `actql run --json` | yes |
| Available command syntax | `actql --help`, `actql check --help` | no |

Environment inspection is separate: see [The environment](#the-environment).
Help lists supported arguments; it does not validate project configuration.

Start at the top. Most failures are caught by `check` without touching any
system, and under `--profile mock` you can take a Program all the way to a
Checkpoint without credentials.

## Check failures

`check` reports every problem it can find, with a named reason and a
location:

```text
$ actql check churn-risk.aql
Check  failed
  expression_type_mismatch   line 7
    risk.value.level = 1   level is STRING, got INT64
  parameter_undeclared       line 3
    @since is used but not declared
```

The reason names are stable and listed in the
[check reason catalog](../reference/check-reasons.md). The ones you will see
most:

| Reason | Typical cause | Fix |
| --- | --- | --- |
| `query_syntax_invalid`, `query_lexical_invalid` | A typo, an unsupported clause, a missing `|>` | Compare with [Writing Programs](../authoring.md) |
| `source_selector_unregistered` | `salesforce.accounts` is not a source of any configured connection | Inspect the configured Catalog material; fix the connection name or resource, then check the same Program |
| `expression_type_mismatch` | Comparing or combining values of different types | Cast explicitly, or fix the literal |
| `parameter_undeclared`, `parameter_value_required` | `@name` is used but not declared, or declared but not supplied | Declare it, and pass `--params` |
| `query_alias_absent` | A column is referenced through an alias that does not exist | Check `AS` names, including the `INFER … AS` name |
| `graph_operation_invalid` | A graph operation got an argument of the wrong kind | See the graph section of [Writing Programs](../authoring.md) |
| `implementation_limit` | The Program is valid but uses something this Host cannot run yet | See [Implementation status](../reference/status.md) |

`check --json` returns the same report as data, which is what an agent should
read before trying again. A warning does not stop `check` from returning 0;
an error does.

Not every reason means the Program is wrong. Three things are reported
separately: the Program is **invalid** (`query_syntax_invalid`,
`expression_type_mismatch` — fix the text); the check is **incomplete** —
a value is missing (`parameter_value_required`), the checker ran out of
budget (`analysis_budget_exhausted`), or something could not be resolved
within your permissions (`unresolved_protected`) — supply the value or ask,
the Program may be fine; or this Host **cannot run** a valid Program
(`implementation_limit`). Read the verdict, the completeness and the
environment support as three facts, not one severity.

## Plan problems

If `check` passes but `explain` refuses, the Program is valid and the Host
cannot bound it: a source without a row limit, a model step whose item count
cannot be established, or a Capability the Program relies on that the
connection does not declare. The message names the missing bound or
capability. Add a `LIMIT`, a `MAX ITEMS` guard, or a filter the source can
evaluate, and read [Plans and pushdown](plans-and-pushdown.md) for how
placement is decided.

## Run failures

A Run that ends `failed` tells you where:

```text
$ actql status run_…
Run run_…
  Status   failed
  Failed   read snowflake.usage_30d
           ACTQL_E_SOURCE_READ_FAILED  Snowflake: SQL compilation error: Object 'USAGE_30D' does not exist
  Effects  none sent
```

Read it by state:

| Status | Likely cause | What to do |
| --- | --- | --- |
| `failed` during a read | Credentials, a missing object, a limit exceeded | Fix the connection or the Program; run again |
| `failed` during `INFER` | `ON FAILURE FAIL` and a failed row, or the item limit exceeded before any call | Check `outcome` values with a mock run, or lower the input |
| `waiting_checkpoint` | A decision is pending | `approve` or `reject` |
| `needs_reconciliation` | A write's outcome is unknown | `reconcile`; see [Run lifecycle](run-lifecycle.md) |
| `cancelled` | Someone cancelled it, or rejected its Checkpoint before anything was sent | Nothing was written; adjust and run again |

Runs are never silently cut short: a limit that was hit is named in the
failure, and a partial result is never presented as complete. Every error has
a stable `ACTQL_E_*` code; `status --json` carries it with the full Run state.

Running the same Program again creates a new Run. The old one stays in the
Store with its evidence for the retention period, so you can compare.

## Unexpected results

- **Fewer rows than expected after `INFER`.** Rows whose outcome is not `ok`
  have `value = NULL` and fall out of a `WHERE risk.value.level = 'high'`.
  Look at the outcomes first: `|> AGGREGATE COUNT(*) GROUP BY risk.outcome`.
- **A filter seems ignored.** It is applied; check whether it runs in the
  source (`explain`) and whether the source's semantics differ, for example
  case-sensitive string comparison.
- **The model's answer looks wrong.** The type is guaranteed, the judgement is
  not. The mock profile cannot tell you whether a prompt is good — it returns
  fixed answers — so use it to check what happens around the model: the
  input columns, the types, the failed-row handling, the Effect. To compare
  two versions of a task's instructions, run both against the real provider
  on the same evaluation rows.
- **An Effect's result does not match the Preview.** Tell four things apart:
  the approved Preview (what ActQL set out to change), the send record (what
  was sent and when), the Connector's outcome receipt (`applied`, `accepted`,
  `failed`, `unknown`) and the external system's current value. The Preview
  fixes the approved change; it does not guarantee the external system
  succeeded, and it says nothing about what a third party changed afterwards.
  An `unknown` outcome goes to reconciliation.

## The environment

The current Native CLI does not implement `doctor` or the `catalog` commands.
Those are [v0.1 target interfaces](../cli.md#discovery), not available
environment probes. The help output describes syntax; it does not inspect
configuration, Store files, keys or provider connectivity.

Inspect `actql.config.json` and the connector/model files it actually names.
For example, an initialized `churn-risk-mock` project selects its independent
Catalog through `mock.catalog` at `./mock/catalog.json`. Compare its declared
connection, resource and column names with the Program. Reading those files
does not establish provider reachability or current permission.

From that initialized Local project, use the same Program and configuration
for check and plan diagnostics. For status, substitute an existing Run ID
from that project; do not submit a replacement Run just to inspect its state:

```text
actql --mode local --config actql.config.json check churn-risk.aql --json
actql --mode local --config actql.config.json explain churn-risk.aql --json
actql --mode local --config actql.config.json status <existing-run-id> --json
```

These commands report the Program, plan or retained Run state. They are not
a replacement for the unavailable combined installation diagnosis or a
connection-wide Catalog listing.

## Getting help

Collect the same-Program `check --json` and `explain --json` reports and,
when relevant, the existing Run's `status --json` report using the forms
above. The current Native CLI has no `--redact` option. These outputs may
contain connection/resource names, parameters, Run references and Preview
values. Before sharing, manually remove secrets and private values while
retaining the relevant reason codes and report structure. This is a review
you perform, not automatic CLI redaction.

## Next

- [Check reason catalog](../reference/check-reasons.md): every reason `check` can report.
- [Run lifecycle and recovery](run-lifecycle.md): states and reconciliation.
- [CLI reference](../cli.md): `--json` output of each command.
