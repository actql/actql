# Current implementation status

Snapshot: 2026-09-28. Merged implementation baseline:
`d4d64d1cdfc810b8466e0ed66b98b044f33589e3`.
This is an implementation map, not a new acceptance run or a language specification.

| Area | Merged behavior | Remaining boundary |
| --- | --- | --- |
| Standard Node Client | Embedded Local, submit, durable request lookup, attach, Run observation and Named Result reads; HTTP/in-process submit classification and operation-specific response bounds. | Installed profiles constrain accepted Programs. Embedded Local-owned Hybrid is unavailable. |
| Input and Checkpoints | Explicit DuckDB installation, acquired-input evidence, read approval and restart, target binding and refusal on retargeting. | Salesforce installation and approval handoff also landed in #27. Arbitrary multi-source acquisition remains outside this profile. |
| Runtime ownership | One installed owner for Local preparation/compilation; dispatch cleanup responsibility and terminal observations; bounded authorization/diagnostic lifetimes. | These properties do not establish every connector or Effect installation. |
| Local execution | Bounded family routes and retained Relation chains have landed, including Append/Set/Cross Join followed by filter/derive/select; further retained Relation coverage is recorded in the Local evidence. | Numeric retained reductions, remaining Carrier obligations, nonlinear shapes and native in-flight drain must be tracked by their specific evidence; route counts are not complete performance proof. |
| Salesforce | Provider, declarations, manifest contracts, standard Host discovery/read, packed installation and the installed Effect (Result-referencing create, update, upsert) are present. | Realistic-size live-org read evidence remains separate. Live Effect evidence covers one Resource through Embedded Local; multi-Resource Sets are mock evidence. A non-2xx single-record reply stays unknown until a typed-failure contract exists. |
| Effect | Values-origin, single-Unit, Result-referencing Effects install on the standard Host (#29, #35): whole-Set approval, restart, per-tuple current checks, publication, from Remote HTTP, Embedded Local and the packed `connect()`. | Effects with external acquisition, a source and an Effect installed together, deferred target check reads and Cloud/Hybrid installation are outside this unit. |

## Integration evidence, checked on 2026-09-28

- [PR #27](https://github.com/actql/actql/pull/27), `db645d634`:
  Merged into main: Salesforce standard Host discovery/read, retained declarations, Checkpoint
  read handoff, acquisition stop observations, larger bounded Local input and
  packed-package coverage. All 14 required CI checks succeeded; performance
  matrix was intentionally skipped. The earlier live-org evidence used short
  values. Realistic-size input is tested locally, not yet established by that
  live-org evidence. The merge is confirmed at the baseline above.
- [PR #29](https://github.com/actql/actql/pull/29) and
  [PR #35](https://github.com/actql/actql/pull/35) (`74d24e272`), merged:
  the connector-independent installed Effect on Remote HTTP, Embedded Local and
  the packed `connect()`, with the Salesforce Effect factory reviewed in draft
  #32. Multi-Resource Sets recheck every tuple; a definitive pre-send refusal
  fails the Run and retires its capture; uncertain sends keep reconciliation.
- [PR #36](https://github.com/actql/actql/pull/36): mock-org evidence on the
  public paths for two-Resource Sets in both member orders (4 writes and the
  Named Result; refusal of the later Resource writes nothing, fails the Run and
  retires the capture), a lost reply kept unknown without resend, and the
  packed Local Host writing a two-Resource Set after approval and restart.
- Live Dev org, 2026-09-28, through Embedded Local on the dedicated test
  object: two rows created by the check, held for approval with no write,
  approved and resumed in restarted Hosts, each row updated once, the Named
  Result published, no write on a further restart, and the created rows
  deleted. One Resource only; multi-Resource Sets are not exercised live.

## Reading older reviews

The [Local gaps review](2026-09-19-sga-veca-tea-local-gaps.md) contains historical
failures followed by later closure sections. Its initial strict-gate status is
not the current status. The [managed completion report](2026-09-20-managed-completion-unification-result.md)
likewise records a historical branch; the shared output boundary has since
been integrated. Preserve recorded test SHAs when updating conclusions.

Update this page and affected package READMEs when an integration is merged.
Record public entry, packaged availability, tested Program shape, recovery
coverage and live-versus-local evidence separately. A kernel, wire operation or
test-only factory alone is not evidence of an installed public feature.
