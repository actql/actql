///|
/// Exact owned binary step. The input identifiers preserve ordered occurrences,
/// including two reads from the same predecessor in a self join.
struct PreparedJoinKernel {
  owner : BoundPrepared
  step : Int
  profile : PreparedInnerJoin
  output_limit : Int64?
}

///|
pub fn prepare_join_kernel(
  owner : BoundPrepared,
  step : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedJoinKernel, InnerJoinIssue] {
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is InnerJoin(checked) &&
    node.inputs.length() == 2 else {
    return Err(InvalidCheckedShape)
  }
  let profile = match prepare_inner_join(checked, max_entries, max_name_bytes) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let output_limit = match @join.output_guard(checked) {
    None => None
    Some(Literal(n)) => Some(n)
    Some(Parameter(name)) => {
      let remaining = max_name_bytes - profile.name_bytes
      if name.length() > remaining || @utf8.encode(name).length() > remaining {
        return Err(PreparationLimit)
      }
      guard parameter_value(owner, name) is Some(value) &&
        value.value is @value.Number(n) &&
        @scalar.read_safe_integer(n) is Some(n) &&
        n > 0L else {
        return Err(InvalidGuard)
      }
      Some(n)
    }
  }
  Ok({ owner, step, profile, output_limit, })
}

///|
pub fn join_kernel_owner(kernel : PreparedJoinKernel) -> BoundPrepared {
  kernel.owner
}

///|
pub fn join_kernel_step(kernel : PreparedJoinKernel) -> Int {
  kernel.step
}

///|
pub fn join_kernel_profile(kernel : PreparedJoinKernel) -> PreparedInnerJoin {
  kernel.profile
}

///|
pub fn join_kernel_input(kernel : PreparedJoinKernel, left : Bool) -> String {
  kernel.owner.prepared.nodes[kernel.step].inputs[if left { 0 } else { 1 }]
}

///|
pub fn join_kernel_output_limit(kernel : PreparedJoinKernel) -> Int64? {
  kernel.output_limit
}
