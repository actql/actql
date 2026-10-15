# Execution model and guarantees

ActQL runs Programs that an agent may have written a minute ago against
systems that hold real business data. This page states what ActQL guarantees
and what it does not, so that you can decide where you still need a person or
a policy in the loop. The [execution specification](../spec/execution.md)
defines each rule exactly.

The guarantees here are the ones the specification defines. Which features
and Hosts implement them today is recorded separately, in the reference
section's limits and compatibility pages.

## TL;DR

1. Nothing runs without limits. Before each unit of work or external
   operation starts, the finite limits that apply to it are fixed and checked.
2. Business data is changed intentionally only through a declared Effect, and
   every Effect goes through policy.
3. A resumed Run reuses what it already captured — data read, model answers,
   Effect outcomes — and never sends an applied Effect again.
4. An unknown outcome is never guessed. It is reconciled against the external
   system, and if the evidence is not enough it stays unknown.
5. A model's answer has the declared type, but ActQL does not guarantee that
   it is correct.

The rest of this page gives the detail behind each of these.

## Program, Invocation, Run and Result

ActQL distinguishes what you declared, what one execution saw, the record of
that execution, and its output:

| Term | What it is | Changes between executions? |
| --- | --- | --- |
| **Program** | The definition of the work: its reads, computation, Results and Effects. Usually written as SQL/Pipe text, which is translated into one common Program representation | No — the same Program can run many times |
| **Invocation** | One concrete input to one stage of that computation: the bound parameter values plus everything that stage actually read, including model answers. A Program with several stages has several Invocations in one Run | Yes — each execution captures its own observations |
| **Run** | The Host's record of executing it: admission, Checkpoints, Effects sent, their outcomes and recovery | Yes — one per execution |
| **Result** | A named output the Program publishes | Derived from the Invocation |

The same Invocation always produces the same Results. Reading the data again
makes a new Invocation, so that guarantee does not extend to fresh reads, nor
to what an external system does with an Effect once it receives it.

## Run states

A Run is always in exactly one of these states. *Protected work* below means
anything that needs a policy decision: reading from or writing to an external
system, and calling a model.

| State | Meaning |
| --- | --- |
| `preparing` | Preparation is in progress; execution has not been admitted yet |
| `running` | Execution is in progress |
| `waiting_checkpoint` | Stopped at a Checkpoint; no protected work runs until a decision is made |
| `resuming` | An approval was recorded; the same Run is continuing |
| `needs_reconciliation` | The outcome of the execution itself, or of one or more Effects, is unknown and must be resolved |
| `succeeded` | The required computation and the aggregation of Effect outcomes completed. For an asynchronous Effect this can be reached once the external system has accepted the work, before it has finished it |
| `failed` | Finished unsuccessfully, with no unresolved outcome |
| `cancelled` | Cancellation was requested, stopping was confirmed, and no outcome is unresolved |

`succeeded`, `failed` and `cancelled` are final. A Run never reaches them
while an outcome is still unknown.

## Guarantees by area

### Check and plan

- Checking is static. It validates names, types, the definitions the Program
  relies on — Connector sources, model tasks, Effect targets — and the
  capabilities and permissions the Program would need, against what the Host
  publishes. Whether an operation is actually allowed is decided by the Host
  at run time, from its policy and permissions. Checking reads no business
  data.
- Planning fixes the limits the Program runs under. A Program whose limits
  cannot be established is rejected or reported as unsupported; it is never
  run without them. Limits that depend on an earlier stage are fixed before
  the work they apply to starts.
- Checking cannot know what the data contains. Row counts, the actual values
  a model returns and the current state of an external record are only known
  at run time.

`check` reports what it validated, and reads no data:

```text
$ actql check churn-risk.aql
Check  ok
  Sources
    salesforce.accounts   id, description                  read
    snowflake.usage_30d   account_id, active_users, trend  read
  Model task
    model-task:churn-risk.v1   input (notes, active_users, trend) → level, reason
  Effect
    update salesforce.Account   Churn_Risk__c, Risk_Reason__c   write
  Permissions
    salesforce: accounts.read, Account.update
    snowflake:  usage_30d.read
  No data read.
```

A mistake is refused here, with a named reason:

```text
$ actql check churn-risk.aql
Check  failed
  expression_type_mismatch   line 7
    risk.value.level = 1   level is STRING, got INT64
```

### Placement and pushdown

For the churn-risk Program from [Concepts](overview.md#programs), this is
where each step runs:

![Salesforce accounts and aggregated Snowflake usage are read into the ActQL engine, which joins them, sends only the INPUT columns of each account to the LLM, filters on the typed answer, previews the update and, after approval, writes it back to Salesforce. Filtering and aggregation run inside Snowflake.](data-flow.svg)

`explain` shows the same placement, still without reading anything. For each
step it names the **Site** where the work runs (Salesforce, Snowflake, your
machine) and the **Engine** that computes it there. Some choices are left to
the Run on purpose: the engine for the join depends on how many rows arrive,
so `explain` marks it as decided at run time rather than guessing.
[Plans and pushdown](../guides/plans-and-pushdown.md) shows the output.

- The planner may reorder, fuse or push computation down to a Connector, or
  run it elsewhere, only when results, ordering, failure behaviour, the scope of
  observed data and permission boundaries stay exactly the same.
- How much work moves to an external system depends on what each Connector
  declares it can do. A Connector that cannot filter is not asked to.

### Approval and Effects

- Business data is changed intentionally only through a declared Effect.
  Reads and model calls still have their own side effects — API usage,
  charges, access logs — and go through policy for that reason.
- Before an Effect is applied, its changes are computed and stored as a
  preview. How exact the preview is depends on the Connector: it may hold the
  current and new values (`full_diff`), the exact targets and the new values
  (`targeted`), or only the intent, when the targets cannot be resolved in
  advance (`blind`). A blind preview can be shown, but never applied.
- An approval covers that preview only; if the preview would change, a new
  approval is required.
- Policy and the bound approval are checked again immediately before each
  Effect is sent. An approval that is no longer valid stops the Run instead
  of sending. This closes the time-of-check/time-of-use (TOCTOU) gap between
  approval and application.
- Approval is not a guarantee of completion. An approved Effect can still
  fail, or end with an unknown outcome.
- ActQL does not provide transactions across systems. A Run that stops after
  some Effects were applied does not undo them.

`run` stops at the Checkpoint with the exact changes it is about to make:

```text
$ actql run churn-risk.aql --profile mock --stop-before commit
Run run_…
  Status      waiting_checkpoint
  Checkpoint  ckpt_…
  Effect      update  (Salesforce Account)
  Items       2
  Changes
    Acme Corp     Churn_Risk__c   low     → high
                  Risk_Reason__c  (empty) → falling usage and a competitor evaluation
    Globex Inc    Churn_Risk__c   medium  → high
                  Risk_Reason__c  (empty) → support tickets about pricing
```

### Durable execution and unknown outcomes

Each operation sent to an external system is recorded with exactly one
outcome:

| Outcome | Meaning |
| --- | --- |
| `applied` | The external system confirmed the change |
| `accepted` | The external system accepted the work; whether it finally completed or failed is not yet known |
| `failed` | The external system reported a definite failure |
| `unknown` | The request may have been sent, but no provable answer arrived |

Items that were never sent are recorded separately, as `unattempted`. An
Effect with several items records an outcome per item, so an Effect can end
partly applied; the Run then ends `failed` once nothing is unknown.

Approving continues the same Run, and `status` shows the outcome of each
item:

```text
$ actql approve ckpt_…
Checkpoint ckpt_…  approved
Run run_…  resuming

$ actql status run_…
Run run_…
  Status   succeeded
  Effect   update  (Salesforce Account)   2 items
    Acme Corp     applied
    Globex Inc    applied
```

- A resumed or recovered Run reuses the captured observations it holds:
  data that was read, model answers and Effect outcomes. An applied Effect is
  never sent again. If the evidence a resume needs has been lost, ActQL does
  not quietly read the data again and treat it as the same execution.
- `unknown` is never treated as success or as failure. The Run moves to
  `needs_reconciliation`, and the outcome is reconciled through the
  Connector's procedure, using the identity of the Run and the operation —
  for example by looking the operation up. Nothing is resent without
  evidence. If the evidence is not enough, the outcome stays unknown and
  visible:

  ```text
  $ actql status run_…
  Run run_…
    Status   needs_reconciliation
    Effect   update  (Salesforce Account)   2 items
      Acme Corp     applied
      Globex Inc    unknown   reply lost after send; reconciling with Salesforce
  ```
- A matching value in the external system is not, on its own, proof that an
  earlier attempt succeeded: the same value may have been written by someone
  else.
- Requesting cancellation stops new work from starting and asks running work
  to stop. The Run becomes `cancelled` only once stopping is confirmed and no
  outcome is unresolved; an unknown outcome has to be reconciled first.
  Cancellation is not a rollback: observations that were already sent and
  Effects that were already applied stay as they are.
- ActQL does not promise exactly-once delivery from every external system. It
  promises that it will not resend without evidence, and that every uncertain
  outcome stays visible until it is resolved.

### Models and INFER

- Each input row gets an outcome: `ok` with a value of the model task's
  declared type, or a failure with its reason, such as `failed:timeout`.
- The reason is one of `rate_limit`, `timeout`, `provider_error`, `refusal`,
  `schema_invalid`, `safety_rejected` or `truncated`. A response that does not
  match the declared type is `schema_invalid`; it is never passed on as a
  partly typed value.
- By default, failed rows are returned alongside successful ones, so the
  Program decides what to do with them. `ON FAILURE FAIL` on the `INFER`
  step fails the whole step instead. Failures are never replaced with defaults.
- Only transient failures — rate limits, timeouts, provider errors — are
  retried, within fixed bounds. Refusals and invalid responses are not
  retried, and nothing is retried silently.
- If the number of rows would exceed the limit, no model is called at all.
- ActQL does not guarantee that a model's answer is correct. Use policy and
  Checkpoints to put a person in the loop where a wrong answer would be costly.
- The Run records the answer it adopted and the evidence of each attempt.
  Recovery reuses the adopted answer instead of calling the model again.

### Bounded execution

- Every runnable Program has a ceiling for each capacity that matters —
  rows, bytes, model calls, Effects.
- Exceeding a ceiling fails the protected work with an error. It never
  silently truncates data or returns a partial result as if it were complete.

### Security and data

- Programs never contain credentials. The Host manages them, and a Connector
  uses them only for an operation the Host has admitted.
- A Connector's declared capability is not permission. Whether a read or an
  Effect may happen is decided by the Host's current policy for that exact
  operation.
- Data leaves for an external system only through the operations the plan
  admits — a model call, a pushed-down query, an Effect.
- Run records can contain business data and model answers. They are kept as
  private evidence by the Host and are subject to its retention settings.

## Next

- [Concepts](overview.md): the vocabulary used on this page.
- [Architecture](architecture.md): which component enforces each guarantee.
- [Execution specification](../spec/execution.md): the normative rules.
