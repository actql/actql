///|
struct IntervalSearchLimit {
  source : UnitOperationSource
  selected : @context.IntervalSearchCheck
  proofs : Array[Array[ReidentifiedStep]]
  left_refs : Array[String]
  right_refs : Array[String]
  subject : String
  cid : String
}

///|
fn emit_interval_search_body(
  subject : String,
  maximum : Int64,
  left : Array[String],
  right : Array[String],
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(w)
  @encode.key(w, "condition")
  @encode.string_value(w, "single_visit")
  @encode.key(w, "enforcement")
  @encode.string_value(w, "engine_atomic")
  @encode.key(w, "left_bounds")
  @encode.begin_array(w)
  for cid in left {
    @encode.string_value(w, cid)
  }
  @encode.end_array(w)
  @encode.key(w, "maximum")
  @encode.number_value(w, maximum.to_double())
  @encode.key(w, "right_bounds")
  @encode.begin_array(w)
  for cid in right {
    @encode.string_value(w, cid)
  }
  @encode.end_array(w)
  @encode.key(w, "search_contract_cid")
  @encode.string_value(w, @context.core_contract_cid(IntervalSearchRules))
  @encode.key(w, "subject_ref")
  @encode.string_value(w, subject)
  @encode.key(w, "unit")
  @encode.string_value(w, "pair_visits")
  @encode.key(w, "version")
  @encode.string_value(w, "actql-interval-search-limit/0.1")
  @encode.end_object(w)
}

///|
pub fn emit_interval_search_limit(
  v : IntervalSearchLimit,
  w : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_interval_search_body(
    v.subject,
    @step_bounds.interval_search_upper(v.selected.product),
    v.left_refs,
    v.right_refs,
    w,
  )
}

///|
fn assemble_interval_search_limit(
  units : Array[BuiltUnit],
  source : UnitOperationSource,
  selected : @context.IntervalSearchCheck,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> IntervalSearchLimit raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  let product = selected.product
  guard selected.rule == @context.EnforceSingleVisitSearch &&
    physical_equal(selected.site.pipeline, source.pipeline) &&
    selected.site.step == source.source_ordinal &&
    physical_equal(
      @step_bounds.interval_search_pipeline(product),
      source.pipeline,
    ) &&
    @step_bounds.interval_search_step(product) == source.source_ordinal &&
    @context.interval_search_bound_product(selected.bounds) is Some(expected) &&
    physical_equal(expected, product) else {
    raise ForeignOwner
  }
  let identity = @context.expression_closure_identity(
    @context.operation_requirements_expressions(
      @context.operation_resolution_requirements(
        @context.interval_search_bound_owner(selected.bounds),
      ),
    ),
  )
  guard @context.program_identity_stage_at(identity, selected.site.stage)
    is Some(stage) &&
    physical_equal(stage, source.stage) else {
    raise ForeignOwner
  }
  let proofs : Array[Array[ReidentifiedStep]] = [[], []]
  let mut found = false
  for unit in units {
    identity_charge(remaining, 1)
    if physical_equal(unit.pipeline, source.pipeline) {
      if found || unit.definition_cid != source.unit_definition_cid {
        raise ForeignOwner
      }
      found = true
    }
  }
  guard found else { raise ForeignOwner }
  let references : Array[Array[String]] = [[], []]
  for side in 0..<2 {
    let count = @context.interval_search_bound_candidate_count(
      selected.bounds,
      side,
    )
    identity_charge(remaining, count)
    let ordered : Array[(String, ReidentifiedStep)] = []
    for candidate in 0..<count {
      let membership = @context.interval_search_bound_candidate_at(
        selected.bounds,
        side,
        candidate,
      ).unwrap()
      let rows = @capacity.target_membership_rows(membership)
      guard physical_equal(
          @capacity.target_membership_closure(membership),
          @context.interval_search_bound_closure(selected.bounds),
        ) &&
        @capacity.target_membership_consumer_visit(membership) ==
        selected.site.producer_visit &&
        physical_equal(@step_bounds.target_rows_pipeline(rows), source.pipeline) &&
        @step_bounds.interval_search_input_at(product, side) ==
        Some(@step_bounds.target_rows_target(rows)) else {
        raise ForeignOwner
      }
      let proof = reidentify_step_graph(
        units,
        @step_bounds.target_rows_bound(rows),
        remaining,
        conversion~,
      )
      let witness = @wire.program_proof_witness(proof.proof)
      if @wire.value(witness) != @step_bounds.target_rows_value(rows) {
        raise ForeignOwner
      }
      ordered.push((@wire.cid(witness), proof))
    }
    identity_sort(ordered, remaining)
    let mut previous : String? = None
    for (cid, proof) in ordered {
      identity_charge(remaining, cid.length() + 1)
      if previous != Some(cid) {
        references[side].push(cid)
        previous = Some(cid)
      }
      // Keep every admitted membership's original graph even when IDs coalesce.
      proofs[side].push(proof)
    }
  }
  let subject = unit_operation_subject(source, remaining)
  let writer = identity_writer(remaining)
  emit_interval_search_body(
    subject,
    @step_bounds.interval_search_upper(product),
    references[0],
    references[1],
    writer,
  ) catch {
    e => raise Encoding(e)
  }
  let cid = identity_finish(remaining, writer)
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  {
    source,
    selected,
    proofs,
    left_refs: references[0],
    right_refs: references[1],
    subject,
    cid,
  }
}

///|
fn prepare_program_interval_search_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
  conversion? : ProofConversion? = None,
) -> Array[Array[IntervalSearchLimit]] raise UnitBuildFailure {
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
  guard units.length() == @context.program_identity_stage_count(identity) else {
    raise ForeignOwner
  }
  let seen : Map[(Int, Int), Bool] = Map([])
  for i in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, i)
      is Some(ExecutionCheck(IntervalSearch(selected))) &&
      selected.rule == @context.EnforceSingleVisitSearch else {
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
    guard unit_operation_source(unit, site.pipeline, site.step) is Some(source) else {
      raise ForeignOwner
    }
    let limit = assemble_interval_search_limit(
      units,
      source,
      selected,
      remaining,
      conversion~,
    )
    identity_charge(remaining, 1)
    result[site.stage].push(limit)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_interval_search_limit_count(
  p : CheckedProgram,
  stage : Int,
) -> Int? {
  p.interval_search_limits.get(stage).map(a => a.length())
}

///|
pub fn unit_interval_search_limit_at(
  p : CheckedProgram,
  stage : Int,
  index : Int,
) -> IntervalSearchLimit? {
  p.interval_search_limits.get(stage).bind(a => a.get(index))
}

///|
pub fn interval_search_limit_cid(v : IntervalSearchLimit) -> String {
  v.cid
}

///|
pub fn interval_search_limit_source(
  v : IntervalSearchLimit,
) -> UnitOperationSource {
  v.source
}

///|
pub fn interval_search_limit_selection(
  v : IntervalSearchLimit,
) -> @context.IntervalSearchCheck {
  v.selected
}

///|
pub fn interval_search_limit_proof_count(
  v : IntervalSearchLimit,
  side : Int,
) -> Int {
  v.proofs.get(side).map(a => a.length()).unwrap_or(0)
}

///|
pub fn interval_search_limit_proof_at(
  v : IntervalSearchLimit,
  side : Int,
  index : Int,
) -> ReidentifiedStep? {
  v.proofs.get(side).bind(a => a.get(index))
}
