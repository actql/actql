///|
/// Bind Components input-node proof to its exact checked step, then resolve
/// output rows under the selected Host ceiling. The two limits are independent.
fn derive_components_limits(
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
      if consumer is @capacity.Components(step~, ..) {
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
      guard @pipeline.step_at(pipeline, step).unwrap().operation
        is @pipeline.Graph(operation) &&
        @graph.operation(operation) == @graph.Components else {
        continue
      }
      let subject = "components:checked-step:" + step.to_string()
      if !spend(subject.length()) {
        return Err(BudgetExceeded)
      }
      let node_candidates : Array[@wire.ProgramProofClaim] = []
      let row_candidates : Array[@wire.ProgramProofClaim] = []
      for bound in derived.applications[stage] {
        if !spend(1) {
          return Err(BudgetExceeded)
        }
        if @step_bounds.checked_step(bound) != step ||
          !physical_equal(@step_bounds.checked_pipeline(bound), pipeline) {
          continue
        }
        let proof = @step_bounds.checked_proof(bound)
        let wire = @wire.program_proof_witness(proof)
        match (@law.name(@wire.law(wire)), @wire.unit(wire)) {
          ("actql.bound.components-input-nodes", @derivation.Nodes) =>
            node_candidates.push(proof)
          ("actql.bound.components-nodes", @derivation.Rows) =>
            row_candidates.push(proof)
          _ => ()
        }
      }
      let node_extension = match
        @host.extend_program_resolved_limits(
          sources,
          [{ subject: subject + ":nodes", candidates: node_candidates, }],
          @wire.EngineAtomic,
          {
            max_work: remaining,
            max_bytes: metadata.max_bytes - bytes,
            max_nodes: metadata.max_nodes - nodes,
            max_depth: metadata.max_depth,
          },
        ) {
        Ok(value) => value
        Err(issue) => return Err(ResolvedComponentsLimits(stage, step, issue))
      }
      let node_usage = @host.resolved_limit_usage(node_extension)
      if !spend(node_usage.0) ||
        node_usage.1 > metadata.max_bytes - bytes ||
        node_usage.2 > metadata.max_nodes - nodes {
        return Err(BudgetExceeded)
      }
      bytes += node_usage.1
      nodes += node_usage.2
      guard @host.resolved_limit_index(node_extension, 0) is Some(node_index) else {
        return Err(BudgetExceeded)
      }
      sources = @host.resolved_limit_sources(node_extension)
      guard @policy.ceiling(selected_policy, "max_graph_output_rows")
        is Some(ceiling) else {
        return Err(MissingComponentsCeiling(stage))
      }
      let row_extension = match
        @host.extend_resolved_limits(
          sources,
          ceiling,
          [{ subject, candidates: row_candidates, }],
          @wire.EngineAtomic,
          {
            max_work: remaining,
            max_bytes: metadata.max_bytes - bytes,
            max_nodes: metadata.max_nodes - nodes,
            max_depth: metadata.max_depth,
          },
        ) {
        Ok(value) => value
        Err(issue) => return Err(ResolvedComponentsLimits(stage, step, issue))
      }
      let row_usage = @host.resolved_limit_usage(row_extension)
      if !spend(row_usage.0) ||
        row_usage.1 > metadata.max_bytes - bytes ||
        row_usage.2 > metadata.max_nodes - nodes {
        return Err(BudgetExceeded)
      }
      bytes += row_usage.1
      nodes += row_usage.2
      guard @host.resolved_limit_index(row_extension, 0) is Some(row_index) else {
        return Err(BudgetExceeded)
      }
      sources = @host.resolved_limit_sources(row_extension)
      consumers.push(
        @capacity.Components(step~, nodes=node_index, output=row_index),
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
