///|
/// Declared enforcement quantities shared by request projection and runtime.
/// These are not inferred cardinalities or evidence of successful execution.
pub(all) struct FragmentRowLimits {
  max_input_rows : Int64
  max_value_bytes : Int64
  max_live_value_bytes : Int64
  max_work : Int64
}

///|
pub fn fragment_row_limits_valid(limits : FragmentRowLimits) -> Bool {
  for
    value in [
      limits.max_input_rows,
      limits.max_value_bytes,
      limits.max_live_value_bytes,
      limits.max_work,
    ] {
    if value < 0L || value > 9007199254740991L {
      return false
    }
  }
  true
}

///|
pub fn emit_fragment_row_limits_body(
  limits : FragmentRowLimits,
  self_cid : String?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "max_input_rows")
  @encode.number_value(out, limits.max_input_rows.to_double())
  @encode.key(out, "max_live_value_bytes")
  @encode.number_value(out, limits.max_live_value_bytes.to_double())
  @encode.key(out, "max_value_bytes")
  @encode.number_value(out, limits.max_value_bytes.to_double())
  @encode.key(out, "max_work")
  @encode.number_value(out, limits.max_work.to_double())
  if self_cid is Some(cid) {
    @encode.key(out, "self_cid")
    @encode.string_value(out, cid)
  }
  @encode.key(out, "version")
  @encode.string_value(out, "actql-derive-row-limits/0.1")
  @encode.end_object(out)
}
