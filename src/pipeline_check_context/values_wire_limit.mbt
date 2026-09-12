///|
pub(all) enum ValuesWireLimitIssue {
  Encoding(@encode.EncodeFailure)
  Arithmetic(@wire.ClosureIssue)
  Admission(@wire.Issue)
} derive(Debug)

///|
/// A limit for the complete execution /rows wire value, not nested cells,
/// Artifact output or physical memory. The selected policy and applied proof
/// remain attached to the same Program owner.
pub struct ValuesWireLimit {
  bound : ValuesWireBound
  policy : @policy.Policy
  limit : @wire.LimitClaim
}

///|
fn emit_values_wire_limit(
  bound : ValuesWireBound,
  subject : String,
  cid : String?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "author_guard_binding")
  @encode.string_value(out, "absent")
  @encode.key(out, "breach")
  @encode.string_value(out, "fail")
  @encode.key(out, "candidates")
  @encode.begin_array(out)
  @wire.emit(@wire.program_proof_witness(bound.proof), out)
  @encode.end_array(out)
  @encode.key(out, "effective_max")
  @encode.number_value(out, bound.bytes.to_double())
  @encode.key(out, "enforcement")
  @encode.string_value(out, "engine_atomic")
  if cid is Some(cid) {
    @encode.key(out, "resolved_limit_cid")
    @encode.string_value(out, cid)
  }
  @encode.key(out, "subject_ref")
  @encode.string_value(out, subject)
  @encode.key(out, "unit")
  @encode.string_value(out, "bytes")
  @encode.key(out, "version")
  @encode.string_value(out, "actql-resolved-limit/0.1")
  @encode.end_object(out)
}

///|
/// Select the exact Program-proven /rows wire bound. The fixed values grammar
/// has no authored byte guard, and no field in the admitted fixed Host capacity
/// policy governs this whole-payload scope. Artifact/nest ceilings do not apply
/// merely because their units are bytes; their own scopes remain separate.
/// Limits bound each metadata encoding/admission, not the payload or the total
/// Program preparation budget. This does not close other values requirements.
pub fn create_values_wire_limit(
  bound : ValuesWireBound,
  limits : @wire.LimitLimits,
) -> Result[ValuesWireLimit, ValuesWireLimitIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_candidates < 0 {
    return Err(Admission(@wire.InvalidLimits))
  }
  if limits.max_candidates < 1 {
    return Err(Admission(@wire.BudgetExceeded))
  }
  let requirements = bound.cells.queries.ranges.fills.frames.scalars.orders.requirements
  let selected = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected
  let policy = @environment.capacity_policy(selected.capacity)
  let subject = "values:checked-step:" + bound.site.step.to_string() + ":wire"
  let claims = match
    @wire.check_arithmetic_claims([@wire.program_proof_witness(bound.proof)], {
      max_witnesses: 1,
      max_references: limits.max_nodes,
    }) {
    Ok(v) => v
    Err(e) => return Err(Arithmetic(e))
  }
  try {
    let hash = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_values_wire_limit(bound, subject, None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let out = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_values_wire_limit(bound, subject, Some(cid), out)
    let limit = match
      @wire.admit_limit(
        @wire_utf8.encode(@encode.finish(out)),
        cid,
        claims,
        limits,
      ) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    Ok({ bound, policy, limit, })
  } catch {
    error => Err(Encoding(error))
  }
}
