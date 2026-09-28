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
| Salesforce | Provider, declarations, manifest contracts, standard Host discovery/read and packed installation are present. | Realistic-size live-org evidence and the standard Host Effect installation remain separate work. |
| Effect | Common compilation/apply/Ledger mechanisms exist. | The standard Host approval/restart integration is PR #29; a real Salesforce installation still needs connection to that boundary. |

## Integration evidence, checked on 2026-09-28

- [PR #27](https://github.com/actql/actql/pull/27), `db645d634`:
  Merged into main: Salesforce standard Host discovery/read, retained declarations, Checkpoint
  read handoff, acquisition stop observations, larger bounded Local input and
  packed-package coverage. All 14 required CI checks succeeded; performance
  matrix was intentionally skipped. The earlier live-org evidence used short
  values. Realistic-size input is tested locally, not yet established by that
  live-org evidence. The merge is confirmed at the baseline above.
- Open [PR #29](https://github.com/actql/actql/pull/29), `c0b982cad`:
  Values-origin, single-Unit, Result-reference Effects with whole-Set approval,
  restart and publication through the public Client. Its reference Site is not
  a real Salesforce installation. Acquisition-bearing Effect compilation is
  outside that unit. Final CI and merge are separate from local test evidence.

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
