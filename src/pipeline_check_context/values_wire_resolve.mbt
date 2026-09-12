///|
pub(all) enum ValuesWireResolutionIssue {
  Measurement(ValuesMeasurementIssue)
  Encoding(@encode.EncodeFailure)
  Proof(@wire.Issue)
  Limit(ValuesWireLimitIssue)
} derive(Debug)

///|
fn emit_values_measurement_proof(
  subject : String,
  bytes : Int,
  out : @encode.Writer,
  law? : String = "actql.bound.values-wire",
  unit? : String = "bytes",
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "inputs")
  @encode.begin_array(out)
  @encode.end_array(out)
  @encode.key(out, "law_id")
  @encode.string_value(out, law)
  @encode.key(out, "semantic_ref")
  @encode.string_value(out, subject)
  @encode.key(out, "unit")
  @encode.string_value(out, unit)
  @encode.key(out, "value")
  @encode.number_value(out, bytes.to_double())
  @encode.key(out, "version")
  @encode.string_value(out, "actql-bound-proof/0.1")
  @encode.end_object(out)
}

///|
fn emit_values_measurement_witness(
  subject : String,
  bytes : Int,
  proof_cid : String,
  witness_cid : String?,
  out : @encode.Writer,
  law? : String = "actql.bound.values-wire",
  unit? : String = "bytes",
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "dependencies")
  @encode.begin_array(out)
  @encode.string_value(out, proof_cid)
  @encode.end_array(out)
  @encode.key(out, "derivation")
  @encode.begin_object(out)
  @encode.key(out, "op")
  @encode.string_value(out, "source")
  @encode.end_object(out)
  @encode.key(out, "law_id")
  @encode.string_value(out, law)
  @encode.key(out, "role")
  @encode.string_value(out, "proven_upper_bound")
  @encode.key(out, "source")
  @encode.begin_object(out)
  @encode.key(out, "kind")
  @encode.string_value(out, "program")
  @encode.key(out, "proof_cid")
  @encode.string_value(out, proof_cid)
  @encode.key(out, "semantic_ref")
  @encode.string_value(out, subject)
  @encode.end_object(out)
  @encode.key(out, "unit")
  @encode.string_value(out, unit)
  @encode.key(out, "value")
  @encode.number_value(out, bytes.to_double())
  @encode.key(out, "version")
  @encode.string_value(out, "actql-bound-witness/0.1")
  if witness_cid is Some(cid) {
    @encode.key(out, "witness_cid")
    @encode.string_value(out, cid)
  }
  @encode.end_object(out)
}

///|
/// Derive the whole-/rows wire limit directly from owned cell resolutions.
/// No caller-built proof or claimed byte count is required. Payload limits bound
/// the one measurement pass; metadata limits bound each proof/witness/limit
/// encoding and admission, not aggregate Program work or physical memory.
/// Other publication resources remain independent requirements.
pub fn resolve_values_wire_limit(
  cells : ProgramOperationCells,
  requirement_index : Int,
  payload : @wire.Limits,
  metadata : @wire.LimitLimits,
) -> Result[ValuesWireLimit, ValuesWireResolutionIssue] {
  if metadata.max_bytes < 0 ||
    metadata.max_nodes < 0 ||
    metadata.max_depth < 0 ||
    metadata.max_candidates < 0 {
    return Err(Limit(Admission(@wire.InvalidLimits)))
  }
  if metadata.max_candidates < 1 {
    return Err(Limit(Admission(@wire.BudgetExceeded)))
  }
  let (bytes, nodes, depth) = match
    measure_operation_values_rows(
      cells,
      requirement_index,
      payload.max_bytes,
      payload.max_nodes,
      payload.max_depth,
    ) {
    Ok(v) => v
    Err(e) => return Err(Measurement(e))
  }
  // The measurement validates the exact resource occurrence before indexing.
  let requirements = cells.queries.ranges.fills.frames.scalars.orders.requirements
  let site = requirements.entries[requirement_index]
  let subject = "checked-step:" + site.step.to_string()
  let limits : @wire.Limits = {
    max_bytes: metadata.max_bytes,
    max_nodes: metadata.max_nodes,
    max_depth: metadata.max_depth,
  }
  fn writer() -> @encode.Writer raise @encode.EncodeFailure {
    @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
  }
  fn hasher() -> @encode.Writer raise @encode.EncodeFailure {
    @encode.hashing_writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
  }
  try {
    let hash = hasher()
    emit_values_measurement_proof(subject, bytes, hash)
    let proof_cid = "sha256:" + @encode.finish_hash(hash)
    let proof_out = writer()
    emit_values_measurement_proof(subject, bytes, proof_out)
    let proof_bytes = @wire_utf8.encode(@encode.finish(proof_out))
    let hash = hasher()
    emit_values_measurement_witness(subject, bytes, proof_cid, None, hash)
    let witness_cid = "sha256:" + @encode.finish_hash(hash)
    let witness_out = writer()
    emit_values_measurement_witness(
      subject,
      bytes,
      proof_cid,
      Some(witness_cid),
      witness_out,
    )
    let witness = match
      @wire.admit(
        @wire_utf8.encode(@encode.finish(witness_out)),
        witness_cid,
        limits,
      ) {
      Ok(v) => v
      Err(e) => return Err(Proof(e))
    }
    let proof = match @wire.bind_program_proof(proof_bytes, witness, limits) {
      Ok(v) => v
      Err(e) => return Err(Proof(e))
    }
    // The claim was derived from this measurement, rather than supplied by a
    // caller; retain that exact ownership without measuring the payload twice.
    let bound : ValuesWireBound = {
      cells,
      requirement_index,
      site,
      proof,
      bytes,
      nodes,
      depth,
    }
    match create_values_wire_limit(bound, metadata) {
      Ok(v) => Ok(v)
      Err(e) => Err(Limit(e))
    }
  } catch {
    e => Err(Encoding(e))
  }
}
