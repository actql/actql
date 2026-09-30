///|
/// Supply the two independent engine-atomic limits for local path queries.
/// The selected Host policy owns the ceilings; authored output guards can only
/// narrow them during checked application.
fn derive_traversal_limits(
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
      if consumer is @capacity.Traversal(step~, ..) {
        covered[step] = true
      }
    }
    let mut sources = material.sources
    let consumers = material.consumers.copy()
    for step in 0..<@pipeline.step_count(pipeline) {
      if !spend(1) {
        return Err(BudgetExceeded)
      }
      if covered.contains(step) {
        continue
      }
      let (operation, output_law) = match
        @pipeline.step_at(pipeline, step).unwrap().operation {
        @pipeline.Traverse(..) =>
          ("traverse", Some("actql.bound.traverse-nodes"))
        @pipeline.Reach(_) => ("reach", None)
        @pipeline.Shortest(..) =>
          ("shortest_path", Some("actql.bound.shortest-path"))
        _ => continue
      }
      let subject = operation + ":checked-step:" + step.to_string()
      if !spend(subject.length()) {
        return Err(BudgetExceeded)
      }
      let output_candidates : Array[@wire.ProgramProofClaim] = []
      for bound in derived.applications[stage] {
        if !spend(1) {
          return Err(BudgetExceeded)
        }
        if @step_bounds.checked_step(bound) != step ||
          !physical_equal(@step_bounds.checked_pipeline(bound), pipeline) {
          continue
        }
        let proof = @step_bounds.checked_proof(bound)
        let witness = @wire.program_proof_witness(proof)
        if @wire.unit(witness) == @derivation.Rows &&
          output_law == Some(@law.name(@wire.law(witness))) {
          output_candidates.push(proof)
        }
      }
      let mut path_index = None
      let mut output_index = None
      for
        (field, suffix) in [
          ("max_graph_paths", ":paths"),
          ("max_graph_output_rows", ""),
        ] {
        guard @policy.ceiling(selected_policy, field) is Some(ceiling) else {
          return Err(MissingTraversalCeiling(stage, field))
        }
        let requests : Array[@host.ResolvedLimitRequest] = [
          {
            subject: subject + suffix,
            candidates: if suffix == "" {
              output_candidates
            } else {
              []
            },
          },
        ]
        let extended = match
          @host.extend_resolved_limits(
            sources,
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
          Err(issue) => return Err(ResolvedTraversalLimits(stage, step, issue))
        }
        let usage = @host.resolved_limit_usage(extended)
        if !spend(usage.0) ||
          usage.1 > metadata.max_bytes - bytes ||
          usage.2 > metadata.max_nodes - nodes {
          return Err(BudgetExceeded)
        }
        bytes += usage.1
        nodes += usage.2
        guard @host.resolved_limit_index(extended, 0) is Some(index) else {
          return Err(BudgetExceeded)
        }
        if suffix == ":paths" {
          path_index = Some(index)
        } else {
          output_index = Some(index)
        }
        sources = @host.resolved_limit_sources(extended)
      }
      consumers.push(
        @capacity.Traversal(
          step~,
          paths=path_index.unwrap(),
          output=output_index.unwrap(),
        ),
      )
    }
    materials[stage] = { sources, consumers, }
  }
  Ok({
    ..derived,
    materials,
    work: derived.work + max_work - remaining,
    bytes: derived.bytes + bytes,
    nodes: derived.nodes + nodes,
  })
}
