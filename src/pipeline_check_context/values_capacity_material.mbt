///|
priv struct ValuesCapacityMaterial {
  material : CapacityMaterial
  // Authored step -> unchanged or appended claim coordinate in this material.
  slots : Array[Int?]
  bounds : Array[@step_bounds.StepBound?]
  work : Int
  metadata_bytes : Int
  metadata_nodes : Int
}

///|
pub enum ValuesCapacityIssue {
  InvalidLimits
  BudgetExceeded
  Count(Int, ValuesRowLimitIssue)
  Extension(@wire.ProgramExtensionIssue)
}

///|
priv suberror ValuesCapacityStop {
  ValuesCapacityStop(ValuesCapacityIssue)
}

///|
// Prepare one definition, before expanding its imported occurrences. A supplied
// count is reused only after application to the actual checked operation. Its
// body may be shared; this does not establish a shared producer occurrence.
fn derive_values_capacity_material(
  pipeline : @pipeline.CheckedPipeline,
  original : CapacityMaterial,
  max_work : Int,
  metadata : @wire.Limits,
) -> Result[ValuesCapacityMaterial, ValuesCapacityIssue] {
  if max_work < 0 ||
    metadata.max_bytes < 0 ||
    metadata.max_nodes < 0 ||
    metadata.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  fn spend(n : Int) -> Unit raise ValuesCapacityStop {
    if n > remaining {
      raise ValuesCapacityStop(BudgetExceeded)
    }
    remaining -= n
  }
  try {
    let claims = @host.source_claims(original.sources)
    let arithmetic = @wire.program_claim_arithmetic(claims)
    let count = @wire.claim_count(arithmetic)
    let steps = @pipeline.step_count(pipeline)
    spend(count)
    spend(steps)
    let slots : Array[Int?] = Array::make(steps, None)
    let bounds : Array[@step_bounds.StepBound?] = Array::make(steps, None)
    let by_subject : Map[String, Array[(Int, @wire.ProgramProofClaim)]] = Map([])
    let mut prior_proofs = 0
    for index in 0..<count {
      if @wire.program_claim_proof_at(claims, index) is Some(proof) {
        prior_proofs += 1
        let witness = @wire.program_proof_witness(proof)
        let law = @law.name(@wire.law(witness))
        spend(law.length())
        if law == "actql.bound.values" &&
          @wire.source(witness) is @wire.Program(subject, _) {
          spend(subject.length())
          match by_subject.get(subject) {
            Some(entries) => entries.push((index, proof))
            None => by_subject[subject] = [(index, proof)]
          }
        }
      }
    }
    let added : Array[@wire.ProgramProofClaim] = []
    let mut bytes = 0
    let mut nodes = 0
    for step in 0..<steps {
      if @pipeline.step_at(pipeline, step).unwrap().operation
        is @pipeline.Values(_) {
        let subject = "checked-step:" + step.to_string()
        spend(subject.length())
        if by_subject.get(subject) is Some(entries) {
          for (index, proof) in entries {
            spend(1)
            // A table may also retain an imported producer's proof with this
            // local ordinal. Only reuse applicable evidence; keep every other
            // supplied record for the later owner-aware application checks.
            match @step_bounds.check(pipeline, step, proof) {
              Ok(bound) => {
                slots[step] = Some(index)
                bounds[step] = Some(bound)
              }
              Err(_) => ()
            }
          }
        }
        if slots[step] is None {
          // Metadata nodes also bound construction work; reserve before hashing.
          let generated = match
            prepare_values_row_bound(pipeline, step, {
              max_bytes: metadata.max_bytes - bytes,
              max_nodes: Int::min(metadata.max_nodes - nodes, remaining),
              max_depth: metadata.max_depth,
            }) {
            Ok(value) => value
            Err(issue) => raise ValuesCapacityStop(Count(step, issue))
          }
          spend(generated.metadata_nodes)
          bytes += generated.metadata_bytes
          nodes += generated.metadata_nodes
          slots[step] = Some(count + added.length())
          bounds[step] = Some(generated.bound)
          added.push(@step_bounds.checked_proof(generated.bound))
        }
      }
    }
    let material = if added.is_empty() {
      original
    } else {
      // Extension rechecks the complete graph, not only the new leaves. Reserve
      // every retained witness, proof, limit and reference before that pass.
      let limits = match @wire.program_claim_mixed(claims) {
        Some(mixed) => @wire.mixed_limit_count(mixed)
        None => 0
      }
      spend(count)
      spend(prior_proofs)
      spend(limits)
      spend(added.length())
      spend(added.length())
      let references = @wire.program_claim_reference_count(claims)
      spend(references)
      // A values source proof adds one witness dependency and no input edges.
      spend(added.length())
      let sources = match
        @host.extend_program_sources(original.sources, added, {
          max_witnesses: count + prior_proofs + limits + added.length() * 2,
          max_references: references + added.length(),
        }) {
        Ok(value) => value
        Err(issue) => raise ValuesCapacityStop(Extension(issue))
      }
      { ..original, sources, }
    }
    Ok({
      material,
      slots,
      bounds,
      work: max_work - remaining,
      metadata_bytes: bytes,
      metadata_nodes: nodes,
    })
  } catch {
    ValuesCapacityStop(issue) => Err(issue)
  }
}
