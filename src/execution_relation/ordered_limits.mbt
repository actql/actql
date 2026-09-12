///|
/// A generated same-kernel limits member. This is not admission of an enclosing
/// fragment request: its exact step map and request identity are still required.
priv struct OrderedLimits {
  params : OrderedParams
  limits : LogicalLimits
  cid : String
}

///|
priv enum OrderedLimitsIssue {
  InvalidLimits
  EnclosingLimit
  ForeignKernel
  EncodingLimit
} derive(Eq, Debug)

///|
fn prepare_ordered_limits(
  params : OrderedParams,
  limits : LogicalLimits,
  request_rows : Int64,
  request_value_bytes : Int64,
) -> Result[OrderedLimits, OrderedLimitsIssue] {
  if validate_logical_limits(limits) is Err(_) ||
    request_rows < 0L ||
    request_rows > 9007199254740991L ||
    request_value_bytes < 0L ||
    request_value_bytes > 9007199254740991L {
    return Err(InvalidLimits)
  }
  if limits.max_input_rows > request_rows ||
    limits.max_value_bytes > request_value_bytes {
    return Err(EnclosingLimit)
  }
  // Closed, constant-size schema; every integer has at most 16 decimal digits.
  let cid = try {
    let out = @encode.hashing_writer(1024, 16, 2)
    emit_ordered_limits_body(limits, None, out)
    "sha256:" + @encode.finish_hash(out)
  } catch {
    _ => return Err(EncodingLimit)
  }
  Ok({ params, limits, cid, })
}

///|
fn emit_ordered_limits_body(
  limits : LogicalLimits,
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
  match self_cid {
    Some(cid) => {
      @encode.key(out, "self_cid")
      @encode.string_value(out, cid)
    }
    None => ()
  }
  @encode.key(out, "version")
  @encode.string_value(out, "actql-derive-row-limits/0.1")
  @encode.end_object(out)
}

///|
fn ordered_limits_for_kernel(
  context : OrderedLimits,
  kernel : @lower.PreparedKernel,
) -> Result[LogicalLimits, OrderedLimitsIssue] {
  if !physical_equal(ordered_params_kernel(context.params), kernel) {
    return Err(ForeignKernel)
  }
  Ok(context.limits)
}
