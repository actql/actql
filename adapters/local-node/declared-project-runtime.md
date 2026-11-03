# Declared project fixture Source and Effect boundary

## Responsibility

`installed-project-mock.mjs` installs the catalog's actual prepared Source
members against a selected fixture document. `installed-mock-row-effect.mjs`
installs its optional single writable target through the catalog's prepared
Effect member. They use generic relation admission and target projection, not
scenario-specific schemas, connector names, permissions or row values. Project
configuration selects declarations and sample data independently. Existing
Source initialization, checked Run, RowRun, Account and durable Effect Ledger
owners retain their respective authority; this composition creates no new owner.

## Inputs and outputs

Preparation consumes exact Project/Profile originals, selected connections and
the declared catalog through the existing installation inventory. The retained
bundle identifies all Source declarations, physical relation descriptors, file
bindings and zero or one writable descriptor. Source installation loads each
member with its original declaration, exported wire and prepared Environment.
Reads admit the original JSON bytes once for that read and project every
catalog physical relation with its declared resource, items/key paths, primary
identity and writable fields. Ordinary RowRun delivery accepts the selected
projection through `clientProgramRelationAcceptChargedDocument`; file listing
and keyed content delivery use `createFixtureFileSupplier` and the same original
read. Effect observation and update use the selected projection and the original
prepared Mapping, without restoring declarations or reserializing Mappings.

## Identity

Project, runtime, profile selection and connections remain exact retained
originals, checked before and after asynchronous preparation. Source reads bind
to their checked owner, original managed Run and complete stage/input/task
occurrence; keyed reads additionally bind the exact request and keyed acquisition.
Equal bytes do not replace these identities. Every sibling read in the same Run
must observe equal fixture bytes. File Resources are issued only from this
Source's bounded inventory, scoped by its physical collection, identity,
connection scope and authorization context; a filename is not identity or a
new capability. Effects bind requests to the actual binding, Mapping, target,
before image and version, plus the same Run. Nested DATA snapshots are frozen,
not mistaken for original grants.

## Ownership

The Source parent retains preparation and declaration contexts. Each managed
physical read retains its actual bytes, admitted document and every typed
projection. These aliases remain on that read, including partial projection
failure, until the original physical close and native retirement permit release.
The existing Host Run owns shared Source/Effect read records and payload severing;
weak indexes grant neither parenthood nor cleanup authority. The Effect driver
uses the existing file target and Effect resource methods. Row Effect still owns
Preview, durable row claims, recovery entries and response-before-settlement
ordering. Neither metadata holders nor issued Resource labels are installed
adapters, Ledger replacements or independent execution owners.

## Synchronization

Retain the installation inventory before the first metadata/declaration
construction and reuse its original Source material and base Environment.
Preparation retains its acquired bundle before the final currentness check.
Read grants require a current Account acquisition decision for the exact
connection/resource, a Run invocation and dispatch identity, and one use.
Read currentness and cancellation are checked around physical reads and
verification callbacks. Duplicate complete occurrences and duplicate keyed
requests refuse. Effect requests consume current read/write grants for the
catalog's declared permissions; updates use the resumed checkpoint decision,
existing durable claim and physical target serialization, never a profile label.

## Failure

Missing inventory, foreign preparation, an absent prepared member, mismatched
Mapping or physical descriptor, multiple writable targets, unauthorized reads,
changed sibling bytes and invalid typed projections refuse. A failed initial
preparation calls inventory failure on that same original material. Source
installation retains partial adapter cleanup via the existing Host failure
carrier. Effect updates compare both version and canonical before image before
replacement; a conflict does not silently re-observe or rewrite another target.
Partial document/projection construction and failed physical close remain
owned for cleanup, rather than being hidden by a new read or successful Promise.

## Cancellation

Signals are checked before and after read/verification; cancellation does not
acknowledge physical close. Each physical child must explicitly report
`pending: false`, then its original direct/keyed native read is retired.
Shared Effect reads release aliases only after the same Run's payload-sever
witness and every sibling physical-close acknowledgement. Pending close retains
the whole inventory, raw backing and projections for retry. Source close also
closes keyed children and clears its issued Resource inventory only after
successful close. Initial Host shutdown fails unconstructed inventory contexts
without claiming a metadata-only holder was successfully installed.

## Resources

The configuration reader funds strict UTF-8 decoding and native metadata
construction before allocation under the same Source reservation, as described
in `../host-node/source-declaration-continuations.md`. Runtime original reads
charge their full bytes before projection or acceptance. Generic relation bounds
include bytes, nodes, depth, rows and work. The admitted backing plus all typed
relation projections, not merely the selected relation, participate in the
existing managed Source/Run memory census and cleanup. File Resources have a
bounded inventory of 100 entries; file page and content limits remain explicit.
Effect file target limits bound original bytes, rows, nodes, depth, work and
response. These limits are not retrospective funding, GC/RSS evidence, or
permission to omit sibling projections from native memory accounting.

## Extension

New collections and sample data are expressed through the declared catalog,
physical paths, typed schemas, Mapping descriptors and fixture file. No scenario
names, fixed field pairs or connector-specific branching belong in these runtime
modules. Additional writable targets or operations require an explicit supported
contract and tests; this boundary currently selects at most one update target.
Live-provider installation and authorization are not inferred from mock success.

## Verification

`../host-node/installed-project-mock.actual.test.mjs` exercises actual managed
Source consumption and retirement. `../host-node/mock-effect-host-original.test.mjs` checks
shared Effect Plan and original Host/Journal custody. Generic target behavior
requires its own executed component evidence; these syntax declarations do not
claim that test establishes it. The declaration inventory and
fixture supplier component tests cover original construction and file transport
boundaries separately. Source-scoped syntax coverage checks declaration hashes,
exports, actual JavaScript operation inventory and these ten obligations; it is
not execution evidence. Component checks do not establish a normal-package README
pass, live SaaS acceptance, production deployment or physical RSS reclamation.
