///|
struct GroupLimit {
  source : GroupAggregateSource
  selected : @context.GroupArrayLimit
  claim : @wire.LimitClaim
  proofs : Array[GroupInputProof]
}

///|
pub fn group_limit_source(v : GroupLimit) -> GroupAggregateSource {
  v.source
}

///|
pub fn group_limit_selection(v : GroupLimit) -> @context.GroupArrayLimit {
  v.selected
}

///|
pub fn group_limit_claim(v : GroupLimit) -> @wire.LimitClaim {
  v.claim
}

///|
pub fn group_limit_proof_count(v : GroupLimit) -> Int {
  v.proofs.length()
}

///|
pub fn group_limit_proof_at(v : GroupLimit, index : Int) -> GroupInputProof? {
  v.proofs.get(index)
}

///|
fn assemble_group_array_limit(
  units : Array[BuiltUnit],
  source : GroupAggregateSource,
  selected : @context.GroupArrayLimit,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> GroupLimit raise UnitBuildFailure {
  let max_depth = budget.depth
  let host = publication_host(@context.group_array_limit_host(selected), budget)
  let host_bytes = publication_metadata(
    w => @host.emit(host, w) catch { e => raise Encoding(e) },
    budget,
  )
  identity_charge(budget, host_bytes.length())
  let host_witness = match
    @wire.admit(host_bytes, @host.cid(host), {
      max_bytes: host_bytes.length(),
      max_nodes: host_bytes.length(),
      max_depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  let candidates : Array[(String, @wire.WireWitness)] = [
    (@wire.cid(host_witness), host_witness),
  ]
  let proofs : Array[GroupInputProof] = []
  let inputs : Array[ReidentifiedStep] = []
  let count = @context.group_array_limit_candidate_count(selected)
  identity_charge(budget, count)
  let mut non_author = @wire.value(host_witness)
  for candidate in 0..<count {
    let proof = group_input_proof(
      units,
      source,
      selected,
      candidate,
      budget,
      conversion~,
    )
    let witness = @wire.program_proof_witness(proof.proof)
    non_author = Int64::min(non_author, @wire.value(witness))
    candidates.push((@wire.cid(witness), witness))
    inputs.push(proof.input)
    proofs.push(proof)
  }
  let guard_value = @context.group_array_limit_guard(selected)
  if guard_value is Some(value) {
    let witness = emit_group_guard_witness(source, value, budget)
    candidates.push((@wire.cid(witness), witness))
  }
  let claim = assemble_group_limit_claim(
    source,
    candidates,
    inputs,
    guard_value,
    Some(non_author),
    @context.group_array_limit_maximum(selected),
    "array_items",
    budget,
  )
  { source, selected, claim, proofs, }
}

///|
fn assemble_group_limit_claim(
  source : GroupAggregateSource,
  candidates : Array[(String, @wire.WireWitness)],
  inputs : Array[ReidentifiedStep],
  guard_value : Int64?,
  non_author : Int64?,
  maximum : Int64,
  unit : String,
  budget : IdentityBudget,
) -> @wire.LimitClaim raise UnitBuildFailure {
  let subject = group_aggregate_subject_with_budget(source, budget)
  assemble_aggregate_limit_claim(
    subject, candidates, inputs, guard_value, non_author, maximum, unit, budget,
  )
}

///|
fn assemble_aggregate_limit_claim(
  subject : String,
  candidates : Array[(String, @wire.WireWitness)],
  inputs : Array[ReidentifiedStep],
  guard_value : Int64?,
  non_author : Int64?,
  maximum : Int64,
  unit : String,
  budget : IdentityBudget,
  preserve_candidate_occurrences? : Bool = false,
) -> @wire.LimitClaim raise UnitBuildFailure {
  let max_depth = budget.depth
  identity_sort(candidates, budget)
  let input_limits : Array[(Bytes, String)] = []
  let witnesses = publication_proof_claims(inputs, budget, limits=input_limits)
  let seen : Map[String, Bool] = Map([])
  for witness in witnesses {
    identity_charge(budget, @wire.cid(witness).length())
    seen[@wire.cid(witness)] = true
  }
  for (cid, witness) in candidates {
    identity_charge(budget, cid.length())
    if !seen.contains(cid) {
      seen[cid] = true
      witnesses.push(witness)
    }
  }
  identity_charge(budget, witnesses.length())
  identity_charge(budget, input_limits.length())
  let mixed = match
    @wire.check_mixed_claims(witnesses, input_limits, {
      max_entities: witnesses.length() + input_limits.length(),
      max_references: budget.work / 3,
      max_bytes: budget.work / 3,
      max_nodes: budget.work / 3,
      max_depth,
    }) {
    Ok(v) => v
    Err(e) => raise PublicationMixed(e)
  }
  let (references, bytes, nodes) = @wire.mixed_usage(mixed)
  identity_charge(budget, references)
  identity_charge(budget, bytes)
  identity_charge(budget, nodes)
  let binding = match guard_value {
    None => "absent"
    Some(value) =>
      if non_author is None || value < non_author.unwrap() {
        "binding"
      } else {
        "currently_non_binding"
      }
  }
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    identity_charge(budget, candidates.length())
    try {
      @encode.begin_object(w)
      @encode.key(w, "author_guard_binding")
      @encode.string_value(w, binding)
      @encode.key(w, "breach")
      @encode.string_value(w, "fail")
      @encode.key(w, "candidates")
      @encode.begin_array(w)
      let mut previous = ""
      for (key, witness) in candidates {
        if preserve_candidate_occurrences || key != previous {
          @wire.emit(witness, w)
          previous = key
        }
      }
      @encode.end_array(w)
      @encode.key(w, "effective_max")
      @encode.number_value(w, maximum.to_double())
      @encode.key(w, "enforcement")
      @encode.string_value(w, "engine_atomic")
      if cid is Some(cid) {
        @encode.key(w, "resolved_limit_cid")
        @encode.string_value(w, cid)
      }
      @encode.key(w, "subject_ref")
      @encode.string_value(w, subject)
      @encode.key(w, "unit")
      @encode.string_value(w, unit)
      @encode.key(w, "version")
      @encode.string_value(w, "actql-resolved-limit/0.1")
      @encode.end_object(w)
    } catch {
      e => raise Encoding(e)
    }
  }
  let hash = identity_writer(budget)
  emit(hash, None)
  let cid = identity_finish(budget, hash)
  let bytes = publication_metadata(w => emit(w, Some(cid)), budget)
  identity_charge(budget, bytes.length())
  let claim = match
    @wire.admit_limit(bytes, cid, @wire.mixed_arithmetic(mixed), {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth,
      max_candidates: candidates.length(),
    }) {
    Ok(v) => v
    Err(e) => raise PublicationWire(e)
  }
  claim
}
