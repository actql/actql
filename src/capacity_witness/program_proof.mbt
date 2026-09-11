///|
pub(all) enum ProgramProofForm {
  DerivedInputs
  ProgramDependencies(String)
} derive(Eq, Debug)

///|
/// Integrity-bound Program proof claim, not a verified operation or source fact.
struct ProgramProofClaim {
  witness : WireWitness
  form : ProgramProofForm
  inputs : Array[String]
}

///|
/// Bind the two actql-bound-proof/0.1 body forms used by the fixed compiler.
/// Enforced ceilings and other proof domains need their respective owners.
/// This checks identity and assertions, not their truth about an actual Program.
pub fn bind_program_proof(
  bytes : Bytes,
  witness : WireWitness,
  limits : Limits,
) -> Result[ProgramProofClaim, Issue] {
  try {
    if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
      raise Stop(InvalidLimits)
    }
    if bytes.length() > limits.max_bytes {
      raise Stop(BudgetExceeded)
    }
    guard witness.source is Program(semantic_ref, proof_cid) else {
      raise Stop(InvalidWitness)
    }
    if witness.derivation is EnforcedCeiling(_) {
      raise Stop(InvalidWitness)
    }
    if "sha256:" + @sha.hex(bytes) != proof_cid {
      raise Stop(IdentityMismatch)
    }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => raise Stop(BudgetExceeded)
          _ => raise Stop(InvalidWitness)
        }
    }
    let cursor = match
      @decode.admit(node, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_bytes,
        max_total_string_bytes: limits.max_bytes,
      }) {
      Ok(v) => v
      Err(_) => raise Stop(BudgetExceeded)
    }
    let open = get(@decode.open_object(cursor))
    let (object, form, input_name) = if @decode.lookup(
        open, "program_definition_cid",
      )
      is Some(_) {
      let o = get(
        @decode.closed_object(cursor, [
          "version", "unit", "value", "semantic_ref", "law_id", "program_definition_cid",
          "dependencies",
        ]),
      )
      (
        o,
        ProgramDependencies(identity(o, "program_definition_cid")),
        "dependencies",
      )
    } else {
      let o = get(
        @decode.closed_object(cursor, [
          "version", "unit", "value", "semantic_ref", "law_id", "inputs",
        ]),
      )
      (o, DerivedInputs, "inputs")
    }
    if text(object, "version") != "actql-bound-proof/0.1" ||
      text(object, "semantic_ref") != semantic_ref ||
      text(object, "law_id") != @law.name(witness.law) ||
      read_unit(text(object, "unit")) != witness.unit ||
      number(object, "value") != witness.value {
      raise Stop(InvalidWitness)
    }
    let inputs : Array[String] = []
    let declared = get(
      @decode.elements(get(@decode.required(object, input_name))),
    )
    let mut previous = ""
    let expected : Map[String, Bool] = Map([])
    expected[proof_cid] = true
    if form is ProgramDependencies(id) {
      expected[id] = true
    }
    for input in declared {
      let id = get(@decode.text(input))
      // Proof arrays retain sorted repeated operand occurrences; wire dependency
      // sets are unique. These are different representations, not a repair.
      if !valid_cid(id) || id < previous {
        raise Stop(InvalidWitness)
      }
      previous = id
      inputs.push(id)
      expected[id] = true
    }
    if expected.length() != witness.dependencies.length() {
      raise Stop(InvalidWitness)
    }
    for id in witness.dependencies {
      if !expected.contains(id) {
        raise Stop(InvalidWitness)
      }
    }
    try {
      let writer = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_cursor(cursor, writer, false)
      if "sha256:" + @encode.finish_hash(writer) != proof_cid {
        raise Stop(NoncanonicalArtifact)
      }
    } catch {
      Stop(e) => raise Stop(e)
      _ => raise Stop(BudgetExceeded)
    }
    Ok({ witness, form, inputs, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn program_proof_witness(proof : ProgramProofClaim) -> WireWitness {
  proof.witness
}

///|
pub fn program_proof_form(proof : ProgramProofClaim) -> ProgramProofForm {
  proof.form
}

///|
pub fn program_proof_input_count(proof : ProgramProofClaim) -> Int {
  proof.inputs.length()
}

///|
pub fn program_proof_input_at(
  proof : ProgramProofClaim,
  index : Int,
) -> String? {
  proof.inputs.get(index)
}
