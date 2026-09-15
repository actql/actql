///|
pub(all) enum ValuesRowLimitIssue {
  InvalidLimits
  BudgetExceeded
  InvalidOwner
  MissingCeiling
  Encoding(@encode.EncodeFailure)
  Admission(@wire.Issue)
  Application(@step_bounds.Issue)
  Host(@host.Issue)
  Arithmetic(@wire.ClosureIssue)
} derive(Debug)

///|
/// Row-count selection shares the exact operation and policy of the wire limit.
/// This is a selected enforcement requirement, not a successful enforcement.
pub struct ValuesRowLimit {
  wire : ValuesWireLimit
  rows : @step_bounds.StepBound
  host : @host.Witness
  limit : @wire.LimitClaim
}

///|
pub fn resolve_values_row_limit(
  wire : ValuesWireLimit,
  limits : @wire.LimitLimits,
) -> Result[ValuesRowLimit, ValuesRowLimitIssue] {
  resolve_values_row_limit_metered(wire, limits, None)
}

///|
fn resolve_values_row_limit_metered(
  wire : ValuesWireLimit,
  limits : @wire.LimitLimits,
  meter : ValuesMetadataBudget?,
) -> Result[ValuesRowLimit, ValuesRowLimitIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_candidates < 0 {
    return Err(InvalidLimits)
  }
  if limits.max_candidates < 2 {
    return Err(BudgetExceeded)
  }
  let site = wire.bound.site
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(InvalidOwner)
  }
  guard step.operation is @pipeline.Values(_) else { return Err(InvalidOwner) }
  guard @policy.ceiling(wire.policy, "max_relation_output_rows")
    is Some(ceiling) else {
    return Err(MissingCeiling)
  }
  let subject = "checked-step:" + site.step.to_string()
  let metadata : @wire.Limits = {
    max_bytes: limits.max_bytes,
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
  }
  fn writer(hash : Bool) -> @encode.Writer raise @encode.EncodeFailure {
    if hash {
      @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
    } else {
      @encode.writer(limits.max_bytes, limits.max_nodes, limits.max_depth)
    }
  }
  let rows = match
    prepare_values_row_bound_metered(site.pipeline, site.step, limits, meter) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let witness = @wire.program_proof_witness(@step_bounds.checked_proof(rows))
  let count = @wire.value(witness)
  try {
    let host = match
      @host.create(ceiling, {
        max_bytes: values_metadata_bytes(meter, limits),
        max_nodes: values_metadata_nodes(meter, limits),
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) => return Err(Host(e))
    }
    reserve_values_metadata(meter, limits, out => @host.emit(host, out))
    let out = writer(false)
    @host.emit(host, out)
    let host_wire = match
      @wire.admit(
        @wire_utf8.encode(@encode.finish(out)),
        @host.cid(host),
        metadata,
      ) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    let candidates = if @wire.cid(witness) < @wire.cid(host_wire) {
      [witness, host_wire]
    } else {
      [host_wire, witness]
    }
    let claims = match
      @wire.check_arithmetic_claims(candidates, {
        max_witnesses: 2,
        max_references: limits.max_nodes,
      }) {
      Ok(v) => v
      Err(e) => return Err(Arithmetic(e))
    }
    fn emit_limit(
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
      for candidate in candidates {
        @wire.emit(candidate, out)
      }
      @encode.end_array(out)
      @encode.key(out, "effective_max")
      let ceiling_value = @policy.ceiling_value(ceiling)
      @encode.number_value(
        out,
        if count < ceiling_value {
          count.to_double()
        } else {
          ceiling_value.to_double()
        },
      )
      @encode.key(out, "enforcement")
      @encode.string_value(out, "engine_atomic")
      if cid is Some(cid) {
        @encode.key(out, "resolved_limit_cid")
        @encode.string_value(out, cid)
      }
      @encode.key(out, "subject_ref")
      @encode.string_value(out, "values:" + subject + ":rows")
      @encode.key(out, "unit")
      @encode.string_value(out, "rows")
      @encode.key(out, "version")
      @encode.string_value(out, "actql-resolved-limit/0.1")
      @encode.end_object(out)
    }
    reserve_values_metadata(meter, limits, out => {
      emit_limit(Some(values_metadata_cid), out)
    })
    let hash = writer(true)
    emit_limit(None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let out = writer(false)
    emit_limit(Some(cid), out)
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
    Ok({ wire, rows, host, limit, })
  } catch {
    e => Err(Encoding(e))
  }
}
