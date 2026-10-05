///|
priv enum BoundedSequenceComparisonKind {
  IdentityComparison
  PartitionComparison
  OrderedComparison
} derive(Eq)

///|
/// Pair and purpose remain fixed while the shared value cursor is pending.
/// The original input owner retains every borrowed cell until kernel stop.
fn begin_bounded_sequence_comparison(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
  kind : BoundedSequenceComparisonKind,
) -> Bool {
  if state.compare_left == -1 {
    state.compare_left = left
    state.compare_right = right
    state.compare_kind = Some(kind)
    state.compare_column = 0
    true
  } else {
    state.compare_left == left &&
    state.compare_right == right &&
    state.compare_kind == Some(kind)
  }
}

///|
fn clear_bounded_sequence_comparison(state : BoundedSequenceState) -> Unit {
  if state.comparison is Some(_) {
    state.comparison = None
    release_slots(state.workspace, 2)
  }
  state.compare_left = -1
  state.compare_right = -1
  state.compare_kind = None
  state.compare_column = 0
}
