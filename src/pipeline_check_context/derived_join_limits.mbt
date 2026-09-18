///|
fn join_family_step(step : @pipeline.CheckedStep) -> Bool {
  match step.operation {
    @pipeline.Join(..)
    | @pipeline.CrossJoin(..)
    | @pipeline.IntervalJoin(..)
    | @pipeline.AsOfJoin(..) => true
    _ => false
  }
}

///|
fn derive_join_limits(
  prepared : @stage_results.PreparedLocalSource,
  derived : RowCapacityResult,
  max_work : Int,
  metadata : @wire.Limits,
  selected_policy : @policy.Policy,
) -> Result[RowCapacityResult, CapacityStageIssue] {
  if max_work < 0 ||
    metadata.max_bytes < 0 ||
    metadata.max_nodes < 0 ||
    metadata.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  let mut bytes = 0
  let mut nodes = 0
  fn spend(amount : Int) -> Bool {
    if amount < 0 || amount > remaining {
      false
    } else {
      remaining -= amount
      true
    }
  }
  let materials = derived.materials.copy()
  let wiring = @stage_results.local_source_wiring(prepared)
  for stage in 0..<materials.length() {
    if !spend(1) {
      return Err(BudgetExceeded)
    }
    let port = @stage_results.wiring_stage_at(wiring, stage).unwrap()
    let orders = @results.checked_producer_orders(
      @results.ports_orders(@stage_results.stage_port_publications(port)),
    )
    let pipeline = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(orders, 0).unwrap(),
    )
    let material = materials[stage]
    let covered : Map[Int, Bool] = Map([])
    if !spend(material.consumers.length()) {
      return Err(BudgetExceeded)
    }
    for consumer in material.consumers {
      if consumer is @capacity.Join(step~, ..) {
        covered[step] = true
      }
    }
    let requests : Array[@host.ResolvedLimitRequest] = []
    let steps : Array[Int] = []
    for index in 0..<@pipeline.step_count(pipeline) {
      if !spend(1) {
        return Err(BudgetExceeded)
      }
      let step = @pipeline.step_at(pipeline, index).unwrap()
      if !join_family_step(step) || covered.contains(index) {
        continue
      }
      let candidates : Array[@wire.ProgramProofClaim] = []
      for bound in derived.applications[stage] {
        if !spend(1) {
          return Err(BudgetExceeded)
        }
        if @step_bounds.checked_step(bound) == index &&
          physical_equal(@step_bounds.checked_pipeline(bound), pipeline) {
          candidates.push(@step_bounds.checked_proof(bound))
        }
      }
      let subject = "join:checked-step:" + index.to_string() + ":output"
      if !spend(subject.length()) {
        return Err(BudgetExceeded)
      }
      requests.push({ subject, candidates, })
      steps.push(index)
    }
    if requests.is_empty() {
      continue
    }
    guard @policy.ceiling(selected_policy, "max_relation_output_rows")
      is Some(ceiling) else {
      return Err(MissingJoinCeiling(stage))
    }
    let extended = match
      @host.extend_resolved_limits(
        material.sources,
        ceiling,
        requests,
        @wire.EngineAtomic,
        {
          max_work: remaining,
          max_bytes: metadata.max_bytes - bytes,
          max_nodes: metadata.max_nodes - nodes,
          max_depth: metadata.max_depth,
        },
      ) {
      Ok(value) => value
      Err(issue) => return Err(ResolvedJoinLimits(stage, issue))
    }
    let usage = @host.resolved_limit_usage(extended)
    if !spend(usage.0) ||
      usage.1 > metadata.max_bytes - bytes ||
      usage.2 > metadata.max_nodes - nodes {
      return Err(BudgetExceeded)
    }
    bytes += usage.1
    nodes += usage.2
    let consumers = material.consumers.copy()
    for request in 0..<requests.length() {
      guard @host.resolved_limit_index(extended, request) is Some(index) else {
        return Err(BudgetExceeded)
      }
      consumers.push(@capacity.Join(step=steps[request], output=index))
    }
    materials[stage] = {
      sources: @host.resolved_limit_sources(extended),
      consumers,
    }
  }
  Ok({
    ..derived,
    materials,
    work: derived.work + max_work - remaining,
    bytes: derived.bytes + bytes,
    nodes: derived.nodes + nodes,
  })
}
