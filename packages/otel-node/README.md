# Node Host OpenTelemetry adapter

This optional package projects confirmed ActQL Owner facts from the installed
Node Host. It supports public Embedded Local and HTTPS. It does not own Run
state, authorize calls, capture evaluation Evidence, or replace an application's
OpenTelemetry providers.

```js
import {createNodeHostObservability} from '@actql/otel-node';
import {connect} from '@actql/local-node';

const telemetry = createNodeHostObservability({
  endpoint: 'https://collector.example.com', // Traces only.
  logs: {endpoint: 'https://collector.example.com/v1/logs'},
});
const client = await connect({
  mode: 'local', owner: 'local', durability: 'durable',
  installation: {
    directory: './actql-state',
    observation: telemetry.connection,
    // Supply the ordinary installed Host authorization/provider configuration.
  },
});
try {
  // Run operations under the application's existing active OTel context.
} finally {
  await client.close();
  await telemetry.close();
}
```

For HTTPS, pass `observation: telemetry.connection` to
`openInstalledRemoteHttpHost` from `@actql/local-node/http-host`. The application
still owns its TLS listener and authentication. On the caller side, pass
`traceContext: () => trace.getSpanContext(context.active())` to `@actql/sdk`
`connect`. Only a syntax-checked W3C `traceparent` is propagated. It is not
authorization. Baggage and tracestate are neither propagated nor persisted.

## Configuration and disclosure

- The supported managed transport is OTLP/HTTP protobuf. Other transports and
  Hosts are rejected when configured. No environment endpoint/resource defaults
  are read. Install the package's pinned dependencies; a normal SDK/Local install
  does not need them.
- `traces`, `metrics` and `logs` each accept an explicit endpoint or `false`.
  The generic `endpoint` enables traces only and appends `/v1/traces`.
  A specific endpoint is used exactly. Nothing implicitly sends to localhost.
- Trace sampling is the standard trace-ID ratio sampler (`sampleRate`, default
  1). It is not error-based or parent-based sampling. Metrics/logs and Evidence
  are independent of trace sampling. Tail sampling is a Collector concern.
- Default disclosure is metadata-only. Names/bodies are fixed operation/event
  labels. Managed Resource is fixed `service.name=actql.node-host`. No Program text,
  rows, Result names, error text, credentials, arbitrary Resource or baggage
  enters a record. Run/CID correlation is opt-out via `correlation: false`;
  this also removes caller context and recovery links. IDs are not metric labels.
- Metrics use only operation/outcome labels and omit Exemplars. Logs and traces
  may include Owner-issued Run identity, task/attempt/slot ordinals and revision.
  A CID is not access permission. This first profile is single-scope Node, not
  hosted multi-tenant export.
- `include`/`exclude` select fixed operation categories; exclusion wins. Empty
  selection disables observation. Missing all signals is complete disable and
  does not allocate the optional journal tables. Configuration is immutable.
- `configuration()` inspects effective signals, sampler, versions and finite
  caps without URLs/secrets or a connectivity probe. `status()` reports queue,
  sender counters and explicit loss reasons. No raw errors are retained there.

SDK pins: API 1.9.1; trace/metrics/resources 2.12.0; logs/OTLP transformer
0.223.0; semantic-conventions package and schema 1.43.0. The package lock fixes
all transitive inputs. Semantic Run/Program contracts remain unchanged.

## Finite limits and failure isolation

| Boundary | Default maximum |
| --- | --- |
| Projected record, including reserved correlation space | 4,096 bytes |
| Host queue | 256 records / 1,048,576 bytes |
| Per ingress request / segment | 128 / 512 records (stricter wins) |
| Concurrent ingress segments | 64 |
| Per Run, across restart | 2,048 records / 1,048,576 bytes |
| Optional custody in one Host journal | 1,024 Run rows; no eviction/reset |
| Projection shutdown wait | 1,000 ms |
| Each signal payload | 65,536 bytes |
| Each signal's rolling process-local window | 256 sends / 262,144 bytes per 60 s |
| Each signal export timeout / response | 500 ms / 4,096 bytes |
| SDK metric cardinality | 192 combinations per instrument |

These are ceilings, not execution resource budgets or billing evidence. Limits
may only be narrowed (`projectionLimits` and transport `limits`). Each Host
connection has one sequential delivery; each enabled sender has at most one
physical request. The sender retains capacity through physical close, including
timeout/error. It never retries. Projection overflow drops newest records;
shutdown discards unsent records at the deadline and reports loss. A pending
application callback retains its slot; timeouts do not prove physical settlement.

Run consumption is conservatively charged before queue insertion, including
records subsequently dropped. Optional tables in the existing request journal
bind the original request/Run, observation scope and effective configuration
digest. Saved caller context becomes a recovery **link**, never a span reopened
through approval waits. Changed config, missing/corrupt custody or unknown
consumption stops additional Run observations and reports loss; it never resets
a Run allowance or changes execution. Observation writes are separate from
semantic commits. Outbound window caps are process-local; the Run cap is durable.
This is not a distributed telemetry quota service.

An alternative application-owned `tracerProvider`, `meterProvider` or
`loggerProvider` is mutually exclusive with managed destinations. Callbacks run
on a later event-loop turn, outside the semantic boundary that confirmed a fact.
The adapter never registers, replaces, flushes or shuts down these providers.
ActQL bounds its own contribution, **not arbitrary synchronous processor time or
downstream buffers**. Close Client/Host first, then close this adapter. Closing
the adapter disables its delivery; it does not cancel a Run or revoke authority.
Application providers may add their own Resource, attributes or exemplars.
Those additions are outside the managed metadata-only payload guarantee.

See [the Owner mapping](../../docs/design/node-host-observability.md) for fact
sources, support limitations and evaluation/measurement separation.
