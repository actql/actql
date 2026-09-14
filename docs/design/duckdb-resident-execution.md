# Run-owned DuckDB residency

This design covers the local serial resident fixed-input realization and its
standard Node Host boundary. Existing fresh-DB execution remains a distinct
realization. No semantic, acquisition,
wire, or content-identity rule changes with the selected physical realization.

## Scope and authority

A resident environment belongs to one captured DAG execution. It is not a
process-wide cache and is never found by content CID alone. Its table records
must bind the exact fixed producer, output target, stored column representation,
environment generation and live ownership. Each receiver uses its own checked
projection and binding, and still performs its required guards and demand
measurement. Residency is neither receiving admission nor budget credit.

The initial shape remains X to A to C, and X to B, using filter/select. One
import of X can serve A and B; a retained A table can serve C. Host validation
and retained Host results remain mandatory. A DB copy is additional storage,
not a replacement for the independently completed Host result.

## Planning versus provision

Pure finite candidate comparison can describe an existing environment or a new
environment's provider/profile and unresolved binding. A proposed environment
does not supply a live handle, and a future table does not supply an input CID
or execution evidence. Preparation, import, computation, output transfer,
retention and cleanup belong to the whole-plan comparison. Shared work is
counted once only when its resource and allocation are actually shared.

The Host authorizes and reserves before provision starts. The local provider
creates a source-isolated DB and returns its actual profile and live binding;
dependent dispatch checks these against the chosen realization. Provision is
real work: once sent, its cost and cleanup responsibility cannot be erased by
reselection. This boundary does not require Cloud provisioning, a universal
provider SPI, or a second planner.

The planner selects the realization together with its resource profile; an
Execution Site Provider supplies the environment, while the Host owns
authorization, reservations and lifetime. A larger profile is not automatically
compatible: runtime, supported types and laws, input representation and access
conditions must also match. Existing-only policy excludes new provision rather
than silently authorizing it. Candidate enumeration performs neither I/O nor
capacity reservation.

The standard Host validates and freezes all transport settings before reserving
an environment. Rejected settings consume no provision attempt or reservation.
Cleanup distinguishes a request never sent to the provider from started work
whose result is unknown; absence of a returned handle is not proof of cleanup.

Outstanding cleanup of an already allocated environment contributes equally to
every remaining candidate, including all-Local placement. It persists while
cleanup is pending and disappears only after settlement. A proposed new
environment adds its own preparation and cleanup; an existing one does not
repeat preparation. An unknown cleanup estimate remains unknown.

An estimate, a Host reservation, a provider-confirmed allocation and a usable
binding are distinct states. Provision failure, a mismatched returned profile
or an uncertain response must not permit dependent Compute dispatch. They leave
the incurred cost and outstanding cleanup responsibility intact. A completed
dispatch is not rewritten to target a newly returned environment; dependent
dispatch is sealed only after its concrete binding has been checked.

Closing a provision intent before it becomes usable stops the DAG, even after
its reservation is settled. It is not treated as loss of a reusable DB copy.
This prevents a failed creation or profile confirmation from reopening the same
work through another candidate without an explicit recovery contract.

This increment exercises these boundaries with run-owned local DuckDB storage.
It does not establish a general provisioning SPI, Cloud deployment support or
conformance for every existing-site/new-site combination. Environment supply
remains separate from resident table ownership so that another supply mechanism
need not change canonical meaning or completed-input contracts.

## Resource accounting

The shared DB's configured execution-memory allowance is reserved once, from
before creation until confirmed cleanup, including idle intervals. It is not
a hard whole-process RSS limit. Resident table allowances are bounded
suballocations within that DB allowance; they do not charge the same DB memory
again as additional physical allocations. Host result copies and task-specific
transport/receiver scratch remain separate real capacity requirements.

Table retirement prevents new readers but does not immediately release its
capacity. Release requires its last reader to have stopped and native removal
to be confirmed. Cancellation is not that confirmation. Shared DB close forbids
new tasks while preserving outstanding allocation and cleanup responsibility.
Already consumed transport bytes and planning work are never refunded.

Tables are retained through their last planned use. There is no automatic LRU
or pressure eviction. Plans that cannot reserve the required capacity are
infeasible. Reselection may retire tables that are no longer needed, without
discarding in-flight borrowers or unconfirmed cleanup obligations.

The most recent unstarted table preparation can be cancelled atomically: its
table slot, suballocation and unused name are reclaimed, but planning work is
not refunded. The standard Host uses this operation if import preflight or
transfer reservation fails. Once transfer admission succeeds, cancellation of
preparation is forbidden; import failure stops new work and requires confirmed
cleanup. Exact handle checks reject cancelled preparations even if a name is
later reused.

## Transactions and completion

Each serial task owns its transaction and connection; the environment owns the
DB. Tables intended to survive connections must use DB-scoped owned storage,
not connection-local TEMP tables. Only adapter-generated operations access
these tables. Failed task transactions must not roll back previously committed
tables. Task cleanup acknowledges task resources, not environment destruction.

Resident task preparation binds an opaque ordered input set to the exact
run, task, environment and compiled Compute. Each input port is checked against
its own completed producer and receiver mapping; a self join may borrow one
physical table twice without importing a second copy. Receiver views use the
compiled port-specific names. A failure while preparing a later port returns
all earlier borrowers. Callers may cancel only an unclaimed set; task admission
claims the whole set once, and confirmed native settlement returns all its
borrowers. Individual read handles are not exposed by that task-level API.
Neither a close request nor an unconfirmed cleanup releases those borrowers.

A resident realization succeeds only after Host validation, exact retained
table correspondence, native transaction completion, and both required holding
obligations have succeeded. Failure to establish the DB result is not silently
converted into success of a different realization. Any provisional table left
after a later failure remains an owned cleanup obligation, not reusable data.

After successful completion, loss of the DB copy alone leaves the independent
Host result valid. An unstarted dependent task can, within existing search
limits, compare Local execution or reimport of that same live fixed input.
Started tasks are not retried or migrated. Session loss and task-local failure
are distinct; neither permits a failed Program's partial-success publication.

## Representation and verification

The supported single-table filter/select path preserves relative row order and
duplicates; it does not create a logical total-order witness. Generation and
checked column mappings must survive residency. No string SQL rewriting or
same-name schema guess substitutes for adapter compilation of those mappings.

Fixed equikey inner joins and group/count also use this boundary. Join input
ports receive separate checked views, including when both reference the same
table. The adapter's explicit join order and group order are unchanged by reuse.
Host value admission, join preflight, output limits, demand/measurement and
independent Host output holding remain required; keeping a DB copy does not
waive them. The shared driver imports each missing producer table once, while
charging task work and each result receipt separately.

Acceptance includes real import-count and transport reduction, equivalence to
Local and fresh DB execution, changed projections, multiple chunks and duplicate
rows, foreign/expired bindings, capacity boundaries, task rollback, environment
loss, pending cleanup, and completed-result independence. Wall-clock speedup is
not an acceptance requirement. Full-scan acquisition transfer, process-local
capture and the previously accepted performance regression remain limitations.
