# Current Session JS package configuration review

Reviewed source: `58710094a4698c16587c6cfffac25f050d93c92d`.
Toolchain: the unchanged pinned Moon revision `94521db`, compiler
`0.10.12+1634b282e`. This review extends only the finite JS configuration
allowlist. It does not close the execution environment or authorize reuse.

The source delta from the previous reviewed revision is:

| Package | Added or changed inputs | JS configuration boundary |
| --- | --- | --- |
| `native_values_integration` | New package, literal runtime and whitebox imports | The compiler/link driver, stub compiler and SSL flags are under `link.native` only. JS does not invoke them. |
| `publication_store` | Checkpoint/signature imports; Effect source/capture custody files | Every new target predicate is `native` or `not native`; C stub settings remain unchanged. |
| `remote_client` | Checkpoint import and Native checkpoint test | Literal import is followed; the new test is Native-only. |
| `remote_journal` | Effect/publication/request-scope/SHA/checkpoint imports; ledger and checkpoint files | All new file predicates are literal Native or not-Native selections; the inspection C stub setting is unchanged. |
| `remote_transfer_client` | Reconciliation Native test | Native-only predicate; retry-wait C stub and other selections unchanged. |
| `remote_transfer_journal` | Destination admission Native test | Native-only predicate; SHA dependency remains literal and inventoried. |
| `signature` | Core base64/JSON imports and Native private-evidence test | External core imports are inventoried; the new test is Native-only. |
| `query_integration` | Native values fixture extraction; Local table, Effect/request-scope and core debug imports | Existing Native linker settings unchanged; every new dependency is literal and followed, including whitebox imports. |

Imports are followed even when only whitebox or Native code uses them. Package
members, C files, generated interfaces, tests, file modes and directory
membership remain bound. New checkpoint, Effect and values integration
packages are not silently excluded. Native link drivers are not JS execution
inputs because the pinned JS target does not execute the `link.native` path;
this is not a claim about Native linker closure.

Changed bytes, unknown options/imports, a different target or a different
compiler pin still require fresh broad-source execution with an unresolved
reason. The expanded real-Git fixture checks literal dependency closure,
package membership and staged bytes/modes. Each changed configuration has a
negative test proving that unreviewed bytes preserve full-source fallback.

The separate finite experiment contract remains unchanged. If its original
experiment bytes differ from current source, its runtime is open and reuse is
refused. Positive mixed-archive tests install the exact independently pinned
experiment only in their own temporary Git repository; they neither relabel
current source nor rewrite original receipts.
