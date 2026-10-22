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
  resolve_values_wire_limit_metered(
    cells,
    requirement_index,
    payload,
    metadata,
    None,
  )
}

///|
fn resolve_values_wire_limit_metered(
  cells : ProgramOperationCells,
  requirement_index : Int,
  payload : @wire.Limits,
  metadata : @wire.LimitLimits,
  meter : ValuesMetadataBudget?,
) -> Result[ValuesWireLimit, ValuesWireResolutionIssue] {
  let owner = match bound_values_resource_owner(cells, requirement_index) {
    Ok(value) => value
    Err(issue) => return Err(Measurement(issue))
  }
  resolve_values_resource_wire_limit(owner, payload, metadata, meter)
}

///|
fn resolve_values_resource_wire_limit(
  owner : ValuesResourceOwner,
  payload : @wire.Limits,
  metadata : @wire.LimitLimits,
  meter : ValuesMetadataBudget?,
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
    measure_values_resource_rows(
      owner,
      payload.max_bytes,
      payload.max_nodes,
      payload.max_depth,
    ) {
    Ok(v) => v
    Err(e) => return Err(Measurement(e))
  }
  if meter is Some(meter) {
    if bytes > meter.bytes || nodes > meter.nodes {
      return Err(Encoding(@encode.OutputLimit))
    }
    meter.bytes -= bytes
    meter.nodes -= nodes
  }
  // The measurement retains the exact resource occurrence before proof emission.
  let subject = "checked-step:" + values_resource_step(owner).to_string()
  let proof = match
    prepare_values_measurement_proof(subject, bytes, metadata, meter) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The claim was derived from this measurement, rather than supplied by a
  // caller; retain that exact ownership without measuring the payload twice.
  let bound : ValuesWireBound = { owner, proof, bytes, nodes, depth, }
  match create_values_wire_limit_metered(bound, metadata, meter) {
    Ok(v) => Ok(v)
    Err(e) => Err(Limit(e))
  }
}

///|
// The original measurement owner applies the law before this integrity-only
// construction. Reserve the same two complete artifacts, with fixed-width CID
// placeholders, then hash each original preimage once without a JSON round trip.
fn prepare_values_measurement_proof(
  subject : String,
  bytes : Int,
  metadata : @wire.LimitLimits,
  meter : ValuesMetadataBudget?,
) -> Result[@wire.ProgramProofClaim, ValuesWireResolutionIssue] {
  try {
    reserve_values_metadata(meter, metadata, out => {
      emit_values_measurement_proof(subject, bytes, out)
    })
    reserve_values_metadata(meter, metadata, out => {
      emit_values_measurement_witness(
        subject,
        bytes,
        values_metadata_cid,
        Some(values_metadata_cid),
        out,
      )
    })
    match
      @wire.create_program_source(
        subject,
        bytes.to_int64(),
        @derivation.Bytes,
        @law.admit("actql.bound.values-wire").unwrap(),
        {
          max_bytes: metadata.max_bytes,
          max_nodes: metadata.max_nodes,
          max_depth: metadata.max_depth,
        },
      ) {
      Ok(value) => Ok(value)
      Err(@wire.BudgetExceeded) => Err(Encoding(@encode.OutputLimit))
      Err(issue) => Err(Proof(issue))
    }
  } catch {
    issue => Err(Encoding(issue))
  }
}
