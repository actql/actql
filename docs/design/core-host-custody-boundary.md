# Portable checked graphs and Host custody

Portable Core derives and validates semantic proposals. Host execution owns live
resource admission, currentness, attempts, retained results and cleanup. Moving
an operation between these layers must not turn numeric budgets or callbacks
into authority.

## Package direction

- `physical_strategy` owns checked DAG construction, bounded carrier expansion,
  checked task identities and validated retained-task projections. Its opaque
  graph constructors still validate the original checked Program, prepared
  owners, incoming gates and exact Effect static/Run correspondence.
- `physical_host` owns only the pure quantities projected from managed producer
  reads. Estimates are proposals, not admission or evidence of task completion.
- `physical_strategy_host` owns captured DAGs, resource-backed strategy search,
  task execution, result retention and Effect custody. It reexports the actual
  Core nominal graph types rather than reconstructing equivalent-looking proof.
- `physical_host_dispatch` owns prepared dispatch, adaptive selection and the
  installation's compute lifecycle. A ticket retains its exact dispatch Owner;
  another Run cannot consume it even when both Runs share one checked DAG.
- `physical_resources` remains a Host-private accounting and admission Owner.
  Its installed target-specific issuers are outside the portable Core closure.

Dependencies point from Host to Core. The portable closure checker explicitly
rejects the three live-custody packages, including through an otherwise neutral
intermediate package. A future implementation without syntactic FFI does not
make a live-custody Owner a portable proposal.

## Read-only graph projections

Checked DAGs and array-bearing computation descriptors remain abstract. Public
collection projections return counts, optional indexed values or read-only
iterators, never the owned arrays or nested mutable arrays. Nested indexed
projections return `None` for invalid indexes. Scalar-only descriptors may expose
read-only fields, but outside packages cannot construct or update those records.
Existing opaque prepared/occurrence references retain their original identity.

Core refuses a mismatched Effect Run with `CheckedEffectRunIssue::ForeignCandidate`.
The Host adapter maps this exactly to the existing `RunIssue::ForeignCandidate`.
Retained-task projection refusals similarly retain the existing Host
`UnsupportedGraph` outcome. This separation does not collapse other typed Host
failures or weaken their use-site checks.

## Admission and lifetime invariants

No public callback, scalar quota, permission Boolean or generic Resource trait
constructs an imported funding original. The existing private imported origin
still retains its exact Ledger back-reference, fixed capacities, sticky loss,
stop state and installed current/report/stop operations. Currentness checks,
reentry fences, partial-admission cleanup and stop/report custody remain at the
same Host operations. Native and Wasm retain their actual target-specific
installation/refusal behavior; no permissive fallback is introduced.

A reservation is not a consumed attempt. Tests that model an intervening start
must explicitly consume the reserved attempt before settlement; otherwise an
unchanged-state search refusal is correct. Neither an estimate nor a static
retained-task projection starts an attempt or authorizes publication.

## Regression obligations

The portable boundary suite compiles the actual isolated Core with the pinned
compiler: a valid read-only projection must compile, while external construction,
record update, field mutation and owned-array escape must fail for the expected
visibility reason. Resource-owner tests retain their currentness, reentry and
cleanup cases. Host integration tests cover equal checked-graph identity across
distinct Runs, foreign revisions/tickets, one-shot consumption and foreign Effect
owner refusal. These focused checks complement, not replace, full integration
and target-specific runtime acceptance.

## Fixed-input text-bound views

`lowering_relation` retains an opaque `ExpressionTextBound` only after its
existing closure, stage, producer, pipeline and typed-occurrence identity checks.
The view is a nominal single-field tuple type, not an allocated wrapper record.
Pinned compiler representation checks cover JS, Wasm and Native; it retains the
original pointer without adding owned storage. The lowered expression's private
map stores that view once; repeated access
returns the same nominal view, and another typed child cannot borrow its bound.
Read-only projections retain the original checked output, policy and optional
filter expression. They do not expose the checker site or provide constructors.

The fixed-input engine consumes these lowering-owned views instead of importing
`pipeline_check_context` directly. This is a direct dependency boundary, not a
claim that lowering has no transitive checker dependency. It neither rechecks
wire-equivalent data nor promotes a policy or numeric output to Host admission.
