///|
pub(all) struct DeriveBoundLimits {
  max_input_work : Int
  max_operand_work : Int
  max_reference_work : Int
  metadata : @wire.Limits
}

///|
pub(all) enum DeriveBoundIssue {
  InvalidLimits
  ReferenceWorkLimit
  Application(Issue)
  Encoding(@encode.EncodeFailure)
  Admission(@wire.Issue)
} derive(Debug)

///|
/// An operation application constructed from checked operands. Metadata usage
/// reserves each complete proof/witness artifact once, not each encoding pass.
pub struct DerivedBound {
  bound : StepBound
  metadata_bytes : Int
  metadata_nodes : Int
  reference_work : Int
  work : Int
}

///|
/// Construct an existing operation law without caller-authored proof JSON.
/// Inputs are in data-edge order, including repetitions. This does not select
/// candidate evidence, discharge runtime obligations or authorize execution.
/// max_work bounds the sum of input/operand work, reference work and complete
/// metadata nodes. Each independent limit also remains in force.
pub fn derive_bound(
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  inputs : Array[BoundInput],
  limits : DeriveBoundLimits,
  unit? : @arithmetic.BoundUnit = @arithmetic.Rows,
  bindings? : CountBindings? = None,
  max_work? : Int = 2147483647,
) -> Result[DerivedBound, DeriveBoundIssue] {
  let metadata = limits.metadata
  if max_work < 0 ||
    limits.max_input_work < 0 ||
    limits.max_operand_work < 0 ||
    limits.max_reference_work < 0 ||
    metadata.max_bytes < 0 ||
    metadata.max_nodes < 0 ||
    metadata.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if bindings is Some(bound) && !physical_equal(bound.pipeline, pipeline) {
    return Err(Application(BindingOwnerMismatch))
  }
  guard @pipeline.step_at(pipeline, index) is Some(step) else {
    return Err(Application(MissingStep))
  }
  let (law, rule) = match operation_rule(step, bindings, unit) {
    Ok(v) => v
    Err(e) => return Err(Application(e))
  }
  if rule_output_unit(rule) != unit {
    return Err(Application(LawMismatch))
  }
  let n = inputs.length()
  if !rule_input_count_valid(rule, n) {
    return Err(Application(InputCountMismatch))
  }
  // Reserve a linear pass before copying any caller-owned input array.
  if n > limits.max_reference_work || n > max_work {
    return Err(ReferenceWorkLimit)
  }
  let prepared = match
    prepare_bound_inputs(
      pipeline,
      step,
      rule,
      n,
      i => inputs[i],
      limits.max_input_work,
      limits.max_operand_work,
      None,
      aggregate_work=Some(max_work - n),
    ) {
    Ok(v) => v
    Err(e) => return Err(Application(e))
  }
  let count = match
    calculate_bound_value(
      rule,
      n,
      i => {
        @numeric.read(@wire.value(source_witness(prepared.inputs[i]))).unwrap()
      },
      None,
    ) {
    Ok(v) => v
    Err(e) => return Err(Application(e))
  }
  let application_work = prepared.input_work + prepared.operand_work
  let reference_cap = limits.max_reference_work.min(max_work - application_work)
  let sorted = match sort_bound_references(prepared.ids, reference_cap - n) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  // Reserve dependency construction before hashing either artifact. Its
  // operands were sorted above; insertion of the proof CID needs one pass.
  if n >= reference_cap - n - sorted.1 {
    return Err(ReferenceWorkLimit)
  }
  let reference_work = n + sorted.1 + n + 1
  let metadata_work = max_work - application_work - reference_work
  let subject = subject_ref(pipeline, index).unwrap()
  let emit_proof = fn(
    out : @encode.Writer,
  ) -> Unit raise @encode.EncodeFailure {
    emit_derived_proof(subject, law, unit, count, sorted.0, out)
  }
  try {
    let measured = @encode.measuring_writer(
      metadata.max_bytes,
      metadata.max_nodes.min(metadata_work),
      metadata.max_depth,
    )
    emit_proof(measured)
    let (proof_size, proof_nodes, _) = @encode.finish_measurement_usage(
      measured,
    )
    let hash = @encode.hashing_writer(
      metadata.max_bytes,
      metadata.max_nodes,
      metadata.max_depth,
    )
    emit_proof(hash)
    let proof_cid = "sha256:" + @encode.finish_hash(hash)
    let proof_out = @encode.writer(
      metadata.max_bytes,
      metadata.max_nodes,
      metadata.max_depth,
    )
    emit_proof(proof_out)
    let proof_bytes = @utf8.encode(@encode.finish(proof_out))
    // Dependency sets are unique; proof operands and owned inputs are not.
    let dependencies : Array[String] = []
    let mut inserted = false
    for id in sorted.0 {
      if !inserted && proof_cid <= id {
        dependencies.push(proof_cid)
        inserted = true
      }
      if dependencies.last() != Some(id) {
        dependencies.push(id)
      }
    }
    if !inserted {
      dependencies.push(proof_cid)
    }
    let emit_witness = fn(
      cid : String?,
      out : @encode.Writer,
    ) -> Unit raise @encode.EncodeFailure {
      emit_derived_witness(
        subject,
        law,
        unit,
        count,
        rule,
        prepared.ids,
        proof_cid,
        dependencies,
        cid,
        out,
      )
    }
    let available_bytes = metadata.max_bytes - proof_size
    let available_nodes = (metadata.max_nodes - proof_nodes).min(
      metadata_work - proof_nodes,
    )
    let measure = @encode.measuring_writer(
      available_bytes,
      available_nodes,
      metadata.max_depth,
    )
    emit_witness(Some("sha256:" + "0".repeat(64)), measure)
    let (witness_size, witness_nodes, _) = @encode.finish_measurement_usage(
      measure,
    )
    let hash = @encode.hashing_writer(
      available_bytes,
      available_nodes,
      metadata.max_depth,
    )
    emit_witness(None, hash)
    let witness_cid = "sha256:" + @encode.finish_hash(hash)
    let out = @encode.writer(
      available_bytes,
      available_nodes,
      metadata.max_depth,
    )
    emit_witness(Some(witness_cid), out)
    let witness = match
      @wire.admit(@utf8.encode(@encode.finish(out)), witness_cid, metadata) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    let proof = match @wire.bind_program_proof(proof_bytes, witness, metadata) {
      Ok(v) => v
      Err(e) => return Err(Admission(e))
    }
    Ok({
      bound: {
        pipeline,
        index,
        proof,
        inputs: prepared.inputs,
        input_work: prepared.input_work,
        operand_work: prepared.operand_work,
        bindings,
        join_evidence: None,
        enforcement: None,
      },
      metadata_bytes: proof_size + witness_size,
      metadata_nodes: proof_nodes + witness_nodes,
      reference_work,
      work: application_work + reference_work + proof_nodes + witness_nodes,
    })
  } catch {
    e => Err(Encoding(e))
  }
}

///|
// Iterative merge sorting charges copies and comparisons before each action.
// All strings are admitted, fixed-width CIDs. Repetitions remain in the output.
fn sort_bound_references(
  ids : Array[String],
  maximum : Int,
) -> Result[(Array[String], Int), DeriveBoundIssue] {
  let n = ids.length()
  if n > maximum {
    return Err(ReferenceWorkLimit)
  }
  let mut work = n
  let mut source = ids.copy()
  let mut width = 1
  while width < n {
    let output : Array[String] = []
    let mut start = 0
    while start < n {
      let middle = start + width.min(n - start)
      let end = middle + width.min(n - middle)
      let mut left = start
      let mut right = middle
      while left < middle || right < end {
        let cost = if left < middle && right < end { 2 } else { 1 }
        if cost > maximum - work {
          return Err(ReferenceWorkLimit)
        }
        work += cost
        if right == end || (left < middle && source[left] <= source[right]) {
          output.push(source[left])
          left += 1
        } else {
          output.push(source[right])
          right += 1
        }
      }
      start = end
    }
    source = output
    if width >= n - width {
      break
    }
    width += width
  }
  Ok((source, work))
}
