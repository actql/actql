# Private storage of original Model state

`original_model_state` is a dedicated role of the existing encrypted Local
continuation evidence Store. It is not `captured_input`, a Source capture or a
published Result. The trusted Host connects the existing original resource
Writer to this role; storage does not manufacture a resource state from JSON.

The existing storage binding is closed by owner ID, original request/Run
Definition CID, exact role, semantic byte CID, derived physical holding,
namespace and installation key generation. `hold` records that custody before
committing ciphertext, verifies the exact bytes from the physical Store and
returns their semantic CID only afterwards. A lost reply does not justify
re-running the Writer or Model. The same original holding can be reopened and
verified; missing evidence remains unknown.

Read rechecks request/key/role/holding/state, physical size and AEAD/content
identity. The saved original bytes are not passed through a configuration
canonicalizer. Neither a CID nor successfully read bytes admit a current
Ledger, restore a token, reset a budget or authorize Model dispatch.

The holding preimage remains `actql-local-continuation-holding/0.1` with the
existing fields `version`, `prepare_attempt_id`, `name` and `semantic_cid`.
The new exact name distinguishes its custody; old names, preimages and CIDs
are unchanged. Its existing encryption AAD binds that name and semantic CID.
There is no self CID in the stored original bytes. This role addition does
not add an owned Model artifact/schema or change the original data codec.

The resource Owner separately issues and admits the closed original
read-snapshot/checked-plan binding and, later, the current resource cut. Those
contracts and their schema/pin/vector changes must be registered together.
This storage primitive alone does not authenticate those semantics or link
a preparation basis to a later Slot/Entry/Run revision. Host startup, the
original Writer caller's actual Store ACK and current restoration remain
distinct integration steps, not capabilities implied by role registration.

## Retirement

Generic terminal status and abandoned preparation do not release this role.
Retained Results, Unknown calls, reconciliation and CleanupPending may still
need the original state. Missing release observations, including after restart,
keep custody. The current storage primitive deliberately excludes this role
from automatic terminal retirement; no caller Boolean or arbitrary callback
can make it releasable here.

The later connection must use the same original Owner's issued release facts:
read/Writer settlement, whole-scope finish, no unresolved calls and no remaining
Result need. A failed deletion retains the original Store cleanup handle and
durable pending record. Holding encrypted bytes does not transfer ownership
of a retained Model token. The exact release issuer is not connected by this
role-only change, so whole Model state reclamation is not established.

Object byte limits do not bound retention metadata or revision discovery.
The installation must fund those acquisitions and all Writer/string/UTF-8/
Store/AEAD/read/ACK overlaps before public use. This role does not introduce a
numeric profile, fallback ceiling, resource pool or separate Owner.
