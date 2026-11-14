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
  Hosts are rejected when configured. Environment defaults are not read unless
  `environment: true` explicitly selects the standalone mechanism. Install the
  package's pinned dependencies; a normal SDK/Local install
  does not need them.
- `traces`, `metrics` and `logs` each accept an explicit endpoint or `false`.
  The generic `endpoint` enables traces only and appends `/v1/traces`.
  A specific endpoint is used exactly. Nothing implicitly sends to localhost.
- Trace sampling is standard parent-based sampling with trace-ID ratio for roots
  (`sampleRate`, default 1). A valid parent's sampled flag is preserved, including
  when the root ratio is zero. Explicit `traces: false` disables all traces.
  It is not error-based sampling. Metrics/logs and Evidence
  are independent of trace sampling. Tail sampling is a Collector concern.
- Default disclosure is metadata-only. Names/bodies are fixed operation/event
  labels. Default managed Resource is `service.name=actql.node-host`. No Program text,
  rows, Result names, error text, credentials, arbitrary Resource or baggage
  enters a record. Run/CID correlation is opt-out via `correlation: false`;
  this also removes caller context and recovery links. IDs are not metric labels.
- Metrics use only operation/outcome labels and omit Exemplars. Logs and traces
  may include Owner-issued Run identity, task/attempt/slot ordinals and revision.
  A CID is not access permission. This first profile is single-scope Node, not
  hosted multi-tenant export.
- Original Model entry/return facts are discrete logs correlated by attempt CID.
  Their diagnostic delivery timestamps do not measure the physical invocation;
  they cannot create duration spans. A replayed Saved response emits no new
  physical invocation fact. Measured Source acquisition intervals remain spans.
- `include`/`exclude` select fixed operation categories; exclusion wins. Empty
  selection disables observation. Missing all signals is complete disable and
  does not allocate the optional journal tables. Configuration is immutable.
- The adopted `operations: {include, exclude}` form selects the same categories;
  do not combine it with flat `include`/`exclude`. `measurements: {include,
  exclude}` selects registered groups independently of trace sampling. Only
  `duration` and fixed original managed-Run `resources` log attributes are
  available from the Host hooks. Resource counters are exact decimal strings,
  not heap, Store or physical cleanup measurements; they are not metric labels.
  Other selected groups remain explicitly unavailable, never invented as zero. `cost` requires
  a pricing source and is rejected in this profile. Excluding duration suppresses
  its metric instruments; actual span interval timestamps remain truthful.
- `correlation: {include, exclude}` selects `run`, `task`, `attempt` and
  `external_trace` independently. `attributes: {exclude}` removes registered
  optional attributes before queueing and metrics recording. Excluding required
  envelope attributes suppresses the record and reports loss. `events.level`
  accepts `lifecycle` and `diagnostic`; both retain only the same fixed Owner
  lifecycle facts, with bounded local loss diagnostics, never raw error detail.
- Resource customization is explicit and limited to `service.name`,
  `service.version` and `deployment.environment.name`, each at most 128 UTF-8
  bytes. These are disclosed installation metadata, not per-Run input. Unknown
  keys are rejected without reading their values. Attribute exclusions also
  remove these fields before private SDK Resource construction.
- `configuration()` inspects effective signals, sampler, versions and finite
  caps without URLs/secrets or a connectivity probe. `status()` reports queue,
  sender counters and explicit loss reasons. No raw errors are retained there.

### Explicit standard environment mechanism

```js
const telemetry = createNodeHostObservability({environment: true});
```

This reads the standard `OTEL_EXPORTER_OTLP_ENDPOINT`, signal-specific
`OTEL_EXPORTER_OTLP_{TRACES,METRICS,LOGS}_ENDPOINT`, protocol, headers and timeout,
`OTEL_{TRACES,METRICS,LOGS}_EXPORTER` (`otlp`/`none`), `OTEL_SDK_DISABLED`,
`OTEL_TRACES_SAMPLER`/`OTEL_TRACES_SAMPLER_ARG`, `OTEL_SERVICE_NAME` and
`OTEL_RESOURCE_ATTRIBUTES`. Specific endpoints are used exactly; generic paths
are constructed once. A generic endpoint alone enables only traces. Explicit
metrics/logs `otlp` uses their specific endpoint or the generic base; without
either destination the signal stays disabled with a bounded diagnostic.
Direct signal options take precedence; `none` and complete disable do not
create a localhost fallback. Empty values are unset. Invalid numeric and
unsupported enum values produce fixed diagnostic codes, not echoed values.
The supported sampler is `parentbased_traceidratio`; unsupported sampler
selections fall back to that reported default. Export timeouts cannot exceed
the managed 500 ms ceiling. SDK limit controls cannot widen the Host caps.

Signal headers override generic headers. Code `headers` provide the same direct
configuration equivalent. Headers are at most 16 entries/4,096 total bytes;
framing and context/baggage headers are forbidden. Credentials go only to the
explicit collector, never to observation records, inspection or diagnostics.
Only the three admitted Resource keys are retained, and `OTEL_SERVICE_NAME`
wins over the Resource attribute's name; code Resource fields win over both.
`OTEL_PROPAGATORS=tracecontext` is supported; `none` narrows external linkage.
Baggage and declarative configuration files are explicitly unsupported, not
silently ignored. Application providers cannot select this environment overlay.

This is an API configuration mechanism, not a new CLI or YAML parser. The
adapter neither installs a global propagator nor modifies unrelated libraries.

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
