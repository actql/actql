///|
priv enum RequestCeiling {
  Rows
  ValueBytes
}

///|
priv struct RequestLimit {
  request : RequestArtifact
  ceiling : RequestCeiling
  witness_cid : String
  cid : String
}

///|
fn request_ceiling_fields(
  request : RequestArtifact,
  ceiling : RequestCeiling,
) -> (String, String, Int64) {
  let values = @lower.fragment_request_ceilings(request.request)
  match ceiling {
    Rows => ("/max_rows", "rows", values.0)
    ValueBytes => ("/max_value_bytes", "bytes", values.1)
  }
}

///|
fn emit_request_witness(
  request : RequestArtifact,
  ceiling : RequestCeiling,
  cid : String?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let (pointer, unit, value) = request_ceiling_fields(request, ceiling)
  @encode.begin_object(out)
  @encode.key(out, "dependencies")
  @encode.begin_array(out)
  @encode.string_value(out, request.artifact.cid)
  @encode.end_array(out)
  @encode.key(out, "derivation")
  @encode.begin_object(out)
  @encode.key(out, "op")
  @encode.string_value(out, "source")
  @encode.end_object(out)
  @encode.key(out, "law_id")
  @encode.string_value(out, "actql.expression-fragment.capacity")
  @encode.key(out, "role")
  @encode.string_value(out, "contract_ceiling")
  @encode.key(out, "source")
  @encode.begin_object(out)
  @encode.key(out, "contract_cid")
  @encode.string_value(out, request.artifact.cid)
  @encode.key(out, "field")
  @encode.string_value(out, pointer)
  @encode.key(out, "kind")
  @encode.string_value(out, "contract")
  @encode.end_object(out)
  @encode.key(out, "unit")
  @encode.string_value(out, unit)
  @encode.key(out, "value")
  @encode.number_value(out, value.to_double())
  @encode.key(out, "version")
  @encode.string_value(out, "actql-bound-witness/0.1")
  match cid {
    Some(cid) => {
      @encode.key(out, "witness_cid")
      @encode.string_value(out, cid)
    }
    None => ()
  }
  @encode.end_object(out)
}

///|
fn emit_request_resolved_limit(
  limit : RequestLimit,
  include_cid : Bool,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let (pointer, unit, value) = request_ceiling_fields(
    limit.request,
    limit.ceiling,
  )
  @encode.begin_object(out)
  @encode.key(out, "author_guard_binding")
  @encode.string_value(out, "absent")
  @encode.key(out, "breach")
  @encode.string_value(out, "fail")
  @encode.key(out, "candidates")
  @encode.begin_array(out)
  emit_request_witness(
    limit.request,
    limit.ceiling,
    Some(limit.witness_cid),
    out,
  )
  @encode.end_array(out)
  @encode.key(out, "effective_max")
  @encode.number_value(out, value.to_double())
  @encode.key(out, "enforcement")
  @encode.string_value(out, "engine_atomic")
  if include_cid {
    @encode.key(out, "resolved_limit_cid")
    @encode.string_value(out, limit.cid)
  }
  @encode.key(out, "subject_ref")
  @encode.string_value(out, pointer)
  @encode.key(out, "unit")
  @encode.string_value(out, unit)
  @encode.key(out, "version")
  @encode.string_value(out, "actql-resolved-limit/0.1")
  @encode.end_object(out)
}

///|
fn prepare_request_limit(
  request : RequestArtifact,
  ceiling : RequestCeiling,
  limits : RegistryLimits,
) -> Result[RequestLimit, RootArtifactIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 1 ||
    limits.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  try {
    let witness = @encode.hashing_writer(
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    emit_request_witness(request, ceiling, None, witness)
    let witness_cid = "sha256:" + @encode.finish_hash(witness)
    let pending = { request, ceiling, witness_cid, cid: "", }
    let resolved = @encode.hashing_writer(
      limits.max_body_bytes,
      limits.max_body_nodes,
      limits.max_body_depth,
    )
    emit_request_resolved_limit(pending, false, resolved)
    Ok({ ..pending, cid: "sha256:" + @encode.finish_hash(resolved), })
  } catch {
    _ => Err(OutputLimit)
  }
}

///|
/// Both currently supported request ceilings, sorted by request pointer.
/// Aggregation guards belong to future aggregate fragments, not these kernels.
fn emit_request_limits(
  request : RequestArtifact,
  limits : RegistryLimits,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  for ceiling in [RequestCeiling::Rows, ValueBytes] {
    let limit = match prepare_request_limit(request, ceiling, limits) {
      Ok(limit) => limit
      Err(_) => raise @encode.InvalidStructure
    }
    @encode.begin_object(out)
    @encode.key(out, "request_pointer")
    @encode.string_value(out, request_ceiling_fields(request, ceiling).0)
    @encode.key(out, "resolved_limit")
    emit_request_resolved_limit(limit, true, out)
    @encode.end_object(out)
  }
  @encode.end_array(out)
}
