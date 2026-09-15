///|
/// Selected enforcement requirements, not counters, backend preparation or
/// evidence of successful execution. The request fixes the exact occurrence.
pub struct FragmentEnforcement {
  request : FragmentRequest
  logical : FragmentRowLimits
  measure_bytes : Int
  measure_nodes : Int
  measure_depth : Int
  root_result_bytes : Int64?
  all_expression_roots : Bool
}

///|
/// Backend-independent requirements for an owned semantic sequence. Runtime
/// storage, retained buffers, attempts and execution handles are absent.
struct SequenceRequirements {
  sequence : PreparedSequence
  fragments : Array[FragmentEnforcement]
  by_step : Map[Int, FragmentEnforcement]
  join_ceilings : Array[(Int, Int64)]
}

///|
pub(all) enum SequenceRequirementsIssue {
  InvalidLimits
  ForeignOccurrence
  DuplicateOccurrence
  ExceedsRequest
}

///|
pub fn prepare_fragment_enforcement(
  request : FragmentRequest,
  logical : FragmentRowLimits,
  measure_bytes : Int,
  measure_nodes : Int,
  measure_depth : Int,
  root_result_bytes : Int64?,
  all_expression_roots : Bool,
) -> Result[FragmentEnforcement, SequenceRequirementsIssue] {
  if !fragment_row_limits_valid(logical) ||
    measure_bytes < 0 ||
    measure_nodes < 0 ||
    measure_depth < 0 ||
    (root_result_bytes is Some(n) && n < 0L) {
    return Err(InvalidLimits)
  }
  if logical.max_input_rows > request.max_rows ||
    logical.max_value_bytes > request.max_value_bytes {
    return Err(ExceedsRequest)
  }
  if request.row_limits is Some(declared) &&
    (
      logical.max_input_rows > declared.max_input_rows ||
      logical.max_value_bytes > declared.max_value_bytes ||
      logical.max_live_value_bytes > declared.max_live_value_bytes ||
      logical.max_work > declared.max_work
    ) {
    return Err(ExceedsRequest)
  }
  Ok({
    request,
    logical,
    measure_bytes,
    measure_nodes,
    measure_depth,
    root_result_bytes,
    all_expression_roots,
  })
}

///|
/// Bind existing requests without rebuilding their claims. Bounded handle
/// copies prevent callers from replacing an occurrence after selection.
pub fn prepare_sequence_requirements(
  sequence : PreparedSequence,
  fragments : Array[FragmentEnforcement],
  join_ceilings : Array[(Int, Int64)],
  max_entries : Int,
) -> Result[SequenceRequirements, SequenceRequirementsIssue] {
  if max_entries < 0 ||
    fragments.length() > max_entries ||
    join_ceilings.length() > max_entries - fragments.length() {
    return Err(InvalidLimits)
  }
  let by_step : Map[Int, FragmentEnforcement] = Map([])
  for requirement in fragments {
    let fragment = requirement.request.pipeline
    if !physical_equal(fragment.roots.sequence, sequence) {
      return Err(ForeignOccurrence)
    }
    let step = kernel_step(fragment.kernel)
    if by_step.contains(step) {
      return Err(DuplicateOccurrence)
    }
    by_step[step] = requirement
  }
  let mut previous = -1
  for (step, ceiling) in join_ceilings {
    if step <= previous || ceiling < 0L {
      return Err(InvalidLimits)
    }
    guard sequence_step(sequence, step) is Some(JoinStep(_)) else {
      return Err(ForeignOccurrence)
    }
    previous = step
  }
  Ok({
    sequence,
    fragments: fragments.copy(),
    by_step,
    join_ceilings: join_ceilings.copy(),
  })
}

///|
pub fn sequence_requirements_owner(
  value : SequenceRequirements,
) -> BoundPrepared {
  sequence_owner(value.sequence)
}

///|
pub fn sequence_requirements_sequence(
  value : SequenceRequirements,
) -> PreparedSequence {
  value.sequence
}

///|
pub fn sequence_requirements_fragment_count(
  value : SequenceRequirements,
) -> Int {
  value.fragments.length()
}

///|
pub fn sequence_requirements_fragment_at(
  value : SequenceRequirements,
  index : Int,
) -> FragmentEnforcement? {
  value.fragments.get(index)
}

///|
/// Occurrence lookup in the index bounded at construction by max_entries.
/// Enumeration order has no bearing on the sequence's execution order.
pub fn sequence_requirements_fragment_for_step(
  value : SequenceRequirements,
  step : Int,
) -> FragmentEnforcement? {
  value.by_step.get(step)
}

///|
pub fn sequence_requirements_join_count(value : SequenceRequirements) -> Int {
  value.join_ceilings.length()
}

///|
pub fn sequence_requirements_join_at(
  value : SequenceRequirements,
  index : Int,
) -> (Int, Int64)? {
  value.join_ceilings.get(index)
}
