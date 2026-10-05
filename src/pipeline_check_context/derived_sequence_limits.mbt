///|
/// Supply the existing independent Host limits for every Sequence occurrence.
/// Authored guards narrow these claims during checked application; they do not
/// replace the selected policy or establish runtime matching success.
fn derive_sequence_limits(
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
  if !spend(derived.materials.length()) {
    return Err(BudgetExceeded)
  }
  let materials = derived.materials.copy()
  let wiring = @stage_results.local_source_wiring(prepared)
  for stage in 0..<materials.length() {
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
      if consumer is @capacity.Sequence(step~, ..) {
        covered[step] = true
      }
    }
    let mut sources = material.sources
    let consumers = material.consumers.copy()
    for step in 0..<@pipeline.step_count(pipeline) {
      if !spend(1) {
        return Err(BudgetExceeded)
      }
      if covered.contains(step) ||
        !(@pipeline.step_at(pipeline, step).unwrap().operation
        is @pipeline.Sequence(_)) {
        continue
      }
      let subject = "sequence:checked-step:" + step.to_string()
      if !spend(subject.length()) {
        return Err(BudgetExceeded)
      }
      let mut matches_index = None
      let mut output_index = None
      for
        (field, suffix) in [
          ("max_temporal_matches_per_key", ":matches-per-key"),
          ("max_temporal_output_rows", ":output"),
        ] {
        guard @policy.ceiling(selected_policy, field) is Some(ceiling) else {
          return Err(MissingSequenceCeiling(stage, field))
        }
        let requests : Array[@host.ResolvedLimitRequest] = [
          { subject: subject + suffix, candidates: [], },
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
          Err(issue) => return Err(ResolvedSequenceLimits(stage, step, issue))
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
        if suffix == ":matches-per-key" {
          matches_index = Some(index)
        } else {
          output_index = Some(index)
        }
        sources = @host.resolved_limit_sources(extended)
      }
      consumers.push(
        @capacity.Sequence(
          step~,
          matches=matches_index.unwrap(),
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
