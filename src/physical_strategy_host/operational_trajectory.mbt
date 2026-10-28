///|
struct OperationalRealization {
  task : Int
  registration : String
  resident : Bool
} derive(Eq)

///|
/// Read-only assignment correspondence, not a retained candidate or grant.
pub struct OperationalAssignmentTrajectory {
  tasks : Array[OperationalRealization?]
}

///|
fn operational_assignments(
  candidates : PolicyCandidateSet,
) -> Array[@decode.Cursor] raise PolicyWireStop {
  let node = match
    @source.parse_json_bytes(@utf8.encode(candidates.canonical_json), {
      max_input_bytes: 8388608,
      max_nodes: 1000000,
      max_depth: 24,
    }) {
    Ok(value) => value
    Err(_) => raise PolicyWireStop
  }
  let cursor = policy_wire_decoded(
    @decode.admit(node, {
      max_nodes: 1000000,
      max_depth: 24,
      max_string_bytes: 1024,
      max_total_string_bytes: 8388608,
    }),
  )
  guard @decode.element_at(cursor, 5) is Some(assignments) else {
    raise PolicyWireStop
  }
  let entries = policy_wire_decoded(@decode.elements(assignments))
  entries
}

///|
fn operational_realizations(
  assignment : @decode.Cursor,
) -> (Int, Array[OperationalRealization?]) raise PolicyWireStop {
  let fields = policy_wire_decoded(@decode.elements(assignment))
  if fields.length() != 6 {
    raise PolicyWireStop
  }
  let position = policy_wire_decoded(@decode.int32(fields[0]))
  if position < 0 {
    raise PolicyWireStop
  }
  let tasks = policy_wire_decoded(@decode.elements(fields[5]))
  if tasks.length() > 1024 {
    raise PolicyWireStop
  }
  let projected = []
  for index, task in tasks {
    if @decode.is_null(task) {
      projected.push(None)
      continue
    }
    let offer = policy_wire_decoded(@decode.elements(task))
    if offer.length() != 10 ||
      policy_wire_decoded(@decode.int32(offer[0])) != index {
      raise PolicyWireStop
    }
    projected.push(
      Some({
        task: index,
        registration: policy_wire_decoded(@decode.text(offer[1])),
        resident: !@decode.is_null(offer[9]),
      }),
    )
  }
  (position, projected)
}

///|
pub fn operational_candidate_trajectory(
  candidates : PolicyCandidateSet,
  position : Int,
) -> Result[OperationalAssignmentTrajectory, SearchIssue] {
  try {
    for assignment in operational_assignments(candidates) {
      let (found, tasks) = operational_realizations(assignment)
      if found == position {
        return Ok({ tasks, })
      }
    }
    Err(InvalidPreference)
  } catch {
    _ => Err(InvalidPreference)
  }
}

///|
/// Match against the current feasible projection. Prices, capacity and private
/// environment bindings remain subject to current ordinary admission/commit.
pub fn operational_residual_position(
  candidates : PolicyCandidateSet,
  trajectory : OperationalAssignmentTrajectory,
  first_task : Int,
) -> Result[Int?, SearchIssue] {
  try {
    if first_task < 1 || first_task >= trajectory.tasks.length() {
      raise PolicyWireStop
    }
    let mut best : Int? = None
    for assignment in operational_assignments(candidates) {
      let (position, tasks) = operational_realizations(assignment)
      if tasks.length() != trajectory.tasks.length() {
        continue
      }
      let mut matches = true
      for index in first_task..<tasks.length() {
        if tasks[index] is None ||
          trajectory.tasks[index] is None ||
          tasks[index] != trajectory.tasks[index] {
          matches = false
        }
      }
      if matches && (best is None || position < best.unwrap()) {
        best = Some(position)
      }
    }
    Ok(best)
  } catch {
    _ => Err(InvalidPreference)
  }
}

///|
pub fn operational_candidate_positions(
  candidates : PolicyCandidateSet,
) -> Result[Array[Int], SearchIssue] {
  try {
    let positions = []
    let assignments = operational_assignments(candidates)
    if assignments.length() > 64 {
      return Ok([])
    }
    for assignment in assignments {
      let fields = policy_wire_decoded(@decode.elements(assignment))
      if fields.length() != 6 {
        raise PolicyWireStop
      }
      let position = policy_wire_decoded(@decode.int32(fields[0]))
      if position < 0 || positions.contains(position) {
        raise PolicyWireStop
      }
      positions.push(position)
    }
    Ok(positions)
  } catch {
    _ => Err(InvalidPreference)
  }
}
