///|
pub(all) enum RuntimeFragmentFailureStage {
  Material
  Candidate
  Admission
  Runtime
}

///|
pub fn runtime_fragment_failure_stage(
  issue : RuntimeFragmentIssue,
) -> RuntimeFragmentFailureStage {
  match issue {
    Material(_) => Material
    Candidate(_) => Candidate
    Admission(_) => Admission
    Runtime(_) => Runtime
  }
}

///|
/// Convenience summary only. Input indexes and step indexes remain distinct;
/// callers can also match the full typed error tree without losing the cause.
pub(all) enum SequenceFailureKind {
  InvalidLimits
  InputOwnership
  InputSet
  InputEvidencePending(Int)
  InputLimit
  InputKey(Int)
  Wiring
  Capture(Int)
  Rows(Int)
  Store
  OrderedContext(Int)
  FragmentContext(Int)
  MissingFragmentContext(Int)
  MixedExecutionConfiguration
  UnsupportedRowComparison(Int)
}

///|
pub fn sequence_failure_kind(issue : SequenceRunIssue) -> SequenceFailureKind {
  match issue {
    InvalidLimits => InvalidLimits
    InputOwnership => InputOwnership
    InputSet => InputSet
    InputExecutionEvidencePending(i) => InputEvidencePending(i)
    InputLimit => InputLimit
    InputKey(i, _) => InputKey(i)
    Wiring(_) => Wiring
    Capture(i, _) => Capture(i)
    Rows(i, _) => Rows(i)
    Store(_) => Store
    OrderedContext(i, _) => OrderedContext(i)
    FragmentContext(i, _) => FragmentContext(i)
    MissingFragmentContext(i) => MissingFragmentContext(i)
    MixedExecutionConfiguration => MixedExecutionConfiguration
    UnsupportedRowComparison(i, _) => UnsupportedRowComparison(i)
  }
}
