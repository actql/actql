///|
/// Bounded readonly view of one checked cross-join occurrence. The view keeps
/// the exact checked owner, ordered inputs, projection, singleton assertion,
/// and output guard without re-reading author syntax.
struct PreparedCrossJoin {
  checked : @join.CheckedCrossJoin
  projection : Array[CrossJoinField]
  projected : Bool
  name_bytes : Int
}

///|
pub struct CrossJoinField {
  output : @schema.FieldName
  input : @schema.FieldName
}

///|
pub(all) enum CrossJoinIssue {
  InvalidLimits
  PreparationLimit
  InvalidCheckedShape
  InvalidGuard
} derive(Eq, Debug)

///|
fn prepare_cross_join(
  checked : @join.CheckedCrossJoin,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedCrossJoin, CrossJoinIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  let schema = @join.cross_output_schema(checked)
  let width = @schema.field_count(schema)
  if width > max_entries {
    return Err(PreparationLimit)
  }
  let authored = @join.cross_projection(checked)
  let projection : Array[CrossJoinField] = []
  let mut remaining = max_name_bytes
  let spend = fn(field : @schema.FieldName) -> Bool {
    let name = @schema.reference_name(field)
    if name.length() > remaining {
      return false
    }
    let size = @utf8.encode(name).length()
    if size > remaining {
      return false
    }
    remaining -= size
    true
  }
  for index in 0..<width {
    let output = @schema.field_at(schema, index).unwrap().name
    let input = match authored {
      None => output
      Some(fields) => {
        guard fields.get(index) is Some(field) && field.output == output else {
          return Err(InvalidCheckedShape)
        }
        field.input
      }
    }
    if !spend(output) || !spend(input) {
      return Err(PreparationLimit)
    }
    projection.push({ output, input, })
  }
  Ok({
    checked,
    projection,
    projected: authored is Some(_),
    name_bytes: max_name_bytes - remaining,
  })
}

///|
pub fn cross_join_checked(value : PreparedCrossJoin) -> @join.CheckedCrossJoin {
  value.checked
}

///|
pub fn cross_join_requires_one_right(value : PreparedCrossJoin) -> Bool {
  @join.cross_requires_one_right_row(value.checked)
}

///|
pub fn cross_join_input_schema(
  value : PreparedCrossJoin,
  left : Bool,
) -> @schema.Schema {
  @join.cross_input_schema(
    value.checked,
    if left {
      @schema.Left
    } else {
      @schema.Right
    },
  )
}

///|
pub fn cross_join_field_count(value : PreparedCrossJoin) -> Int {
  value.projection.length()
}

///|
pub fn cross_join_has_projection(value : PreparedCrossJoin) -> Bool {
  value.projected
}

///|
pub fn cross_join_field_at(
  value : PreparedCrossJoin,
  index : Int,
) -> CrossJoinField? {
  value.projection.get(index)
}

///|
struct PreparedCrossJoinKernel {
  owner : BoundPrepared
  step : Int
  profile : PreparedCrossJoin
  output_limit : Int64?
}

///|
pub fn prepare_cross_join_kernel(
  owner : BoundPrepared,
  step : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedCrossJoinKernel, CrossJoinIssue] {
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is CrossJoinRows(checked) &&
    node.inputs.length() == 2 else {
    return Err(InvalidCheckedShape)
  }
  let profile = match prepare_cross_join(checked, max_entries, max_name_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output_limit = match @join.cross_output_guard(checked) {
    None => None
    Some(Literal(value)) => Some(value)
    Some(Parameter(name)) => {
      let remaining = max_name_bytes - profile.name_bytes
      if name.length() > remaining || @utf8.encode(name).length() > remaining {
        return Err(PreparationLimit)
      }
      guard parameter_value(owner, name) is Some(value) &&
        value.value is @value.Number(number) &&
        @scalar.read_safe_integer(number) is Some(number) &&
        number > 0L else {
        return Err(InvalidGuard)
      }
      Some(number)
    }
  }
  Ok({ owner, step, profile, output_limit, })
}

///|
pub fn cross_join_kernel_owner(
  kernel : PreparedCrossJoinKernel,
) -> BoundPrepared {
  kernel.owner
}

///|
pub fn cross_join_kernel_step(kernel : PreparedCrossJoinKernel) -> Int {
  kernel.step
}

///|
pub fn cross_join_kernel_profile(
  kernel : PreparedCrossJoinKernel,
) -> PreparedCrossJoin {
  kernel.profile
}

///|
pub fn cross_join_kernel_input(
  kernel : PreparedCrossJoinKernel,
  left : Bool,
) -> String {
  kernel.owner.prepared.nodes[kernel.step].inputs[if left { 0 } else { 1 }]
}

///|
pub fn cross_join_kernel_output(kernel : PreparedCrossJoinKernel) -> String {
  kernel.owner.prepared.nodes[kernel.step].id
}

///|
pub fn cross_join_kernel_output_limit(
  kernel : PreparedCrossJoinKernel,
) -> Int64? {
  kernel.output_limit
}

///|
pub fn cross_join_kernel_name_bytes(kernel : PreparedCrossJoinKernel) -> Int {
  kernel.profile.name_bytes
}
