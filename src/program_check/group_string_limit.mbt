///|
struct GroupStringLimit {
  source : GroupAggregateSource
  selected : @context.GroupStringLimit
  claim : @wire.LimitClaim
}

///|
pub fn group_string_limit_source(v : GroupStringLimit) -> GroupAggregateSource {
  v.source
}

///|
pub fn group_string_limit_selection(
  v : GroupStringLimit,
) -> @context.GroupStringLimit {
  v.selected
}

///|
pub fn group_string_limit_claim(v : GroupStringLimit) -> @wire.LimitClaim {
  v.claim
}

///|
fn assemble_group_string_limit(
  source : GroupAggregateSource,
  selected : @context.GroupStringLimit,
  budget : IdentityBudget,
) -> GroupStringLimit raise UnitBuildFailure {
  let candidates : Array[(String, @wire.WireWitness)] = []
  let mut non_author : Int64? = None
  if @context.group_string_limit_host(selected) is Some(ceiling) {
    let host = publication_host(ceiling, budget)
    let bytes = publication_metadata(
      w => @host.emit(host, w) catch { e => raise Encoding(e) },
      budget,
    )
    identity_charge(budget, bytes.length())
    let witness = match
      @wire.admit(bytes, @host.cid(host), {
        max_bytes: bytes.length(),
        max_nodes: bytes.length(),
        max_depth: budget.depth,
      }) {
      Ok(v) => v
      Err(e) => raise PublicationWire(e)
    }
    non_author = Some(@wire.value(witness))
    candidates.push((@wire.cid(witness), witness))
  }
  let guard_value = @context.group_string_limit_guard(selected)
  if guard_value is Some(value) {
    let witness = emit_group_guard_witness(source, value, budget)
    candidates.push((@wire.cid(witness), witness))
  }
  let claim = assemble_group_limit_claim(
    source,
    candidates,
    [],
    guard_value,
    non_author,
    @context.group_string_limit_maximum(selected),
    "bytes",
    budget,
  )
  { source, selected, claim, }
}

///|
fn prepare_program_group_string_limits(
  units : Array[BuiltUnit],
  requirements : @context.StageRequirementClosure,
  budget : IdentityBudget,
) -> Array[Array[GroupStringLimit]] raise UnitBuildFailure {
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, units.length())
  let result = Array::makei(units.length(), _ => [])
  let closure = @context.stage_requirement_operations(requirements)
  let seen : Map[(Int, Int, String), Bool] = Map([])
  for index in 0..<@context.operation_closure_count(closure) {
    identity_charge(remaining, 1)
    guard @context.operation_closure_at(closure, index)
      is Some(ExecutionCheck(GroupExecution(check))) &&
      check.rule is EnforceStringBytes(selected) else {
      continue
    }
    guard units.get(check.site.stage) is Some(unit) else { raise ForeignOwner }
    if !physical_equal(unit.pipeline, check.site.pipeline) {
      continue
    }
    let call = @context.group_string_limit_call(selected)
    let name = @relation.aggregate_name(call)
    identity_charge(remaining, name.length())
    let key = (check.site.stage, check.site.step, name)
    if seen.contains(key) {
      raise ForeignOwner
    }
    seen[key] = true
    guard unit_operation_source(unit, check.site.pipeline, check.site.step)
      is Some(operation) else {
      raise ForeignOwner
    }
    let source = GroupAggregateSource::{ operation, call, scope: "bytes", }
    let limit = assemble_group_string_limit(source, selected, remaining)
    identity_charge(remaining, 1)
    result[check.site.stage].push(limit)
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  result
}

///|
pub fn unit_group_string_limit_count(
  program : CheckedProgram,
  stage : Int,
) -> Int? {
  program.group_string_limits.get(stage).map(v => v.length())
}

///|
pub fn unit_group_string_limit_at(
  program : CheckedProgram,
  stage : Int,
  index : Int,
) -> GroupStringLimit? {
  program.group_string_limits.get(stage).bind(v => v.get(index))
}
