# Models and INFER

This page is for authors who want an LLM to judge, classify, extract or draft
something for each row. It shows how to define a model task, register it with
a provider, call it with `INFER`, and work with the typed answers — including
what happens when the model fails, is retried, or is never called.

## The division of labour

A model task says *what to ask the model and what comes back*. The SQL says
*which rows to apply it to and what to do with the answers*. Keeping the two
apart means prompts are versioned and reviewed like code, the Program stays
readable, and ActQL can type-check the rest of the SQL before a single model
call is made.

## Defining a model task

A model task is a versioned file:

```yaml
# model-tasks/churn-risk.v1.yaml
task: model-task:churn-risk.v1
model: { provider: openai, name: "<model id>" }   # optional
input:
  notes: string
  active_users: int64
  trend: string
instructions: |
  From the account notes, the number of active users and the usage trend,
  rate the churn risk as low, medium or high and explain why in one line.
  Do not assume facts that are not in the input.
output:
  level: {type: string, enum: [low, medium, high]}
  reason: string
limits:
  max_items: 5000
  max_output_tokens: 200
```

| Field | Meaning |
| --- | --- |
| `task` | The identifier a Program uses. Bump the version when the instructions or the types change; a Run records which version it used. |
| `model` | Optional. Which provider and model answer the task; without it the registry's `default_provider` is used. Providers are configured in the registry below, never in the task. The mock profile ignores it. |
| `input` | The columns the task accepts, with types. `INFER … INPUT (…)` must supply exactly these. |
| `instructions` | The prompt. It sees only the `input` fields of one row at a time. |
| `output` | The typed answer. `enum` makes a value closed; every field is required unless marked `nullable: true`. |
| `limits` | Ceilings for this task: items per call site, output tokens, and so on. The Host and the Program may lower them, never raise them. |

A model task has no tools, no retrieval and no streaming: one row in, one
typed object out. That is what makes an answer recordable and replayable.

## Registering tasks and providers

`model-tasks.json`, named by `model_tasks` in `actql.config.json`, lists the
task files and the providers they may use:

```json
{
  "version": "actql-model-tasks/0.1",
  "tasks": {
    "model-task:churn-risk.v1": "./model-tasks/churn-risk.v1.yaml",
    "model-task:draft-reply.v1": "./model-tasks/draft-reply.v1.yaml"
  },
  "providers": {
    "openai": { "type": "openai", "api_key_env": "OPENAI_API_KEY" }
  },
  "default_provider": "openai"
}
```

### OpenAI on Node

This path requires `@actql/node` and `@actql/provider-ai-sdk` from the same
[optional five-package cohort](../../release/README.md#optional-node-and-openai-provider-cohort).
Check that both packages are available at the exact selected version before
installing from npm. The historical release covers the four Node and SDK
packages. Set `ACTQL_VERSION` to the selected cohort's exact version. When
that five-package cohort is published, install its two public entries:

```sh
npm install --save-exact "@actql/node@${ACTQL_VERSION}" "@actql/provider-ai-sdk@${ACTQL_VERSION}"
```

For a local candidate, install the five original staged tarballs together in
an empty project directory.

```sh
npm install --save-exact \
  "./actql-client-wire-${ACTQL_VERSION}.tgz" \
  "./actql-sdk-${ACTQL_VERSION}.tgz" \
  "./actql-local-node-${ACTQL_VERSION}.tgz" \
  "./actql-node-${ACTQL_VERSION}.tgz" \
  "./actql-provider-ai-sdk-${ACTQL_VERSION}.tgz"
```

Start the application in the project directory with `OPENAI_API_KEY` set in
its environment. The registry contains only the reference name. The standard
Node path supports the exact name `OPENAI_API_KEY` for the project's default
`openai` provider, for structured, non-streaming Chat Completions. Set the
model selector, deadlines and ceilings in the trusted application setup.

```js
import {open} from '@actql/node';
import {createRegisteredSdkProvider} from '@actql/provider-ai-sdk';

const client = await open({installation: {
  authorization: configuredAuthorization,
  modelSdkRegistrations,
  registerModelProviders: createRegisteredSdkProvider({
    providerId: 'models/openai',
    dataHandlingContractWire,
    generation: {temperature: 0, topP: 1, maxOutputTokens: 100},
    transportTimeouts: {connectMs: 3_000, headersMs: 10_000, bodyMs: 5_000, callMs: 15_000},
    budget: {maxCalls: 1n, maxRows: 1, maxTokens: 1000n,
      maxCostUnits: 100_000n, maxDurationMs: 15_000n},
    observeEgress: observeOpenAIEgress,
  }),
}});
try {
  const run = await client.startSource(program, {format: 'aql'});
  if ((await run.wait()).status === 'succeeded') {
    console.log(await run.result('out').all());
  }
} finally {
  await client.close();
}
```

`configuredAuthorization` is the application's existing Account and signer
configuration. The trusted Host supplies `modelSdkRegistrations` with the exact
OpenAI SDK, adapter and lock images, the resolved model and endpoint, and the
credential reference. Its Provider ID must match the project registry.
`dataHandlingContractWire` is the selected request-data-handling contract.
`observeOpenAIEgress` returns the application's current
`classification`, `region`, `providerRetention` and `trainingUse` facts.
Account and egress rules apply to the exact provider and Task. The Host reads
the environment value only for an authorized fresh call to
`https://api.openai.com/v1/chat/completions`. A missing or invalid value
refuses the call before dispatch. Saved reads use the recorded result without
needing the key. Keep the key out of Program data, project files, diagnostics
and exports.

### The mock model

Under `--profile mock` no provider is called. Each task answers from the file
the configuration names for it under `mock.answers`; the churn-risk example
ships with one:

```yaml
# mock/churn-risk.v1.answers.yaml
task: model-task:churn-risk.v1
answers:
  default: { level: low, reason: "stable usage" }
  by_key:
    "001Acme":   { level: high, reason: "falling usage and a competitor evaluation" }
    "001Globex": { level: high, reason: "support tickets about pricing" }
```

This is how the Quickstart runs without keys, and how you test a Program's
logic — filters, joins, failure handling, Effects — independently of prompt
quality. The answers are looked up by the row's key, but the mock does not
establish that key: its uniqueness is proved from the sources' declared keys,
exactly as with a real provider.

## Calling it from a Program

```sql
SELECT a.id AS id, a.description AS notes, u.active_users, u.trend
FROM salesforce.accounts AS a
JOIN snowflake.usage_30d AS u ON a.id = u.account_id
|> INFER `model-task:churn-risk.v1`
     INPUT (notes, active_users, trend) AS risk
|> WHERE risk.outcome = 'ok' AND risk.value.level = 'high'
```

- `INPUT (…)` maps columns of the incoming rows to the task's input fields,
  by name. Nothing else is sent to the model.
- `AS risk` names the answer. `risk.outcome` and `risk.value` are ordinary
  columns from here on.
- Each row needs a key that identifies it. When exactly one candidate key can
  be proved (`id` here), it is used; otherwise name it with `ITEM KEY (col, …)`.

The result keeps the key columns and adds two:

| Column | Value |
| --- | --- |
| `outcome` | `ok`, or `failed:<reason>` |
| `value` | On `ok`, an object of the task's output type; on failure, `NULL` |

Filtering on `risk.outcome = 'ok'` is what lets you use `risk.value.level`
as a non-null string afterwards.

## When the model fails

The standard Node OpenAI Chat Completions profile sends at most one request per
item. A complete HTTP error reply, including 429, yields
`failed:provider_error` with a `NULL` value. A model refusal yields
`failed:refusal`. The SDK and Host do not retry either result.

The transport has separate limits for connecting, receiving headers and idle
time between body chunks. Its whole-call deadline also applies while body
chunks are arriving. If the deadline expires after a call may have reached the
provider and no complete reply was observed, the Run needs reconciliation.
Reading the same Run or its Saved Result never resends that request.

A complete reply can report input and output token counts. Zero is a reported
count. An absent count stays unknown. Usage and the receipt describe the
original observation, including when the reply cannot produce a typed answer.

A definitive row failure has `failed:` followed by a reason. Which reasons a
provider can report depends on its execution profile.

| Reason | Meaning |
| --- | --- |
| `rate_limit` | The provider profile classified the reply as throttling |
| `timeout` | The provider profile established a definitive timeout outcome |
| `provider_error` | The provider returned an error |
| `refusal` | The model declined to answer |
| `schema_invalid` | The answer did not match the output type |
| `safety_rejected` | A safety filter blocked the request or the answer |
| `truncated` | The answer was cut off by the token limit |

An answer that does not fit the output type produces `schema_invalid` and a
`NULL` value. Retry behavior is fixed by the selected execution profile.

By default every row comes back, failed ones included, so the Program decides
what to do with them — keep only `ok`, route failures to a review table, or
count them. Whether a failure fails the whole step is the Program's choice,
not the task's: the task defines instructions, types, model and retries, and
the `INFER` step says how to treat a failed row. To refuse a partial result,
add `ON FAILURE FAIL`: when any row ends unsuccessfully, the step's result is
not published as a success, no later step or
Effect sees it, and the calls already made stay recorded as evidence with
their cost:

```sql
|> INFER `model-task:churn-risk.v1`
     INPUT (notes, active_users, trend) AS risk
     ON FAILURE FAIL
```

## Limits and cost

Before the first call, ActQL counts the distinct keys it would send. If that
exceeds the task's `max_items`, the Host's ceiling or a guard in the Program,
no model is called at all and the step fails with the limit named. From the
item count, the task's token limits and the retry contract it also fixes the
maximum number of calls, bytes and tokens for the step, so the work of a Run
is finite before it starts; `actql explain` prints these bounds. A finite
amount of work is not the same as a price: what it costs depends on the
provider's terms for input and output tokens, attached content and retries,
so a budget in money is established from the task's and the Host's contracts,
not read off the row count.

## Answers are observations

A model's answer is recorded in the Run as an observation from outside,
together with the evidence of each attempt. If the Run is resumed or
recovered, the adopted answer is reused — the model is not asked again, and
the Program sees the same values. Change the task's version to get fresh
answers under a new definition.

ActQL guarantees the type of the answer and how it is handled, not that the
judgement is right. Where a wrong answer would be costly, put an Effect behind
a Checkpoint so a person sees the values before they are written.

## Next

- [Writing Programs](../authoring.md): the full `INFER` syntax, `NEAREST` for retrieval before inference.
- [Local and remote Hosts](hosts.md): routing `infer` in the account configuration.
- [Runtime limits](../reference/limits.md): default ceilings per environment.
