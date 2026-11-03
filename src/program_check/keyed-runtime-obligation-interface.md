# Checked keyed estimates and runtime obligations

- Responsibility: SourceView resolution retains known row estimates without
  making an unknown aggregate bound an execution prohibition. Pipeline selection
  and Program checking preserve the exact producer and keyed join for runtime
  admission. Static type, operation, Source authority and policy checks remain.
- Inputs and outputs: Original keyed facts and optional genuine TargetRows enter
  KeyedRowBounds. LookupRequirement retains the original join, optional computed
  counts and envelope classification. KeyedExecution retains that requirement
  and optional original TargetMembership on the same Unit operation source.
- Identity: Bounds, joins, memberships, producer rows, checked programs and
  requests retain their physical original correspondence. Audit rejects foreign
  equal-looking objects. Only real static membership enters signed input proof;
  runtime obligations cannot be substituted for a static signature.
- Ownership: Existing Source producer contexts and checked Program objects own
  these records. No Ledger, resource owner, read capability, captured Source or
  completion witness is created by estimate selection.
- Synchronization: The existing bounded check traversal and selection cache are
  used. It performs no Source execution, count scan, second check or compilation.
  Runtime consumers must independently maintain their original liveness fences.
- Failure: Invalid explicit membership, foreign originals, invalid policies and
  bounded check-work exhaustion still fail. Estimate-product overflow leaves
  the aggregate estimate unavailable while retaining genuine producer evidence.
  Actual allocation and cumulative send arithmetic must still reject overflow.
- Cancellation: These immutable check records neither cancel nor settle runtime
  work. A runtime obligation cannot revive a closed Run or refund spent work.
- Resources: Real zero remains a zero estimate; unknown is not encoded as zero
  or unlimited capacity. Known estimates, even above a conservative envelope,
  remain available for planning. Each runtime consumer must admit actual work
  under the existing resource policy before allocation or provider access.
- Extension: The runtime obligation is distinct from the existing static lookup
  barrier and its canonical proof identity. Missing static evidence is allowed
  only in that explicit branch, without relaxing type or authority validity.
- Verification: Focused row selection, estimate arithmetic, automatic keyed
  capacity, source execution, policy, import and foreign-program tests cover
  representation and identity compatibility. They do not establish runtime
  empty-input suppression, provider admission, dynamic allocation or cleanup.
