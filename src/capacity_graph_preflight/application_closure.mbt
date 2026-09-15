///|
pub(all) enum ApplicationClosureIssue {
  InvalidLimits
  CoverageCount(expected~ : Int, actual~ : Int)
  WorkLimit(Int)
  ForeignPipeline(Int)
  ForeignPolicy(Int)
  ForeignGuardClosure
  SequenceGuardBindings(Int)
  TraversalGuardBindings(Int)
  ComponentsGuardBindings(Int)
  GuardBindings(Int, @program.GuardBindingIssue)
  ProofWorkLimit
  InvalidProofOwner(Int, Int)
  DuplicateProofOwner(Int, Int)
  UnnecessaryProofOwner(Int, Int)
  ForeignProofOwner(Int, Int)
  MissingProofOwner(Int, Int)
  ProofBindingMismatch(Int, Int)
  InvalidInputOwner(Int, Int, Int)
  DuplicateInputOwner(Int, Int, Int)
  UnnecessaryInputOwner(Int, Int, Int)
  MissingInputOwner(Int, Int, Int)
  ForeignInputOwner(Int, Int, Int)
  ForeignProducerCollection(Int, Int)
  ForeignGraphDependency(Int, Int)
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
  input_owners : Map[(Int, Int, Int), Int]
  work : Int
}

///|
pub fn check_application_closure(
  orders : @pipeline.ContextualClosure,
  applications : Array[ApplicationCoverage],
  selected_policy~ : @policy.Policy,
  bound_guards~ : @pipeline.BoundGuardClosure,
  proof_owners? : Array[(Int, Int, Int)] = [],
  input_owners? : Array[(Int, Int, Int, Int)] = [],
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
    // External applications must come from an exact collection in this same
    // closure. A separately admitted table with equal CIDs is not a substitute.
    let producer_count = @program.application_producer_count(
      app.sources.program,
    )
    for dependency in 0..<producer_count {
      let producer = @program.application_producer_at(
        app.sources.program,
        dependency,
      ).unwrap()
      let mut found = false
      for candidate in applications {
        if work == max_work {
          return Err(ProofWorkLimit)
        }
        work += 1
        if physical_equal(producer, candidate.sources.program) {
          found = true
          break
        }
      }
      if !found {
        return Err(ForeignProducerCollection(i, dependency))
      }
    }
    let expected = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(orders, i).unwrap(),
    )
    for dependency in 0..<@input.dependency_count(app.sources.graph) {
      let graph = @input.dependency_at(app.sources.graph, dependency).unwrap()
      let mut found = false
      for candidate in applications {
        if work == max_work {
          return Err(ProofWorkLimit)
        }
        work += 1
        if physical_equal(graph, candidate.sources.graph) {
          found = true
          break
        }
      }
      if !found {
        return Err(ForeignGraphDependency(i, dependency))
      }
    }
    if !physical_equal(expected, checked_pipeline(app.sources.graph)) {
      return Err(ForeignPipeline(i))
    }
    if @policy.cid(selected_policy) !=
      @policy.cid(@input.selected_policy(app.sources.graph)) {
      return Err(ForeignPolicy(i))
    }
    if !@sequence.application_guard_bindings_match(
        app.consumers.sequence,
        @pipeline.bound_guard_closure_at(bound_guards, i).unwrap(),
      ) {
      return Err(SequenceGuardBindings(i))
    }
    if app.consumers.traversals is Some(traversals) &&
      !@program.traversal_application_guard_bindings_match(
        traversals,
        @pipeline.bound_guard_closure_at(bound_guards, i).unwrap(),
      ) {
      return Err(TraversalGuardBindings(i))
    }
    if app.consumers.components is Some(components) &&
      !@program.components_application_guard_bindings_match(
        components,
        @pipeline.bound_guard_closure_at(bound_guards, i).unwrap(),
      ) {
      return Err(ComponentsGuardBindings(i))
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
  let inputs = match
    check_input_membership(
      applications,
      membership.owners,
      input_owners,
      max_work - work,
    ) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  work += inputs.work
  Ok({
    orders,
    entries: applications.copy(),
    policy: selected_policy,
    guards: bound_guards,
    bound_applications,
    proof_owners: membership.owners,
    input_owners: inputs.owners,
    work,
  })
}

///|
/// Contextual visit containing the exact retained Graph preflight owner.
pub fn application_closure_input_owner(
  v : ApplicationClosure,
  visit : Int,
  claim : Int,
  dependency : Int,
) -> Int? {
  v.input_owners.get((visit, claim, dependency))
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
