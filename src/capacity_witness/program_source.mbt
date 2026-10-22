///|
/// Construct the existing empty-input Program proof and its source witness.
/// This establishes canonical integrity only, not the law's application to an
/// actual Program, a checked occurrence, permission or physical enforcement.
/// Both complete artifacts must fit the supplied metadata limits.
pub fn create_program_source(
  semantic_ref : String,
  value : Int64,
  unit : @arithmetic.BoundUnit,
  law : @law.RegisteredLaw,
  limits : Limits,
) -> Result[ProgramProofClaim, Issue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if semantic_ref.is_empty() || value < 0L || value > 9007199254740991L {
    return Err(InvalidWitness)
  }
  try {
    let proof = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_program_source_proof(semantic_ref, value, unit, law, proof)
    let proof_cid = "sha256:" + @encode.finish_hash(proof)
    let pending : WireWitness = {
      body: ProgramSourceValue,
      cid: "",
      source: Program(semantic_ref, proof_cid),
      law,
      unit,
      role: @arithmetic.ProvenUpperBound,
      value,
      derivation: SourceValue,
      dependencies: [proof_cid],
    }
    let witness = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_program_source_value(pending, witness, false)
    let (digest, bytes, nodes, _) = @encode.finish_hash_metrics(witness)
    // The closed witness's complete identity adds 88 ASCII bytes and one
    // scalar node; it introduces no container or additional peak depth.
    if bytes > limits.max_bytes - 88 || nodes >= limits.max_nodes {
      return Err(BudgetExceeded)
    }
    Ok({
      witness: { ..pending, cid: "sha256:" + digest, },
      form: DerivedInputs,
      inputs: [],
    })
  } catch {
    _ => Err(BudgetExceeded)
  }
}

///|
fn emit_program_source_proof(
  subject : String,
  value : Int64,
  unit : @arithmetic.BoundUnit,
  law : @law.RegisteredLaw,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "inputs")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "law_id")
  @encode.string_value(writer, @law.name(law))
  @encode.key(writer, "semantic_ref")
  @encode.string_value(writer, subject)
  @encode.key(writer, "unit")
  @encode.string_value(writer, host_source_unit_text(unit))
  @encode.key(writer, "value")
  @encode.number_value(writer, value.to_double())
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-bound-proof/0.1")
  @encode.end_object(writer)
}

///|
fn emit_program_source_value(
  witness : WireWitness,
  writer : @encode.Writer,
  include_identity : Bool,
) -> Unit raise @encode.EncodeFailure {
  let (subject, proof_cid) = match witness.source {
    Program(subject, proof_cid) => (subject, proof_cid)
    _ => raise @encode.OutputLimit
  }
  @encode.begin_object(writer)
  @encode.key(writer, "dependencies")
  @encode.begin_array(writer)
  @encode.string_value(writer, proof_cid)
  @encode.end_array(writer)
  @encode.key(writer, "derivation")
  @encode.begin_object(writer)
  @encode.key(writer, "op")
  @encode.string_value(writer, "source")
  @encode.end_object(writer)
  @encode.key(writer, "law_id")
  @encode.string_value(writer, @law.name(witness.law))
  @encode.key(writer, "role")
  @encode.string_value(writer, "proven_upper_bound")
  @encode.key(writer, "source")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "program")
  @encode.key(writer, "proof_cid")
  @encode.string_value(writer, proof_cid)
  @encode.key(writer, "semantic_ref")
  @encode.string_value(writer, subject)
  @encode.end_object(writer)
  @encode.key(writer, "unit")
  @encode.string_value(writer, host_source_unit_text(witness.unit))
  @encode.key(writer, "value")
  @encode.number_value(writer, witness.value.to_double())
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-bound-witness/0.1")
  if include_identity {
    @encode.key(writer, "witness_cid")
    @encode.string_value(writer, witness.cid)
  }
  @encode.end_object(writer)
}
