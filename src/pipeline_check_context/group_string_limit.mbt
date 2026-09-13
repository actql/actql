///|
pub enum GroupStringLimitIssue {
  InvalidLimits
  InvalidRequirement
  UnresolvedGuard
  MissingFiniteBound
  BudgetExceeded
}

///|
struct GroupStringLimit {
  owner : ProgramOperationResolutionIndex
  requirement : Int
  call : @relation.CheckedAggregate
  host : @policy.Ceiling?
  guard_value : Int64?
  guard_resolution : OperationScalarResolution?
  maximum : Int64
  work : Int
}

///|
pub fn group_string_limit_owner(
  v : GroupStringLimit,
) -> ProgramOperationResolutionIndex {
  v.owner
}

///|
pub fn group_string_limit_requirement(v : GroupStringLimit) -> Int {
  v.requirement
}

///|
pub fn group_string_limit_call(
  v : GroupStringLimit,
) -> @relation.CheckedAggregate {
  v.call
}

///|
pub fn group_string_limit_host(v : GroupStringLimit) -> @policy.Ceiling? {
  v.host
}

///|
pub fn group_string_limit_guard(v : GroupStringLimit) -> Int64? {
  v.guard_value
}

///|
pub fn group_string_limit_guard_resolution(
  v : GroupStringLimit,
) -> OperationScalarResolution? {
  v.guard_resolution
}

///|
pub fn group_string_limit_maximum(v : GroupStringLimit) -> Int64 {
  v.maximum
}

///|
pub fn group_string_limit_work(v : GroupStringLimit) -> Int {
  v.work
}

///|
/// Select the exact Host/author ceilings; not a derived input-size proof or
/// completed enforcement. A row-count bound is not an output-string byte bound.
pub fn select_group_string_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[GroupStringLimit, GroupStringLimitIssue] {
  select_string_limit(owner, requirement, max_work, max_candidates, false)
}

///|
/// Select per-frame string output bytes, not input rows or serialized JSON size.
pub fn select_analytic_string_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[GroupStringLimit, GroupStringLimitIssue] {
  select_string_limit(owner, requirement, max_work, max_candidates, true)
}

///|
fn aggregate_limit_call(
  operation : @relation.CheckedOperation,
  index : Int,
  analytic : Bool,
) -> @relation.CheckedAggregate? {
  if analytic {
    guard @relation.analytic(operation) is Some(body) &&
      @relation.analytic_call_for_validation(body, index) is Some(call) &&
      call.function is @relation.Aggregate(aggregate) else {
      return None
    }
    Some(aggregate)
  } else {
    guard @relation.group(operation) is Some(group) else { return None }
    @relation.aggregate_for_validation(group, index)
  }
}

///|
fn select_string_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
  analytic : Bool,
) -> Result[GroupStringLimit, GroupStringLimitIssue] {
  if max_work < 0 || max_candidates < 1 {
    return Err(InvalidLimits)
  }
  let mut work = owner.work
  let spend = fn() -> Bool {
    if work >= max_work {
      return false
    }
    work += 1
    true
  }
  guard spend() else { return Err(BudgetExceeded) }
  guard owner.requirements.entries.get(requirement) is Some(site) &&
    site.requirement is @pipeline.RelationRequirement(pending) &&
    pending.kind is @relation.AggregateEnvelope else {
    return Err(InvalidRequirement)
  }
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) &&
    step.operation is @pipeline.Unary(operation) &&
    (if analytic {
      @relation.analytic(operation) is Some(_)
    } else {
      @relation.operation(operation) == @relation.Group
    }) &&
    step.input is Some(_) else {
    return Err(InvalidRequirement)
  }
  guard aggregate_limit_call(operation, site.index, analytic) is Some(call) &&
    @relation.aggregate_function(call) is @relation.StringAgg else {
    return Err(InvalidRequirement)
  }
  let stages = owner.requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let closure = stages.contexts[site.stage].context.capacity
  let policy = @capacity.application_closure_policy(closure)
  let host = @policy.ceiling(policy, "max_aggregate_string_bytes")
  let mut guard_value = None
  let mut guard_resolution = None
  match @relation.aggregate_byte_limit(call) {
    Some(@relation.Literal(value)) => guard_value = Some(value)
    Some(@relation.Parameter(name)) => {
      for
        resolution in owner.profiles.calendar.lexical.cells.queries.ranges.fills.frames.scalars.entries {
        guard spend() else { return Err(BudgetExceeded) }
        if resolution.site.stage == site.stage &&
          resolution.site.producer_visit == site.producer_visit &&
          physical_equal(resolution.site.pipeline, site.pipeline) &&
          resolution.site.step == site.step &&
          aggregate_limit_call(operation, resolution.site.index, analytic)
          is Some(aggregate) &&
          physical_equal(aggregate, call) {
          if resolution.site.requirement is @pipeline.RelationRequirement(p) &&
            p.kind is @relation.BoundInteger(name=bound_name, ..) {
            let cost = Int::min(name.length(), bound_name.length()) + 1
            if cost > max_work - work {
              return Err(BudgetExceeded)
            }
            work += cost
            if name != bound_name {
              continue
            }
            guard resolution.value is Integer(value) else {
              return Err(UnresolvedGuard)
            }
            guard_value = Some(value)
            guard_resolution = Some(resolution)
          }
        }
      }
      if guard_value is None {
        return Err(UnresolvedGuard)
      }
    }
    None => ()
  }
  let mut maximum = None
  let mut count = 0
  if host is Some(ceiling) {
    count += 1
    maximum = Some(@policy.ceiling_value(ceiling))
  }
  if guard_value is Some(value) {
    if count == max_candidates {
      return Err(BudgetExceeded)
    }
    count += 1
    maximum = Some(
      match maximum {
        Some(previous) => Int64::min(previous, value)
        None => value
      },
    )
  }
  guard maximum is Some(maximum) else { return Err(MissingFiniteBound) }
  Ok({
    owner,
    requirement,
    call,
    host,
    guard_value,
    guard_resolution,
    maximum,
    work,
  })
}
