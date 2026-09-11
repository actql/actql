///|
pub(all) enum ApplicationClosureIssue {
  InvalidLimits
  CoverageCount(expected~ : Int, actual~ : Int)
  WorkLimit(Int)
  ForeignPipeline(Int)
  ForeignPolicy(Int)
  ForeignGuardClosure
  GuardBindings(Int, @program.GuardBindingIssue)
  ProofWorkLimit
  InvalidProofOwner(Int, Int)
  DuplicateProofOwner(Int, Int)
  UnnecessaryProofOwner(Int, Int)
  ForeignProofOwner(Int, Int)
  MissingProofOwner(Int, Int)
  ProofBindingMismatch(Int, Int)
} derive(Eq, Debug)

///|
/// Coverage of supported capacity applications at every producer occurrence.
/// Does not certify unsupported sources, consumers or runnable Plans.
struct ApplicationClosure {
  orders : @pipeline.ContextualClosure
  entries : Array[ApplicationCoverage]
  policy : @policy.Policy
  guards : @pipeline.BoundGuardClosure
  bound_applications : Array[@program.GuardApplications]
  proof_owners : Map[(Int, Int), Int]
  work : Int
}

///|
pub fn check_application_closure(
  orders : @pipeline.ContextualClosure,
  applications : Array[ApplicationCoverage],
  selected_policy~ : @policy.Policy,
  bound_guards~ : @pipeline.BoundGuardClosure,
  proof_owners? : Array[(Int, Int, Int)] = [],
  max_work~ : Int,
) -> Result[ApplicationClosure, ApplicationClosureIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(orders, @pipeline.bound_guard_closure_source(bound_guards)) {
    return Err(ForeignGuardClosure)
  }
  let n = @pipeline.contextual_closure_count(orders)
  if applications.length() != n {
    return Err(CoverageCount(expected=n, actual=applications.length()))
  }
  let mut work = 0
  let bound_applications : Array[@program.GuardApplications] = []
  for i, app in applications {
    if work >= max_work {
      return Err(WorkLimit(i))
    }
    work += 1
    if app.work > max_work - work {
      return Err(WorkLimit(i))
    }
    work += app.work
    let expected = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(orders, i).unwrap(),
    )
    if !physical_equal(expected, app.sources.graph.pipeline) {
      return Err(ForeignPipeline(i))
    }
    if @policy.cid(selected_policy) != @policy.cid(app.sources.graph.policy) {
      return Err(ForeignPolicy(i))
    }
    let bound = match
      @program.check_guard_bindings(
        app.sources.program,
        @pipeline.bound_guard_closure_at(bound_guards, i).unwrap(),
        max_work=max_work - work,
      ) {
      Ok(v) => v
      Err(e) => return Err(GuardBindings(i, e))
    }
    work += @program.guard_application_work(bound)
    bound_applications.push(bound)
  }
  let membership = match
    check_proof_membership(
      orders,
      applications,
      bound_guards,
      proof_owners,
      max_work - work,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  work += membership.work
  Ok({
    orders,
    entries: applications.copy(),
    policy: selected_policy,
    guards: bound_guards,
    bound_applications,
    proof_owners: membership.owners,
    work,
  })
}

///|
pub fn application_closure_proof_owner(
  v : ApplicationClosure,
  visit : Int,
  claim : Int,
) -> Int? {
  v.proof_owners.get((visit, claim))
}

///|
pub fn application_closure_guards(
  v : ApplicationClosure,
) -> @pipeline.BoundGuardClosure {
  v.guards
}

///|
pub fn application_closure_bindings_at(
  v : ApplicationClosure,
  index : Int,
) -> @program.GuardApplications? {
  v.bound_applications.get(index)
}

///|
pub fn application_closure_policy(v : ApplicationClosure) -> @policy.Policy {
  v.policy
}

///|
pub fn application_closure_orders(
  v : ApplicationClosure,
) -> @pipeline.ContextualClosure {
  v.orders
}

///|
pub fn application_closure_at(
  v : ApplicationClosure,
  index : Int,
) -> ApplicationCoverage? {
  v.entries.get(index)
}

///|
pub fn application_closure_work(v : ApplicationClosure) -> Int {
  v.work
}
