///|
struct SequenceLimit {
  source : UnitOperationSource
  selected : @context.SequenceLimitsCheck
  matches : @wire.LimitClaim
  output : @wire.LimitClaim
}

///|
pub fn sequence_limit_source(v : SequenceLimit) -> UnitOperationSource {
  v.source
}

///|
pub fn sequence_limit_selection(
  v : SequenceLimit,
) -> @context.SequenceLimitsCheck {
  v.selected
}

///|
pub fn sequence_limit_claim(
  v : SequenceLimit,
  scope : @sequence.Scope,
) -> @wire.LimitClaim {
  if scope == @sequence.MatchesPerKey {
    v.matches
  } else {
    v.output
  }
}

///|
// Preserve original Host occurrences and insert the Unit guard in CID order.
fn reidentify_sequence_limit(
  original : @wire.LimitClaim,
  subject : String,
  unit : String,
  budget : IdentityBudget,
  guard_witness? : @wire.WireWitness? = None,
) -> @wire.LimitClaim raise UnitBuildFailure {
  let original_arithmetic = @wire.limit_claims(original)
  let minimum = @wire.limit_minimum(original)
  let count = @derivation.minimum_candidate_count(minimum)
  let arithmetic = match guard_witness {
    None => original_arithmetic
    Some(witness) => {
      identity_charge(budget, count + 1)
      let witnesses : Array[@wire.WireWitness] = []
      let seen : Map[String, Bool] = Map([])
      for i in 0..<count {
        let node = @derivation.minimum_candidate_at(minimum, i).unwrap().node
        let candidate = @wire.claim_at(original_arithmetic, node).unwrap()
        let cid = @wire.cid(candidate)
        identity_charge(budget, cid.length())
        if !seen.contains(cid) {
          seen[cid] = true
          witnesses.push(candidate)
        }
      }
      witnesses.push(witness)
      let claims = @wire.check_arithmetic_claims(witnesses, {
        max_witnesses: witnesses.length(),
        max_references: budget.work,
      })
      match claims {
        Ok(v) => {
          identity_charge(budget, @wire.claim_reference_count(v))
          v
        }
        Err(ClosureBudgetExceeded) => raise BudgetExceeded
        Err(_) => raise ForeignOwner
      }
    }
  }
  let host_max = @derivation.minimum_value(minimum)
  let guard_max = guard_witness.map(v => @wire.value(v))
  let maximum = guard_max.map(v => Int64::min(v, host_max)).unwrap_or(host_max)
  let binding = match guard_max {
    None => "absent"
    Some(v) => if v < host_max { "binding" } else { "currently_non_binding" }
  }
  identity_charge(budget, subject.length())
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    identity_charge(
      budget,
      count + (if guard_witness is Some(_) { 1 } else { 0 }),
    )
    try {
      @encode.begin_object(w)
      @encode.key(w, "author_guard_binding")
      @encode.string_value(w, binding)
      @encode.key(w, "breach")
      @encode.string_value(w, "fail")
      @encode.key(w, "candidates")
      @encode.begin_array(w)
      let mut inserted = false
      for i in 0..<count {
        let candidate = @derivation.minimum_candidate_at(minimum, i).unwrap()
        let host = @wire.claim_at(original_arithmetic, candidate.node).unwrap()
        if guard_witness is Some(authored) &&
          !inserted &&
          @wire.cid(authored) < @wire.cid(host) {
          @wire.emit(authored, w)
          inserted = true
        }
        @wire.emit(host, w)
      }
      if guard_witness is Some(witness) && !inserted {
        @wire.emit(witness, w)
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
  match
    @wire.admit_limit(bytes, cid, arithmetic, {
      max_bytes: bytes.length(),
      max_nodes: bytes.length(),
      max_depth: budget.depth,
      max_candidates: count + (if guard_witness is Some(_) { 1 } else { 0 }),
    }) {
    Ok(value) => value
    Err(e) => raise PublicationWire(e)
  }
}

///|
fn prepare_program_sequence_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> Array[Array[SequenceLimit]] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let identity = @context.expression_closure_identity(
    @context.operation_requirements_expressions(
      @context.operation_resolution_requirements(
        @context.operation_closure_index(closure),
      ),
    ),
  )
  for stage, unit in units {
    identity_charge(remaining, 1)
    guard @context.program_identity_stage_at(identity, stage) is Some(expected) &&
      physical_equal(expected, unit.source) else {
      raise ForeignOwner
    }
  }
  let seen : Map[(Int, Int), Bool] = Map([])
  for i in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(SequenceLimits(selected))) else {
      continue
    }
    let site = selected.site
    guard units.get(site.stage) is Some(unit) else { raise ForeignOwner }
    if !physical_equal(unit.pipeline, site.pipeline) {
      continue
    }
    let key = (site.stage, site.step)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    guard unit_operation_source(unit, site.pipeline, site.step) is Some(source) &&
      physical_equal(
        @sequence.checked_pipeline(selected.limits),
        source.pipeline,
      ) &&
      @sequence.checked_step(selected.limits) == source.source_ordinal else {
      raise ForeignOwner
    }
    let subject = unit_operation_subject(source, remaining) + "/sequence/"
    let matches = reidentify_sequence_limit(
      @sequence.host_limit(selected.limits, MatchesPerKey),
      subject + "matches-per-key",
      "matches_per_key",
      remaining,
      guard_witness=sequence_guard_witness(
        source,
        selected.limits,
        MatchesPerKey,
        remaining,
      ),
    )
    let output = reidentify_sequence_limit(
      @sequence.host_limit(selected.limits, OutputRows),
      subject + "output",
      "rows",
      remaining,
      guard_witness=sequence_guard_witness(
        source,
        selected.limits,
        OutputRows,
        remaining,
      ),
    )
    identity_charge(remaining, 1)
    result[site.stage].push({ source, selected, matches, output, })
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
fn sequence_guard_witness(
  source : UnitOperationSource,
  selected : @sequence.SequenceLimits,
  scope : @sequence.Scope,
  budget : IdentityBudget,
) -> @wire.WireWitness? raise UnitBuildFailure {
  guard @sequence.guard_value(selected, scope) is Some(value) else {
    return None
  }
  let (field, law, unit) = match scope {
    MatchesPerKey =>
      ("max_matches_per_key", "actql.guard.sequence-matches", "matches_per_key")
    OutputRows => ("max_output_rows", "actql.guard.sequence-output", "rows")
  }
  let path = "$.steps[" +
    source.source_ordinal.to_string() +
    "].sequence." +
    field
  identity_charge(budget, path.length())
  Some(
    emit_unit_guard_witness(
      source.unit_definition_cid,
      path,
      law,
      unit,
      value,
      budget,
    ),
  )
}

///|
pub fn unit_sequence_limit_count(program : CheckedProgram, stage : Int) -> Int? {
  program.sequence_limits.get(stage).map(v => v.length())
}

///|
pub fn unit_sequence_limit_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> SequenceLimit? {
  program.sequence_limits.get(stage).bind(v => v.get(index))
}
