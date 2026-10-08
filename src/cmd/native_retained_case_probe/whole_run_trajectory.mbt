///|
// Diagnostic projection only. The existing Owner admits every fresh request
// and commits a position from its current immutable feasible set.
fn whole_run_assignments(
  dispatch : @standard_host.StrategyHostDispatch,
) -> Array[Json] {
  let candidates = @standard_host.dispatch_policy_candidates(dispatch).unwrap()
  // These are already admitted, bounded Owner-generated projection bytes.
  let parsed = @json.parse(candidates.canonical_json) catch {
    _ => abort("WholeRunCandidateJSON")
  }
  guard parsed is Array(fields) &&
    fields.length() == 6 &&
    fields[5] is Array(assignments) else {
    abort("WholeRunCandidateProjection")
  }
  assignments
}

///|
fn whole_run_selected_trajectory(
  dispatch : @standard_host.StrategyHostDispatch,
  position : Int,
) -> Array[Json] {
  for assignment in whole_run_assignments(dispatch) {
    guard assignment is Array(fields) && fields.length() == 6 else {
      abort("WholeRunAssignmentProjection")
    }
    if fields[0] == position.to_json() {
      guard fields[5] is Array(tasks) else { abort("WholeRunTaskProjection") }
      println("whole-run-initial-assignment:" + assignment.stringify())
      return tasks
    }
  }
  abort("WholeRunPositionNotOffered")
}

///|
// Match task identity, actual registration and offered resident realization.
// Cost/capacity projections may change as held inputs and generation change;
// all of those are checked anew by the common admission/commit path. This
// single-site fixture does not infer an opaque environment identity from JSON.
fn whole_run_realization(offer : Json) -> String {
  guard offer is Array(fields) && fields.length() == 10 else {
    abort("WholeRunOfferProjection")
  }
  fields[0].stringify() +
  ":" +
  fields[1].stringify() +
  ":" +
  (!(fields[9] is Null)).to_string()
}

///|
fn whole_run_residual_position(
  dispatch : @standard_host.StrategyHostDispatch,
  trajectory : Array[Json],
  task : Int,
) -> Int? {
  let mut best : Int? = None
  for assignment in whole_run_assignments(dispatch) {
    guard assignment is Array(fields) &&
      fields.length() == 6 &&
      fields[5] is Array(tasks) &&
      tasks.length() == trajectory.length() else {
      abort("WholeRunResidualProjection")
    }
    let mut matches = true
    for index in task..<tasks.length() {
      if tasks[index] is Null ||
        trajectory[index] is Null ||
        whole_run_realization(tasks[index]) !=
        whole_run_realization(trajectory[index]) {
        matches = false
      }
    }
    if matches {
      guard fields[0] is Number(value, ..) else {
        abort("WholeRunPositionProjection")
      }
      let position = value.to_int()
      if best is None || position < best.unwrap() {
        best = Some(position)
      }
    }
  }
  println(
    "whole-run-residual-position:" +
    task.to_string() +
    ":" +
    best.to_json().stringify(),
  )
  best
}
