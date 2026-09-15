///|
priv struct DerivedProgramCapacity {
  inputs : ProgramCapacityInputs
  claims : Map[Int, Array[(@pipeline.CheckedPipeline, Array[Int?])]]
  work : Int
  text : Int
  bytes : Int
  nodes : Int
  input_work : Int
  operand_work : Int
}

///|
fn derive_program_capacity(
  prepared : @stage_results.PreparedLocalSource,
  inputs : ProgramCapacityInputs,
  max_work : Int,
  metadata : @wire.Limits,
  max_input_work : Int,
  max_operand_work : Int,
  count_bindings : CapacityCountBindings,
  max_text_bytes : Int,
  sourceviews : @sourceviews.PipelineInputs?,
  selected_policy : @policy.Policy,
) -> Result[DerivedProgramCapacity, CapacityStageIssue] {
  if max_work < 0 ||
    metadata.max_bytes < 0 ||
    metadata.max_nodes < 0 ||
    metadata.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @stages.program(@stage_results.local_source_source(prepared)),
      inputs.program,
    ) {
    return Err(Inputs(ForeignProgram))
  }
  let count = inputs.materials.length()
  if count > max_work {
    return Err(BudgetExceeded)
  }
  let mut work = count
  let mut bytes = 0
  let mut nodes = 0
  let materials = []
  let seeds = []
  let claims : Map[Int, Array[(@pipeline.CheckedPipeline, Array[Int?])]] = Map([])
  let wiring = @stage_results.local_source_wiring(prepared)
  for stage in 0..<count {
    let port = @stage_results.wiring_stage_at(wiring, stage).unwrap()
    let orders = @results.checked_producer_orders(
      @results.ports_orders(@stage_results.stage_port_publications(port)),
    )
    let pipeline = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(orders, 0).unwrap(),
    )
    let value = match
      derive_values_capacity_material(
        pipeline,
        inputs.materials[stage],
        max_work - work,
        {
          max_bytes: metadata.max_bytes - bytes,
          max_nodes: metadata.max_nodes - nodes,
          max_depth: metadata.max_depth,
        },
      ) {
      Ok(value) => value
      Err(issue) => return Err(Values(stage, issue))
    }
    work += value.work
    bytes += value.metadata_bytes
    nodes += value.metadata_nodes
    materials.push(value.material)
    seeds.push(value.bounds)
    let key = @decode.cursor_span(@pipeline.source(pipeline)).start_byte
    match claims.get(key) {
      Some(bucket) => bucket.push((pipeline, value.slots))
      None => claims[key] = [(pipeline, value.slots)]
    }
  }
  let derived = match
    derive_row_capacity(
      prepared,
      materials,
      seeds,
      max_work - work,
      {
        max_bytes: metadata.max_bytes - bytes,
        max_nodes: metadata.max_nodes - nodes,
        max_depth: metadata.max_depth,
      },
      max_input_work,
      max_operand_work,
      count_bindings,
      max_text_bytes,
      sourceviews,
      selected_policy,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RowCapacity(issue))
  }
  Ok({
    inputs: { ..inputs, materials: derived.materials, },
    claims,
    work: work + derived.work,
    text: derived.text,
    bytes: bytes + derived.bytes,
    nodes: nodes + derived.nodes,
    input_work: derived.input_work,
    operand_work: derived.operand_work,
  })
}

///|
fn retained_values_count(
  stages : StageContexts,
  site : OperationRequirementSite,
  max_work : Int,
) -> Result[(@step_bounds.StepBound?, Int), ValuesRowLimitIssue] {
  guard stages.values_claims is Some(claims) else { return Ok((None, 0)) }
  if max_work < 1 {
    return Err(BudgetExceeded)
  }
  let mut work = 1
  let key = @decode.cursor_span(@pipeline.source(site.pipeline)).start_byte
  guard claims.get(key) is Some(bucket) else { return Err(InvalidOwner) }
  for (pipeline, slots) in bucket {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    if physical_equal(pipeline, site.pipeline) {
      guard slots.get(site.step) is Some(Some(claim)) else {
        return Err(InvalidOwner)
      }
      let closure = stages.contexts[site.stage].context.capacity
      guard @capacity.application_closure_at(closure, site.producer_visit)
        is Some(coverage) else {
        return Err(InvalidOwner)
      }
      let applications = @capacity.source_coverage_program(
        @capacity.application_coverage_sources(coverage),
      )
      guard @step_bounds.application_at(applications, claim) is Some(bound) &&
        physical_equal(@step_bounds.checked_pipeline(bound), pipeline) &&
        @step_bounds.checked_step(bound) == site.step else {
        return Err(InvalidOwner)
      }
      return Ok((Some(bound), work))
    }
  }
  Err(InvalidOwner)
}
