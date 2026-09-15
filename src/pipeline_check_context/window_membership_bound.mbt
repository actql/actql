///|
pub enum WindowMembershipBoundIssue {
  InvalidLimits
  InvalidRequirement
  MissingOptions
  ForeignEvidence
  BudgetExceeded
  Overflow
}

///|
pub struct WindowMembershipCandidate {
  input : @capacity.TargetMembership
  maximum : Int64
}

///|
struct WindowMembershipBounds {
  owner : ProgramOperationResolutionIndex
  requirement : Int
  execution : WindowExecutionCheck
  options : WindowMembershipOptions
  law : String
  candidates : Array[WindowMembershipCandidate]
  maximum : Int64?
  work : Int
}

///|
/// Collect conditional Program bounds, not Host limits or execution permission.
/// Empty coverage means unknown, never zero. Original claim coordinates survive.
pub fn collect_window_membership_bounds(
  owner : ProgramOperationResolutionIndex,
  requirement : Int,
  max_work : Int,
  max_candidates : Int,
) -> Result[WindowMembershipBounds, WindowMembershipBoundIssue] {
  if max_work < 0 || max_candidates < 0 {
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
    site.requirement
    is @pipeline.WindowRequirement(@window.ResolveMembershipBound) else {
    return Err(InvalidRequirement)
  }
  let mut assignment = None
  let start = requirement - site.index
  for slot in 0..<@pipeline.operation_obligations_count(site.obligations) {
    guard spend() else { return Err(BudgetExceeded) }
    let i = start + slot
    guard owner.requirements.entries.get(i) is Some(expected) &&
      expected.stage == site.stage &&
      expected.producer_visit == site.producer_visit &&
      physical_equal(expected.obligations, site.obligations) else {
      return Err(ForeignEvidence)
    }
    if owner.states.get(i) is Some(Execution(WindowExecution(check))) &&
      check.rule is AssignMemberships(options) {
      if !physical_equal(check.site, expected) {
        return Err(ForeignEvidence)
      }
      assignment = Some((check, options))
    }
  }
  guard assignment is Some((execution, options)) else {
    return Err(MissingOptions)
  }
  let law = match @window.input(execution.window) {
    @carrier.Relation(_) => "actql.bound.row-window"
    @carrier.EventValue(_) => "actql.bound.window-events"
    _ => return Err(ForeignEvidence)
  }
  let stages = owner.requirements.stages
  let closure = stages.contexts[site.stage].context.capacity
  let candidates : Array[WindowMembershipCandidate] = []
  let mut maximum = None
  for
    visit in 0..<@pipeline.contextual_closure_count(
      @capacity.application_closure_orders(closure),
    ) {
    guard spend() else { return Err(BudgetExceeded) }
    let coverage = @capacity.application_closure_at(closure, visit).unwrap()
    let source = @capacity.application_coverage_sources(coverage)
    if !physical_equal(
        site.pipeline,
        @capacity.checked_pipeline(@capacity.source_coverage_graph(source)),
      ) {
      continue
    }
    let applications = @capacity.source_coverage_program(source)
    let claims = @wire.program_claim_arithmetic(
      @step_bounds.application_claims(applications),
    )
    for claim in 0..<@wire.claim_count(claims) {
      guard spend() else { return Err(BudgetExceeded) }
      guard @step_bounds.application_at(applications, claim) is Some(bound) else {
        continue
      }
      let (result, used) = @step_bounds.check_target_rows_usage(
        site.pipeline,
        execution.input,
        bound,
        max_work - work,
      )
      work += used
      match result {
        Ok(rows) => {
          if candidates.length() == max_candidates {
            return Err(BudgetExceeded)
          }
          let membership = match
            @capacity.bind_target_membership(closure, rows, visit, claim) {
            Ok(v) => v
            Err(_) => return Err(ForeignEvidence)
          }
          let input = @step_bounds.target_rows_value(rows)
          let factor = options.maximum_per_input
          let product = match window_membership_product(input, factor) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
          maximum = Some(
            match maximum {
              Some(previous) => Int64::min(previous, product)
              None => product
            },
          )
          candidates.push({ input: membership, maximum: product, })
        }
        Err(
          @step_bounds.WrongUnit
          | @step_bounds.UnrelatedBound
          | @step_bounds.MissingProducer
        ) => ()
        Err(@step_bounds.WorkLimit) => return Err(BudgetExceeded)
        Err(_) => return Err(ForeignEvidence)
      }
    }
  }
  Ok({ owner, requirement, execution, options, law, candidates, maximum, work, })
}

///|
fn window_membership_product(
  input : Int64,
  factor : Int64,
) -> Result[Int64, WindowMembershipBoundIssue] {
  // Input and factor were already admitted as nonnegative/positive safe integers.
  if input > 9007199254740991L / factor {
    return Err(Overflow)
  }
  Ok(input * factor)
}

///|
pub fn window_membership_bound_owner(
  v : WindowMembershipBounds,
) -> ProgramOperationResolutionIndex {
  v.owner
}

///|
pub fn window_membership_bound_requirement(v : WindowMembershipBounds) -> Int {
  v.requirement
}

///|
pub fn window_membership_bound_execution(
  v : WindowMembershipBounds,
) -> WindowExecutionCheck {
  v.execution
}

///|
pub fn window_membership_bound_options(
  v : WindowMembershipBounds,
) -> WindowMembershipOptions {
  v.options
}

///|
pub fn window_membership_bound_law(v : WindowMembershipBounds) -> String {
  v.law
}

///|
pub fn window_membership_bound_maximum(v : WindowMembershipBounds) -> Int64? {
  v.maximum
}

///|
pub fn window_membership_bound_candidate_count(
  v : WindowMembershipBounds,
) -> Int {
  v.candidates.length()
}

///|
pub fn window_membership_bound_candidate_at(
  v : WindowMembershipBounds,
  index : Int,
) -> WindowMembershipCandidate? {
  v.candidates.get(index)
}

///|
pub fn window_membership_bound_work(v : WindowMembershipBounds) -> Int {
  v.work
}
