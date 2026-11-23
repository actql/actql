# Effects and approvals

This page is for authors who write Programs that change external systems and
for operators who decide what may be written. It explains how an Effect is
written, what the Preview shows, when a Run stops at a Checkpoint, who
decides, and how to approve or reject from the CLI or from code.

## Writing an Effect

An **Effect** is the only way a Program changes an external system. The
churn-risk Program ends with one:

```sql
|> EFFECT UPDATE salesforce.Account
     ID id SET (
       Churn_Risk__c = risk.value.level,
       Risk_Reason__c = risk.value.reason
     );
```

`EFFECT UPDATE <target> ID <column> SET (...)` takes the rows flowing into it
and, for each, updates the record whose identifier is in `ID` with the listed
fields. The other forms take the same position at the end of the Program:
`UPSERT` and `DELETE` address records by `ID` the same way, `INSERT` lists the
columns to write, `STORE` writes content (from `SERIALIZE` or a file read)
as an object or rows into a table, and `COMMAND` runs an operation the
Connector declares — sending mail, refreshing an extract. [Writing Programs](../authoring.md#writing-back)
shows each form; each Connector page lists what it offers. The familiar SQL
forms are the same Effects:

```sql
UPDATE salesforce.Account
SET Churn_Risk__c = 'high'
WHERE Id = @account_id;
```

Whichever form you write, the Effect is previewed, decided and recorded in the
same way. A Program with no Effect changes nothing anywhere.

## The Preview

Before an Effect is applied, ActQL computes exactly what it would do and
records that as the **Preview**: which records, which fields, which values.
The Preview fixes the targets and the changes ActQL will apply, and the
approval is bound to that Preview. Right before applying, the Host checks the
permission and the conditions the Preview depends on again; if they changed,
the old approval is not reused. Approval does not guarantee success in the
external system: a conflict, a rejection, an asynchronous completion or a
lost reply are handled afterwards ([what can still happen](#what-can-still-happen-after-approval)).

How much a Preview can show depends on the Connector:

| Strength | What the Preview holds | Applied? |
| --- | --- | --- |
| `full_diff` | The exact targets, the current values and the new values | yes |
| `targeted` | The exact targets and the new values | yes |

A Connector that can read a record before writing it gives you `full_diff`;
one that can address records exactly but not read them first gives
`targeted`, which is applied only when the Connector can also verify the
condition it was approved under at apply time — a version guard, a
conditional request. There is no weaker strength: an Effect whose targets
cannot be resolved before sending cannot be declared.

## Who decides

Policy is checked when the Run is admitted and again at every protected
boundary the Run crosses — each read, each model call, and the commit of each
Effect, immediately before it is sent. Policy is Host configuration, never
part of the Program (see [Local and remote Hosts](hosts.md#policy-who-may-do-what)):

1. The execution-account configuration routes the Effect to `allow`, `deny`
   or `delegate`.
2. The delegated decision follows the Host's policy. For example,
   `effect_policy` configures Local Host decisions. A remote Host can route
   decisions through an approval service.

`allow` and an immediate permit apply the Effect without a pause. `deny` and
an immediate reject stop the Run with the Effect undispatched. **Defer** is
what creates a Checkpoint.

For an embedded Node application, configure the Host policy or request an
explicit stop on submission with `stopBefore: 'commit'`. Pass the Program's
parameter declarations and values if it takes parameters.

```ts
const execution = await client.startSource(source, {
  format: 'aql',
  parameterDeclarations,
  parameters,
  stopBefore: 'commit',
});
```

Review the resulting Checkpoint and use the original Run's decision API.
The top-level `decide` connection option is unavailable in the installed
Node client.

## The Checkpoint

A deferred decision stops the Run at a **Checkpoint** with the Preview
attached, and `run` returns:

```text
$ actql run churn-risk.aql
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

`run` never prompts. The Checkpoint is durable: the process can exit, and the
Run waits until someone resolves it. `actql status run_…` shows the same view
at any time, and `--json` returns it as data for an approval application.

`--stop-before commit` forces a Checkpoint before the first Effect even when
policy would have allowed it. Use it to inspect what a new Program would do:

```sh
actql run churn-risk.aql --profile mock --stop-before commit
```

## Approving and rejecting

From the CLI:

```text
$ actql approve ckpt_… --signer ops-approver
Checkpoint ckpt_…  approved
Run run_…  resuming

$ actql reject ckpt_… --signer ops-approver
Checkpoint ckpt_…  rejected
Run run_…  cancelled
```

In a Node application, use `reviewCheckpoint(id)` to read the sealed
review, then explicitly approve or reject the same ID. To defer, leave the
Checkpoint waiting and send no resolution. The
[Node example](node.md#checkpoints) shows all three choices and waits for
the Run state after the committed decision.

```python
state = execution.wait()
client.approve(state.checkpoint.id)
done = execution.wait()
```

Approving continues the **same Run** from the Checkpoint: nothing that was
already read, inferred or computed is redone. The approval covers exactly the
Preview that was shown — every item in it, and nothing outside it. Effects
declared in the same Stage form one **Effect Set** and are previewed and
approved together, at one Checkpoint; Effects of a later Stage get their own.

`approve --wait` waits for the next stable state and prints it, which is
convenient in scripts. When the Host has `signers` configured, a CLI approval
names one with `--signer`; a Local Host without configured signers records
the approval under the local signing key `actql init` created in the Store,
which identifies the machine's user, not a verified person. Production Hosts
configure signers whose decisions they can verify. An embedded Host
identifies the approver through the client.

## Operations are Effects too

Sending mail, posting a message or starting a job is an Effect like a record
write, declared with `EFFECT COMMAND` ([Writing Programs](../authoring.md#running-an-operation)),
and it goes through the same policy, Preview and Checkpoint. The Preview shows
what the operation would send:

```text
$ actql run churn-digest.aql
Run run_…
  Status      waiting_checkpoint
  Checkpoint  ckpt_…
  Effect      command  slack.post  → #revenue (C0123456789)
  Items       1
  Message
    High churn risk today:
    • Acme Corp: falling usage and a competitor evaluation
    • Globex Inc: support tickets about pricing
```

For mail, the Preview lists every recipient, subject and body. After approval
an operation's item ends `accepted` when the system took the request,
`applied` when it confirmed the result, or `unknown`; mail that Gmail
accepted has not necessarily been delivered.

## What can still happen after approval

- **The target changed.** Right before applying, the Host checks the
  approval and the conditions it was given under. If a `full_diff` Preview no
  longer matches the current values, the stale approval is not reused: the
  item ends `failed` with `conflict`, and Host policy may offer a new Preview
  for a fresh approval.
- **The write failed or its outcome is unknown.** Approval is permission, not
  completion. Each item ends `applied`, `accepted`, `failed` or `unknown`, and
  an unknown outcome is reconciled rather than resent. See
  [Run lifecycle and recovery](run-lifecycle.md).
- **Some items applied, others did not.** There is no transaction across
  systems. The Run records which items were applied and ends `failed` once
  nothing is unknown, so you can see exactly where it stopped.

## Next

- [Run lifecycle and recovery](run-lifecycle.md): states, outcomes, reconciliation.
- [Local and remote Hosts](hosts.md): account configuration, deciders and signers.
- [Connectors](../connectors/README.md): the Effects each Connector offers and their Preview strength.
