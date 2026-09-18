///|
/// Emit the selected AoA cross-join node directly from the checked typed view.
pub fn emit_cross_join_kernel(
  kernel : PreparedCrossJoinKernel,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let profile = kernel.profile
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, cross_join_kernel_output(kernel))
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, cross_join_kernel_input(kernel, true))
  @encode.string_value(out, cross_join_kernel_input(kernel, false))
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.cross_join")
  @encode.key(out, "params")
  @encode.begin_object(out)
  if @join.cross_requires_one_right_row(profile.checked) {
    @encode.key(out, "right_rows")
    @encode.string_value(out, "one")
  }
  if kernel.output_limit is Some(limit) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, limit.to_double())
  }
  if cross_join_has_projection(profile) {
    @encode.key(out, "select")
    @encode.begin_object(out)
    for field in profile.projection {
      @encode.key(out, @schema.reference_name(field.output))
      @encode.string_value(out, @schema.reference_name(field.input))
    }
    @encode.end_object(out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
