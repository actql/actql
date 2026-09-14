///|
pub enum GroupArrayLimitIssue {
  InvalidLimits
  InvalidRequirement
  UnresolvedGuard
  MissingHostCeiling
  BudgetExceeded
  ForeignEvidence
}

///|
struct GroupArrayLimit {
  input_law : String
  owner : ProgramOperationResolutionIndex
  requirement : Int
  call : @relation.CheckedAggregate
  host : @policy.Ceiling
  guard_value : Int64?
  guard_resolution : OperationScalarResolution?
  candidates : Array[@capacity.TargetMembership]
  maximum : Int64
  work : Int
}

///|
pub fn group_array_limit_maximum(value : GroupArrayLimit) -> Int64 {
  value.maximum
}

///|
pub fn group_array_limit_owner(
  value : GroupArrayLimit,
) -> ProgramOperationResolutionIndex {
  value.owner
}

///|
pub fn group_array_limit_requirement(value : GroupArrayLimit) -> Int {
  value.requirement
}

///|
pub fn group_array_limit_call(
  value : GroupArrayLimit,
) -> @relation.CheckedAggregate {
  value.call
}

///|
pub fn group_array_limit_host(value : GroupArrayLimit) -> @policy.Ceiling {
  value.host
}

///|
pub fn group_array_limit_guard(value : GroupArrayLimit) -> Int64? {
  value.guard_value
}

///|
pub fn group_array_limit_guard_resolution(
  value : GroupArrayLimit,
) -> OperationScalarResolution? {
  value.guard_resolution
}

///|
pub fn group_array_limit_input_law(value : GroupArrayLimit) -> String {
  value.input_law
}

///|
pub fn group_array_limit_candidate_count(value : GroupArrayLimit) -> Int {
  value.candidates.length()
}

///|
pub fn group_array_limit_candidate_at(
  value : GroupArrayLimit,
  index : Int,
) -> @capacity.TargetMembership? {
  value.candidates.get(index)
}

///|
pub fn group_array_limit_work(value : GroupArrayLimit) -> Int {
  value.work
}

///|
pub fn select_group_array_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[GroupArrayLimit, GroupArrayLimitIssue] {
  select_array_limit(owner, requirement, max_work, max_candidates, false)
}

///|
pub fn select_analytic_array_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[GroupArrayLimit, GroupArrayLimitIssue] {
  select_array_limit(owner, requirement, max_work, max_candidates, true)
}

///|
fn select_array_limit(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
  analytic : Bool,
) -> Result[GroupArrayLimit, GroupArrayLimitIssue] {
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
  guard @pipeline.step_at(site.pipeline, site.step) is Some(step) else {
    return Err(InvalidRequirement)
  }
  let operation = match step.operation {
    @pipeline.Unary(op) => op
    @pipeline.WindowGroup(op) if !analytic => op
    _ => return Err(InvalidRequirement)
  }
  guard (if analytic {
      @relation.analytic(operation) is Some(_)
    } else {
      @relation.operation(operation) == @relation.Group
    }) &&
    step.input is Some(input) else {
    return Err(InvalidRequirement)
  }
  guard aggregate_limit_call(operation, site.index, analytic) is Some(call) &&
    @relation.aggregate_function(call) is @relation.ArrayAgg else {
    return Err(InvalidRequirement)
  }
  let stages = owner.requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let closure = stages.contexts[site.stage].context.capacity
  let policy = @capacity.application_closure_policy(closure)
  guard @policy.ceiling(policy, "max_aggregate_array_items") is Some(host) else {
    return Err(MissingHostCeiling)
  }
  let mut guard_value = None
  let mut guard_resolution = None
  match @relation.aggregate_item_limit(call) {
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
  let mut maximum = @policy.ceiling_value(host)
  let mut count = 1
  if guard_value is Some(value) {
    if count == max_candidates {
      return Err(BudgetExceeded)
    }
    count += 1
    maximum = Int64::min(maximum, value)
  }
  let (candidates, used) = match
    collect_target_row_candidates(
      closure,
      site.pipeline,
      input,
      Some(site.producer_visit),
      max_work - work,
      max_candidates - count,
    ) {
    Ok(found) => found
    Err(CandidateBudget) => return Err(BudgetExceeded)
    Err(_) => return Err(ForeignEvidence)
  }
  work += used
  for candidate in candidates {
    maximum = Int64::min(
      maximum,
      @step_bounds.target_rows_value(
        @capacity.target_membership_rows(candidate),
      ),
    )
  }
  Ok({
    input_law: if analytic {
      "actql.bound.analytic-array-input"
    } else {
      "actql.bound.array-aggregate-input"
    },
    owner,
    requirement,
    call,
    host,
    guard_value,
    guard_resolution,
    candidates,
    maximum,
    work,
  })
}
