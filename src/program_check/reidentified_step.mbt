///|
struct ReidentifiedStep {
  original : @step_bounds.StepBound
  location : UnitOperationSource
  proof : @wire.ProgramProofClaim
  inputs : Array[ReidentifiedStep]
  graph_inputs : Array[ReidentifiedGraphInput]
  external_inputs : Array[@wire.WireWitness]
}

///|
fn reidentified_reference(
  mapping : Map[String, Array[String]],
  reference : String,
) -> String raise UnitBuildFailure {
  match mapping.get(reference) {
    Some([value]) => value
    Some(_) => raise AmbiguousProofInput
    None => raise UnconvertedProofInput
  }
}

///|
fn emit_reidentified_derivation(
  value : @wire.Derivation,
  mapping : Map[String, Array[String]],
  writer : @encode.Writer,
  budget : IdentityBudget,
  operands? : Array[(String, String)] = [],
) -> Unit raise UnitBuildFailure {
  // Resolve every reference through the conversion map: missing dependencies
  // cannot survive as old CIDs. Failure cannot expose the unfinished writer.
  try {
    @encode.begin_object(writer)
    match value {
      SourceValue => {
        @encode.key(writer, "op")
        @encode.string_value(writer, "source")
      }
      Preserve(input) => {
        @encode.key(writer, "input")
        @encode.string_value(writer, reidentified_reference(mapping, input))
        @encode.key(writer, "op")
        @encode.string_value(writer, "preserve")
      }
      Minimum(inputs) => {
        // Minimum's operands are a canonical set, unlike the proof's input
        // occurrences. Reidentification can change both ordering and equality.
        identity_charge(budget, inputs.length())
        let converted : Array[(String, Unit)] = []
        for input in inputs {
          guard mapping.get(input) is Some(values) else {
            raise UnconvertedProofInput
          }
          identity_charge(budget, values.length())
          for value in values {
            converted.push((value, ()))
          }
        }
        identity_sort(converted, budget)
        @encode.key(writer, "inputs")
        @encode.begin_array(writer)
        let mut previous = ""
        for (input, _) in converted {
          if input != previous {
            @encode.string_value(writer, input)
            previous = input
          }
        }
        @encode.end_array(writer)
        @encode.key(writer, "op")
        @encode.string_value(writer, "min")
      }
      Add(left, right) => {
        // StepBound inputs retain data-edge order; proof.inputs is sorted.
        // Equal local CIDs from distinct owners must still select distinct
        // persistent operands, rather than an arbitrary CID-map entry.
        guard operands is [(old_left, new_left), (old_right, new_right)] &&
          old_left == left &&
          old_right == right else {
          raise UnconvertedProofInput
        }
        @encode.key(writer, "left")
        @encode.string_value(writer, new_left)
        @encode.key(writer, "op")
        @encode.string_value(writer, "add")
        @encode.key(writer, "right")
        @encode.string_value(writer, new_right)
      }
      Multiply(input, factor) => {
        @encode.key(writer, "factor")
        @encode.number_value(writer, factor.to_double())
        @encode.key(writer, "input")
        @encode.string_value(writer, reidentified_reference(mapping, input))
        @encode.key(writer, "op")
        @encode.string_value(writer, "multiply")
      }
      Clamp(input, maximum) => {
        if input is Some(input) {
          @encode.key(writer, "input")
          @encode.string_value(writer, reidentified_reference(mapping, input))
        }
        @encode.key(writer, "maximum")
        @encode.number_value(writer, maximum.to_double())
        @encode.key(writer, "op")
        @encode.string_value(writer, "clamp")
      }
      EnforcedCeiling(_) => raise UnconvertedProofInput
    }
    @encode.end_object(writer)
  } catch {
    error => raise ProofConversion(error)
  }
}

///|
// One dependency-ordered conversion step. The enclosing traversal supplies
// converted children; this constructor verifies their exact original owners.
fn reidentify_step(
  unit : BuiltUnit,
  bound : @step_bounds.StepBound,
  inputs : Array[ReidentifiedStep],
  budget : IdentityBudget,
  graph_inputs? : Array[ReidentifiedGraphInput] = [],
) -> ReidentifiedStep raise UnitBuildFailure {
  guard unit_operation_source(
      unit,
      @step_bounds.checked_pipeline(bound),
      @step_bounds.checked_step(bound),
    )
    is Some(location) else {
    raise ForeignOwner
  }
  if inputs.length() != @step_bounds.input_count(bound) - graph_inputs.length() {
    raise UnconvertedProofInput
  }
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, inputs.length())
  identity_charge(remaining, graph_inputs.length())
  let mapping : Map[String, Array[String]] = Map([])
  let operands : Array[(String, String)] = []
  let identities : Array[String] = []
  let original_inputs : Array[String] = []
  let external_inputs : Array[@wire.WireWitness] = []
  let mut step_index = 0
  let mut graph_index = 0
  for i in 0..<@step_bounds.input_count(bound) {
    let (old, new) = match @step_bounds.source_at(bound, i) {
      Some(StepInput(original)) => {
        guard inputs.get(step_index) is Some(converted) &&
          physical_equal(original, converted.original) else {
          raise UnconvertedProofInput
        }
        step_index += 1
        (
          @wire.cid(
            @wire.program_proof_witness(@step_bounds.checked_proof(original)),
          ),
          @wire.cid(@wire.program_proof_witness(converted.proof)),
        )
      }
      Some(GraphInput(original)) => {
        guard graph_inputs.get(graph_index) is Some(converted) &&
          physical_equal(original, converted.original) else {
          raise UnconvertedProofInput
        }
        graph_index += 1
        (
          @wire.cid(@graph_input.bound_witness(original)),
          @wire.cid(converted.witness),
        )
      }
      None => raise UnconvertedProofInput
    }
    identity_charge(remaining, old.length())
    identity_charge(remaining, new.length())
    match mapping.get(old) {
      Some(values) => values.push(new)
      None => mapping[old] = [new]
    }
    operands.push((old, new))
    identities.push(new)
    original_inputs.push(old)
  }
  if @step_bounds.checked_enforcement(bound)
    is Some(SequenceEnforcement(selection)) {
    if !physical_equal(@sequence.checked_pipeline(selection), location.pipeline) ||
      @sequence.checked_step(selection) != location.source_ordinal ||
      @sequence.guard_value(selection, OutputRows) is Some(_) {
      raise UnconvertedProofInput
    }
    let limit = @sequence.host_limit(selection, OutputRows)
    let minimum = @wire.limit_minimum(limit)
    let count = @derivation.minimum_candidate_count(minimum)
    identity_charge(remaining, count)
    for i in 0..<count {
      let node = @derivation.minimum_candidate_at(minimum, i).unwrap().node
      let witness = @wire.claim_at(@wire.limit_claims(limit), node).unwrap()
      // Only the selected Sequence Host leaves are already persistent. Other
      // external sources need their own validated conversion, never CID fallback.
      guard @wire.source(witness) is @wire.HostPolicy(_, _) else {
        raise UnconvertedProofInput
      }
      let cid = @wire.cid(witness)
      identity_charge(remaining, cid.length())
      match mapping.get(cid) {
        Some(values) => values.push(cid)
        None => mapping[cid] = [cid]
      }
      operands.push((cid, cid))
      original_inputs.push(cid)
      identities.push(cid)
      external_inputs.push(witness)
    }
  }
  let original_proof = @step_bounds.checked_proof(bound)
  let count = @wire.program_proof_input_count(original_proof)
  if count != original_inputs.length() {
    raise UnconvertedProofInput
  }
  identity_charge(remaining, count)
  let occurrences : Map[String, Int] = Map([])
  for cid in original_inputs {
    identity_charge(remaining, cid.length())
    occurrences[cid] = occurrences.get(cid).unwrap_or(0) + 1
  }
  for i in 0..<count {
    let cid = @wire.program_proof_input_at(original_proof, i).unwrap()
    identity_charge(remaining, cid.length())
    let n = occurrences.get(cid).unwrap_or(0)
    if n == 0 {
      raise UnconvertedProofInput
    }
    occurrences[cid] = n - 1
  }
  let proof_hash = identity_writer(remaining)
  emit_unit_output_proof(location, bound, identities, proof_hash, remaining)
  let proof_cid = identity_finish(remaining, proof_hash)
  let proof_bytes = publication_metadata(
    w => emit_unit_output_proof(location, bound, identities, w, remaining),
    remaining,
  )
  identity_charge(remaining, identities.length() + 1)
  let dependencies = identities.map(cid => (cid, ()))
  dependencies.push((proof_cid, ()))
  identity_sort(dependencies, remaining)
  let old = @wire.program_proof_witness(@step_bounds.checked_proof(bound))
  let subject = unit_operation_subject(location, remaining)
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    identity_charge(remaining, dependencies.length())
    try {
      @encode.begin_object(w)
      @encode.key(w, "dependencies")
      @encode.begin_array(w)
      let mut previous = ""
      for (value, _) in dependencies {
        if value != previous {
          @encode.string_value(w, value)
          previous = value
        }
      }
      @encode.end_array(w)
      @encode.key(w, "derivation")
      emit_reidentified_derivation(
        @wire.derivation(old),
        mapping,
        w,
        remaining,
        operands~,
      )
      @encode.key(w, "law_id")
      @encode.string_value(w, @law.name(@wire.law(old)))
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
      @encode.string_value(w, proof_unit(old))
      @encode.key(w, "value")
      @encode.number_value(w, @wire.value(old).to_double())
      @encode.key(w, "version")
      @encode.string_value(w, "actql-bound-witness/0.1")
      if cid is Some(cid) {
        @encode.key(w, "witness_cid")
        @encode.string_value(w, cid)
      }
      @encode.end_object(w)
    } catch {
      error => raise ProofConversion(error)
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
  identity_charge(remaining, inputs.length())
  identity_charge(remaining, graph_inputs.length())
  let result = {
    original: bound,
    location,
    proof,
    inputs: inputs.copy(),
    graph_inputs: graph_inputs.copy(),
    external_inputs,
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}
