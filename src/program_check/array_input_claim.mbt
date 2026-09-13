///|
// Encode and admit the common array-item proof shape only after the caller
// validates the operation owner, input membership, subject and applicable law.
fn array_input_claim(
  input : ReidentifiedStep,
  subject : String,
  law : String,
  remaining : IdentityBudget,
) -> @wire.ProgramProofClaim raise UnitBuildFailure {
  let input_witness = @wire.program_proof_witness(input.proof)
  guard @wire.unit(input_witness) is Rows else { raise ForeignOwner }
  let input_cid = @wire.cid(input_witness)
  let value = @wire.value(input_witness)
  let emit_proof = fn(w : @encode.Writer) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(w)
      @encode.key(w, "inputs")
      @encode.begin_array(w)
      @encode.string_value(w, input_cid)
      @encode.end_array(w)
      @encode.key(w, "law_id")
      @encode.string_value(w, law)
      @encode.key(w, "semantic_ref")
      @encode.string_value(w, subject)
      @encode.key(w, "unit")
      @encode.string_value(w, "array_items")
      @encode.key(w, "value")
      @encode.number_value(w, value.to_double())
      @encode.key(w, "version")
      @encode.string_value(w, "actql-bound-proof/0.1")
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(remaining)
  emit_proof(hash)
  let proof_cid = identity_finish(remaining, hash)
  let proof_bytes = publication_metadata(emit_proof, remaining)
  let dependencies = [(input_cid, ()), (proof_cid, ())]
  identity_sort(dependencies, remaining)
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    try {
      @encode.begin_object(w)
      @encode.key(w, "dependencies")
      @encode.begin_array(w)
      for (dependency, _) in dependencies {
        @encode.string_value(w, dependency)
      }
      @encode.end_array(w)
      @encode.key(w, "derivation")
      @encode.begin_object(w)
      @encode.key(w, "op")
      @encode.string_value(w, "source")
      @encode.end_object(w)
      @encode.key(w, "law_id")
      @encode.string_value(w, law)
      @encode.key(w, "role")
      @encode.string_value(w, "proven_upper_bound")
      @encode.key(w, "source")
      @encode.begin_object(w)
      @encode.key(w, "kind")
      @encode.string_value(w, "program")
      @encode.key(w, "proof_cid")
      @encode.string_value(w, proof_cid)
      @encode.key(w, "semantic_ref")
      @encode.string_value(w, subject)
      @encode.end_object(w)
      @encode.key(w, "unit")
      @encode.string_value(w, "array_items")
      @encode.key(w, "value")
      @encode.number_value(w, value.to_double())
      @encode.key(w, "version")
      @encode.string_value(w, "actql-bound-witness/0.1")
      if cid is Some(cid) {
        @encode.key(w, "witness_cid")
        @encode.string_value(w, cid)
      }
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(remaining)
  emit(hash, None)
  let cid = identity_finish(remaining, hash)
  let bytes = publication_metadata(w => emit(w, Some(cid)), remaining)
  identity_charge(remaining, bytes.length())
  identity_charge(remaining, proof_bytes.length())
  let witness = match
    @wire.admit(bytes, cid, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  let proof = match
    @wire.bind_program_proof(proof_bytes, witness, {
      max_bytes: proof_bytes.length(),
      max_nodes: proof_bytes.length(),
      max_depth: remaining.depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  proof
}
