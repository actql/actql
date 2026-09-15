///|
/// Exact count evidence for an already checked values operation. This proves
/// row cardinality, not cell admission or successful runtime enforcement.
pub struct ValuesRowBound {
  bound : @step_bounds.StepBound
  metadata_bytes : Int
  metadata_nodes : Int
}

///|
/// Construct the necessary count proof without caller-authored proof JSON.
/// Limits bound the sum of the proof and complete witness artifacts. Each
/// artifact is reserved once, including its embedded dependency references.
pub fn prepare_values_row_bound(
  pipeline : @pipeline.CheckedPipeline,
  step_index : Int,
  limits : @wire.Limits,
) -> Result[ValuesRowBound, ValuesRowLimitIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  guard @pipeline.step_at(pipeline, step_index) is Some(step) &&
    step.operation is @pipeline.Values(_) else {
    return Err(InvalidOwner)
  }
  match
    @step_bounds.derive_bound(pipeline, step_index, [], {
      max_input_work: 0,
      max_operand_work: 0,
      // No input sorting: only the proof's own dependency is emitted. Its
      // visit is already covered by complete-artifact node accounting here.
      max_reference_work: 1,
      metadata: limits,
    }) {
    Ok(result) =>
      Ok({
        bound: result.bound,
        metadata_bytes: result.metadata_bytes,
        metadata_nodes: result.metadata_nodes,
      })
    Err(@step_bounds.InvalidLimits) => Err(InvalidLimits)
    Err(@step_bounds.ReferenceWorkLimit) => Err(BudgetExceeded)
    Err(@step_bounds.Application(e)) => Err(Application(e))
    Err(@step_bounds.Encoding(e)) => Err(Encoding(e))
    Err(@step_bounds.Admission(e)) => Err(Admission(e))
  }
}

///|
fn prepare_values_row_bound_metered(
  pipeline : @pipeline.CheckedPipeline,
  step_index : Int,
  limits : @wire.LimitLimits,
  meter : ValuesMetadataBudget?,
) -> Result[@step_bounds.StepBound, ValuesRowLimitIssue] {
  guard @pipeline.step_at(pipeline, step_index) is Some(step) &&
    step.operation is @pipeline.Values(values) else {
    return Err(InvalidOwner)
  }
  let count = @values.row_count(values)
  let subject = "checked-step:" + step_index.to_string()
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
  try {
    reserve_values_metadata(meter, limits, out => {
      emit_values_measurement_proof(
        subject,
        count,
        out,
        law="actql.bound.values",
        unit="rows",
      )
    })
    let hash = writer(true)
    emit_values_measurement_proof(
      subject,
      count,
      hash,
      law="actql.bound.values",
      unit="rows",
    )
    let proof_cid = "sha256:" + @encode.finish_hash(hash)
    let out = writer(false)
    emit_values_measurement_proof(
      subject,
      count,
      out,
      law="actql.bound.values",
      unit="rows",
    )
    let proof_bytes = @wire_utf8.encode(@encode.finish(out))
    reserve_values_metadata(meter, limits, out => {
      emit_values_measurement_witness(
        subject,
        count,
        proof_cid,
        Some(values_metadata_cid),
        out,
        law="actql.bound.values",
        unit="rows",
      )
    })
    let hash = writer(true)
    emit_values_measurement_witness(
      subject,
      count,
      proof_cid,
      None,
      hash,
      law="actql.bound.values",
      unit="rows",
    )
    let witness_cid = "sha256:" + @encode.finish_hash(hash)
    let out = writer(false)
    emit_values_measurement_witness(
      subject,
      count,
      proof_cid,
      Some(witness_cid),
      out,
      law="actql.bound.values",
      unit="rows",
    )
    let witness = match
      @wire.admit(@wire_utf8.encode(@encode.finish(out)), witness_cid, metadata) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    let proof = match @wire.bind_program_proof(proof_bytes, witness, metadata) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    match @step_bounds.check(pipeline, step_index, proof) {
      Ok(v) => Ok(v)
      Err(e) => Err(Application(e))
    }
  } catch {
    e => Err(Encoding(e))
  }
}
