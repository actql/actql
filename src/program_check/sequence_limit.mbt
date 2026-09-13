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
// Only Host-only claims admitted by the owned sequence consumer reach this
// conversion. Host witness bodies and repeated candidate occurrences survive.
fn reidentify_sequence_limit(
  original : @wire.LimitClaim,
  subject : String,
  unit : String,
  budget : IdentityBudget,
) -> @wire.LimitClaim raise UnitBuildFailure {
  let arithmetic = @wire.limit_claims(original)
  let minimum = @wire.limit_minimum(original)
  let count = @derivation.minimum_candidate_count(minimum)
  identity_charge(budget, subject.length())
  let emit = fn(
    w : @encode.Writer,
    cid : String?,
  ) -> Unit raise UnitBuildFailure {
    identity_charge(budget, count)
    try {
      @encode.begin_object(w)
      @encode.key(w, "author_guard_binding")
      @encode.string_value(w, "absent")
      @encode.key(w, "breach")
      @encode.string_value(w, "fail")
      @encode.key(w, "candidates")
      @encode.begin_array(w)
      for i in 0..<count {
        let candidate = @derivation.minimum_candidate_at(minimum, i).unwrap()
        @wire.emit(@wire.claim_at(arithmetic, candidate.node).unwrap(), w)
      }
      @encode.end_array(w)
      @encode.key(w, "effective_max")
      @encode.number_value(w, @derivation.minimum_value(minimum).to_double())
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
      max_candidates: count,
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
      @sequence.limit(selected.limits, MatchesPerKey),
      subject + "matches-per-key",
      "matches_per_key",
      remaining,
    )
    let output = reidentify_sequence_limit(
      @sequence.limit(selected.limits, OutputRows),
      subject + "output",
      "rows",
      remaining,
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
