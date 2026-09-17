///|
/// Canonical REL.unionAll occurrence. Checked append alignment has already
/// established the shared output schema; the primitive has no extra params.
pub fn emit_append_kernel(
  kernel : PreparedAppendKernel,
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
  @encode.string_value(out, "REL.unionAll")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.end_object(out)
  @encode.end_object(out)
}
