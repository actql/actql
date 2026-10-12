# F04: typed Vectors NEAREST roles

This is the existing F04 completion unit, not a new language profile. Each side
retains an optional complete KEY/VECTOR pair in the AST. Relation inputs require
an explicit pair. Typed Vectors retain their admitted identity and component
roles; an explicit pair must restate those roles exactly and in order.

The source dispatcher checks the real prefix Carrier and reuses the installed
input binding owner. Machine NEAREST still receives candidates as its current
input and queries in its `queries` argument. Typed Vectors are passed directly;
the existing `vectors` bridge supplies ordinary rows only for KEEP. No identity,
Source, checker, evaluator, or runtime owner is replaced.

The continuation installs a new output scope and retains lexical peer inputs.
It does not restore input aliases removed by NEAREST. Ordered composite Vectors
identities use the common positional object members (`0`, `1`, ...) when creating
the named output key objects. Composite Relation conversion remains unsupported
by the current scalar-id `to_vectors` entry and is not silently approximated.

## Evidence and remaining acceptance

- Baseline `44e16b9eb23193f62e18d366d20d265d5b667153`: `run-xNs4Ix`
  discovered two parser cases; omitted roles failed, malformed pair refusal passed.
- Working source: `run-q7Zfn7`, JS 14/14, existing Relation and optional-role AST.
- Initial typed bridge: `run-hFhATL`, 0/1, common `InvalidBody`; putting the bridge
  and SELECT in separate existing Program steps corrected that boundary.
- Working source: `run-OE43O8`, 1/1, four independently selected operand kinds.
- Working source: `run-kONCqW`, 16/16, exact restatement, fresh output scope,
  normalized input and shared original producer; `run-pnrOAP`, 17/17, adds the
  ordered composite Carrier/lowering control. These are checker/lowering tests,
  not runtime values or public E2E evidence.
- `run-qFzsMM`: changed-file pinned formatting; `run-F3lH4B`: generated affected
  Query interfaces. Both completed with exit 0.

Original raw receipts and output remain under this worktree's `_build`; failure
records are not replaced by later success. Each working-source receipt includes
its selected command. Fixed-HEAD checks will be recorded separately.

Public Source/Host Local/HTTPS acceptance remains unexecuted. Empty inputs, ties,
NULL/type failures, result rows/full schemas, resend/attach and cleanup still need
the original finite public matrix. F01–03 are separately integrated and retain
their pending public acceptance. This unit adds no Heavy reservation or global
Core/CI gate and does not complete F04/P2 by parser or checker success alone.
