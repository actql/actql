///|
/// The caller owns contributor stability and the enclosing resource scope.
/// Each advance admits one contributor, copies one pair-workspace entry,
/// performs one prescribed addition, or performs the final division.
struct ReductionExecution {
  reduction : Reduction
  operation : Operation
  mut contributors : Array[Double]
  max_work : Int
  mut work : Int
  mut phase : Int
  mut index : Int
  mut value : Double
  mut current : Array[Double]
  mut next : Array[Double]
  mut closed : Bool
}

///|
pub fn start_reduction(
  reduction : Reduction,
  operation : Operation,
  contributors : Array[Double],
  max_contributors : Int,
  max_work : Int,
) -> Result[ReductionExecution, ReductionIssue] {
  if max_contributors < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if contributors.length() > max_contributors {
    return Err(ContributorLimit)
  }
  Ok({
    reduction,
    operation,
    contributors,
    max_work,
    work: 0,
    phase: 0,
    index: 0,
    value: 0.0,
    current: [],
    next: [],
    closed: false,
  })
}

///|
pub fn close_reduction(state : ReductionExecution) -> Unit {
  state.contributors = []
  state.current = []
  state.next = []
  state.closed = true
}

///|
fn reduction_charge(state : ReductionExecution) -> Bool {
  if state.work == state.max_work {
    false
  } else {
    state.work += 1
    true
  }
}

///|
pub fn advance_reduction(
  state : ReductionExecution,
) -> Result[Outcome?, ReductionIssue] {
  if state.closed {
    return Err(InvalidLimits)
  }
  let result = advance_reduction_impl(state)
  match result {
    Err(_) | Ok(Some(_)) => close_reduction(state)
    Ok(None) => ()
  }
  result
}

///|
fn advance_reduction_impl(
  state : ReductionExecution,
) -> Result[Outcome?, ReductionIssue] {
  let count = state.contributors.length()
  match state.phase {
    0 =>
      if state.index < count {
        if !reduction_charge(state) {
          return Err(WorkLimit)
        }
        if !finite(state.contributors[state.index]) {
          return Err(NonfiniteContributor(state.index))
        }
        state.index += 1
      } else if count == 0 {
        return Ok(Some({ value: None, count, work: state.work, }))
      } else {
        state.index = 0
        state.phase = match state.reduction.algorithm {
          LeftFold => 1
          AdjacentPairs =>
            if count == 1 {
              state.value = state.contributors[0]
              4
            } else {
              2
            }
        }
      }
    1 =>
      if state.index == count {
        state.phase = 4
      } else {
        if !reduction_charge(state) {
          return Err(WorkLimit)
        }
        state.value = match
          checked_add(state.value, state.contributors[state.index]) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        state.index += 1
      }
    2 =>
      if state.current.length() < count {
        state.current.push(state.contributors[state.current.length()])
      } else {
        state.phase = 3
      }
    3 =>
      if state.current.length() == 1 {
        state.value = state.current[0]
        state.phase = 4
      } else if state.index == state.current.length() {
        state.current = state.next
        state.next = []
        state.index = 0
      } else if state.index + 1 == state.current.length() {
        state.next.push(state.current[state.index])
        state.index += 1
      } else {
        if !reduction_charge(state) {
          return Err(WorkLimit)
        }
        let value = match
          checked_add(
            state.current[state.index],
            state.current[state.index + 1],
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        state.next.push(value)
        state.index += 2
      }
    4 => {
      if state.operation is Average {
        if !reduction_charge(state) {
          return Err(WorkLimit)
        }
        state.value /= count.to_double()
        if !finite(state.value) {
          return Err(NonfiniteIntermediate)
        }
      }
      return Ok(
        Some({ value: Some(public_zero(state.value)), count, work: state.work, }),
      )
    }
    _ => return Err(InvalidLimits)
  }
  Ok(None)
}
