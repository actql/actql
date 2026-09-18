///|
/// Canonical registered row-set occurrence. Alignment is checked preparation
/// metadata and is not restated as a backend-selected parameter.
pub fn emit_set_kernel(
  kernel : PreparedSetKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = kernel.owner.prepared.nodes[kernel.step]
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(
    out,
    match set_kernel_operation(kernel) {
      @set.Except => "REL.except_rows"
      @set.Intersect => "REL.intersect_rows"
    },
  )
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "duplicates")
  @encode.string_value(
    out,
    match set_kernel_duplicates(kernel) {
      @set.Distinct => "distinct"
      @set.All => "all"
    },
  )
  @encode.end_object(out)
  @encode.end_object(out)
}
