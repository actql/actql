# Local Relation physical storage

Local Relation execution retains immutable row tables as its default storage.
Private numeric-column completion adapters can preserve typed producer output;
the broader Value-column and numeric/boolean layouts remain experiments, not
language types or public backend-selection options. The
[completion boundary](execution-completion-storage.md) separates success
ownership from physical representation.

The checked pipeline, owned ordering evidence, shared AoA fragment and logical
resource contracts determine meaning. A physical representation must not alter
row-major binding evaluation, the first evaluated failure, lazy branches, duplicate
occurrences, stable ties, Parameter/producer ownership or canonical identity.
Small result selection does not waive earlier evaluation or input validation.

The private indexed-row and sequence boundaries permit a representation to supply
cell access, construction and release without implementing another checker,
comparison law, take-completion strategy or operation scheduler. Completed output
publication remains atomic and outside experimental storage callbacks.

Shared buffers require physical lifetime accounting distinct from logical table
occurrences. Conversion must include source and destination overlap; a composed
selection must retain and charge the backing storage until its final owner is gone.
Reusing admitted input does not reuse a spent invocation budget.

The storage decision is conservative: lower construction counts alone are not a
sufficient reason to replace rows. The bounded workloads use shared row-index
algorithms already, and admission, row-major expression execution and conversion
can dominate the enclosing cost. A future representation change needs evidence of
an end-to-end benefit without semantic or cross-target regressions, rather than
an isolated transposition or allocation result. It must not create permanent dual
product engines merely to improve a selected benchmark.

Measurements and verification records belong in
[the integrated report](../../benchmarks/local-relation/REPORT.md), separate
from these architectural boundaries.
