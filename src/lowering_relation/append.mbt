///|
/// Exact checked append occurrence. Alignment positions preserve author field
/// identity without exposing the mutable checked table to physical backends.
struct PreparedAppendKernel {
  owner : BoundPrepared
  step : Int
  checked : @append.CheckedAppend
  fields : Array[(@schema.FieldName, Int, Int)]
  name_bytes : Int
}

///|
pub(all) enum AppendIssue {
  InvalidLimits
  PreparationLimit
  InvalidCheckedShape
} derive(Eq, Debug)

///|
pub fn prepare_append_kernel(
  owner : BoundPrepared,
  step : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedAppendKernel, AppendIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is AppendRows(checked) &&
    node.inputs.length() == 2 else {
    return Err(InvalidCheckedShape)
  }
  let output = @append.output_schema(checked)
  let width = @schema.field_count(output)
  if width > max_entries {
    return Err(PreparationLimit)
  }
  let left = @append.input_schema(checked, @schema.Left)
  let right = @append.input_schema(checked, @schema.Right)
  let fields = []
  let mut remaining = max_name_bytes
  for index in 0..<width {
    guard @append.alignment_at(checked, index) is Some((field, li, ri)) &&
      @schema.field_at(output, index) is Some(out) &&
      @schema.field_at(left, li) is Some(lf) &&
      @schema.field_at(right, ri) is Some(rf) &&
      out.name == field &&
      lf.name == field &&
      rf.name == field else {
      return Err(InvalidCheckedShape)
    }
    let name = @schema.reference_name(field)
    if name.length() > remaining {
      return Err(PreparationLimit)
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return Err(PreparationLimit)
    }
    remaining -= bytes
    fields.push((field, li, ri))
  }
  Ok({ owner, step, checked, fields, name_bytes: max_name_bytes - remaining, })
}

///|
pub fn append_kernel_owner(kernel : PreparedAppendKernel) -> BoundPrepared {
  kernel.owner
}

///|
pub fn append_kernel_step(kernel : PreparedAppendKernel) -> Int {
  kernel.step
}

///|
pub fn append_kernel_input(
  kernel : PreparedAppendKernel,
  left : Bool,
) -> String {
  kernel.owner.prepared.nodes[kernel.step].inputs[if left { 0 } else { 1 }]
}

///|
pub fn append_kernel_output(kernel : PreparedAppendKernel) -> String {
  kernel.owner.prepared.nodes[kernel.step].id
}

///|
pub fn append_kernel_output_schema(
  kernel : PreparedAppendKernel,
) -> @schema.Schema {
  @append.output_schema(kernel.checked)
}

///|
pub fn append_kernel_field_count(kernel : PreparedAppendKernel) -> Int {
  kernel.fields.length()
}

///|
pub fn append_kernel_field_at(
  kernel : PreparedAppendKernel,
  index : Int,
) -> (@schema.FieldName, Int, Int)? {
  kernel.fields.get(index)
}

///|
pub fn append_kernel_name_bytes(kernel : PreparedAppendKernel) -> Int {
  kernel.name_bytes
}

///|
pub fn append_kernel_matches_node(
  kernel : PreparedAppendKernel,
  node : PreparedNode,
) -> Bool {
  node.payload is AppendRows(checked) && physical_equal(kernel.checked, checked)
}
