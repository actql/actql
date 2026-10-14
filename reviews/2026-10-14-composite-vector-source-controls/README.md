# Existing F04 composite identity Source controls

These controls use the adopted ordered Vectors identity `[b, a]`: Number `b`
followed by String `a`, as in `nearest_composite_roles_wbtest.mbt`. Two rows
repeat `b=1` but have different `a` and orthogonal two-dimensional vectors.
A scalar substitution loses uniqueness; swapping tuple slots changes types.
Original values, names and tuple order are independently fixed.

The public source explicitly authors `pool_vectors(by: [b, a], method: 'mean',
vector: embedding)` for both inputs. The declared composite Source key must be
validated by the existing bounded input owner. Each group is then a singleton;
the prescribed mean law returns that original vector exactly. `pool-vectors.typed-output`
uses the ordered `by` fields as the output Vectors identity (`options.by.copy()`
in `vector_typing/pool.mbt`). This is an explicit pooling operation, not a hidden
rewrite of Relation NEAREST or a new `to_vectors.id` array contract.

Relation pooling retains the already adopted member-key completion and its
validation/work obligations. Its reserved internal member ID is separate from
the output group tuple. No scalar encoding is introduced by this fixture or
used to replace the public Vectors identity. The original rejected array-ID
control and Direct Relation composite-KEY restriction remain unchanged.

Five normal controls comprise one independently authored JSON Program and
SQL/AQL-text explicit/implicit role pairs. The JSON acquires both Sources through
the existing owned Filter/Select boundary, imports their Relation Results, then
authors the same pooling and nearest operations. SQL uses a final SELECT query
entry. The two negative texts restate `[a, b]` instead of `[b, a]`. Expected
values and full ordered schema are written from the tuple/numeric laws, never
from compiler or runtime output. Two Source reads per normal case and zero per
static refusal are requirements, not observations.

The test-only supplier uses the existing public RowSource installation helpers
and charge/consume/admission/cleanup Owners. JSON pages are transport; they are
not a cast from ARRAY to Vector. The source schema declares non-null `vector(2)`
and both non-null key fields. Facts assert the real complete composite key, not
a fabricated key inferred by the frontend. Existing supplier limits remain
maxPages 1, maxPageBytes 4096, maxPageRows 3, maxCaptureRows 3.

Node-only preparation uses the existing nonHeavy60/TERM5 guard and child30
nonzero wrapper (`prepared-checks.mjs <clean-source>`). These checks cover fixture
bytes, independent CIDs, required rows/schema/operations, cancellation and original
page refusal propagation. Mock declaration projections do not admit a Catalog.

Not executed: parser/lowerer, common checker/planner, the installed supplier or
Host, normal four-package producer, Local/HTTPS matrix, same-Run/restart/cleanup,
Moon/Native, real Provider, Hosted CI or formal publication. New public E2E: 0.
Public worker/delivery integration is still pending; this is the finite existing
F04 control/supplier boundary, not complete F04 or P2 acceptance. Calendar and
Direct Relation composite-ID support are separate current boundaries.
