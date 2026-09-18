///|
/// Exact checked row-set occurrence. Field coordinates preserve the checked
/// name alignment; physical execution must not realign rows independently.
struct PreparedSetKernel {
  owner : BoundPrepared
  step : Int
  checked : @set.CheckedSet
  fields : Array[(@schema.FieldName, Int, Int)]
  name_bytes : Int
}

///|
pub(all) enum SetIssue {
  InvalidLimits
  PreparationLimit
  InvalidCheckedShape
} derive(Eq, Debug)

///|
pub fn prepare_set_kernel(
  owner : BoundPrepared,
  step : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedSetKernel, SetIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is SetRows(checked) &&
    node.inputs.length() == 2 else {
    return Err(InvalidCheckedShape)
  }
  let output = @set.output_schema(checked)
  let width = @schema.field_count(output)
  if width > max_entries {
    return Err(PreparationLimit)
  }
  let aligned = @set.alignment(checked)
  if aligned.length() != width {
    return Err(InvalidCheckedShape)
  }
  let left = @set.input_schema(checked, @schema.Left)
  let right = @set.input_schema(checked, @schema.Right)
  let fields = []
  let mut remaining = max_name_bytes
  for index in 0..<width {
    let alignment = aligned[index]
    guard @schema.field_at(output, index) is Some(out) &&
      @schema.field_at(left, alignment.left_index) is Some(lf) &&
      @schema.field_at(right, alignment.right_index) is Some(rf) &&
      out.name == alignment.field &&
      lf.name == alignment.field &&
      rf.name == alignment.field else {
      return Err(InvalidCheckedShape)
    }
    let name = @schema.reference_name(alignment.field)
    if name.length() > remaining {
      return Err(PreparationLimit)
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return Err(PreparationLimit)
    }
    remaining -= bytes
    fields.push((alignment.field, alignment.left_index, alignment.right_index))
  }
  Ok({ owner, step, checked, fields, name_bytes: max_name_bytes - remaining, })
}

///|
pub fn set_kernel_owner(kernel : PreparedSetKernel) -> BoundPrepared {
  kernel.owner
}

///|
pub fn set_kernel_step(kernel : PreparedSetKernel) -> Int {
  kernel.step
}

///|
pub fn set_kernel_input(kernel : PreparedSetKernel, left : Bool) -> String {
  kernel.owner.prepared.nodes[kernel.step].inputs[if left { 0 } else { 1 }]
}

///|
pub fn set_kernel_output(kernel : PreparedSetKernel) -> String {
  kernel.owner.prepared.nodes[kernel.step].id
}

///|
pub fn set_kernel_operation(kernel : PreparedSetKernel) -> @set.Operation {
  @set.operation(kernel.checked)
}

///|
pub fn set_kernel_duplicates(kernel : PreparedSetKernel) -> @set.Duplicates {
  @set.duplicates(kernel.checked)
}

///|
pub fn set_kernel_output_schema(kernel : PreparedSetKernel) -> @schema.Schema {
  @set.output_schema(kernel.checked)
}

///|
pub fn set_kernel_field_count(kernel : PreparedSetKernel) -> Int {
  kernel.fields.length()
}

///|
pub fn set_kernel_field_at(
  kernel : PreparedSetKernel,
  index : Int,
) -> (@schema.FieldName, Int, Int)? {
  kernel.fields.get(index)
}

///|
pub fn set_kernel_name_bytes(kernel : PreparedSetKernel) -> Int {
  kernel.name_bytes
}

///|
pub fn set_kernel_matches_node(
  kernel : PreparedSetKernel,
  node : PreparedNode,
) -> Bool {
  node.payload is SetRows(checked) && physical_equal(kernel.checked, checked)
}
