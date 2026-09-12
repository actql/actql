///|
pub(all) enum PipelineIssue {
  InvalidLimits
  WorkLimit
  ForeignStage
  ForeignInput(String)
} derive(Eq, Debug)

///|
priv struct PipelineEntry {
  input : ResolvedInput
  carrier : @environment.SourceViewCarrier
}

///|
struct PipelineInputs {
  resolved : Resolved
  stages : Array[Array[PipelineEntry]]
  work : Int
}

///|
struct PipelineAttachment {
  inputs : PipelineInputs
  stage : @stages.CollectedStage
  work : Int
}

///|
/// Prepare type-only registrations from the selected Catalog contracts. Facts,
/// read permissions, request closure and producer obligations are not inferred.
pub fn prepare_pipeline_inputs(
  resolved : Resolved,
  max_work : Int,
) -> Result[PipelineInputs, PipelineIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let source = @inputs.source(resolved.owner.inputs)
  let n = @stages.stage_count(source)
  let mut remaining = max_work
  for cost in [resolved.work, n, resolved.entries.length()] {
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
  }
  let stages : Array[Array[PipelineEntry]] = Array::makei(n, _ => [])
  let carriers = @environment.source_request_carriers(resolved.owner.catalog)
  for input in resolved.entries {
    let declaration = input.declaration
    if declaration.input_name.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= declaration.input_name.length()
    let carrier = @environment.source_view_carrier(
      carriers,
      @environment.source_request_member(input.selected.contract),
    ).unwrap()
    stages[declaration.stage_index].push({ input, carrier, })
  }
  Ok({ resolved, stages, work: max_work - remaining, })
}

///|
pub fn pipeline_resolution(v : PipelineInputs) -> Resolved {
  v.resolved
}

///|
pub fn pipeline_catalog_references(
  v : PipelineInputs,
) -> @environment.CatalogReferences {
  @environment.data_policy_references(
    @environment.value_contract_policies(
      @environment.source_view_shape_values(
        @environment.read_mode_shapes(
          @environment.carrier_schema_modes(
            @environment.source_request_carriers(v.resolved.owner.catalog),
          ),
        ),
      ),
    ),
  )
}

///|
pub fn pipeline_environment(v : PipelineInputs) -> @environment.WireEnvironment {
  @environment.contract_registry_environment(
    @environment.catalog_registry(
      @environment.reference_contents(
        @environment.data_policy_references(
          @environment.value_contract_policies(
            @environment.source_view_shape_values(
              @environment.read_mode_shapes(
                @environment.carrier_schema_modes(
                  @environment.source_request_carriers(v.resolved.owner.catalog),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  )
}

///|
pub fn pipeline_inputs_work(v : PipelineInputs) -> Int {
  v.work
}

///|
pub fn pipeline_input_count(v : PipelineInputs, stage_index : Int) -> Int? {
  v.stages.get(stage_index).map(xs => xs.length())
}

///|
pub fn pipeline_input_source(
  v : PipelineInputs,
  stage_index : Int,
  index : Int,
) -> ResolvedInput? {
  match v.stages.get(stage_index) {
    None => None
    Some(xs) => xs.get(index).map(e => e.input)
  }
}

///|
pub fn pipeline_input_at(
  v : PipelineInputs,
  stage_index : Int,
  index : Int,
) -> (String, @pipeline.InputContract)? {
  let xs = match v.stages.get(stage_index) {
    None => return None
    Some(xs) => xs
  }
  xs
  .get(index)
  .map(e => {
    (
      e.input.declaration.input_name,
      @pipeline.CarrierInput(
        @environment.carrier_schema_value(
          @environment.source_view_carrier_schema(e.carrier),
        ),
      ),
    )
  })
}

///|
/// Require the original type-only registration, not a same-shaped replacement
/// or unadmitted candidate-key/ranking/producer evidence.
pub fn attach_pipeline_inputs(
  inputs : PipelineInputs,
  stage : @stages.CollectedStage,
  max_work : Int,
) -> Result[PipelineAttachment, PipelineIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(
      @inputs.source(inputs.resolved.owner.inputs),
      @stages.source(stage),
    ) {
    return Err(ForeignStage)
  }
  let index = @stages.stage_index(stage)
  let entries = inputs.stages[index]
  let pipeline = @collection.pipeline(@stages.collection(stage))
  let n = @pipeline.input_count(pipeline)
  let mut remaining = max_work
  for cost in [inputs.work, @stages.collection_work(stage), n, entries.length()] {
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
  }
  let registered : Map[String, Int] = Map([])
  for i in 0..<n {
    let name = @pipeline.input_at(pipeline, i).unwrap().0
    if name.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= name.length()
    registered[name] = i
  }
  for entry in entries {
    let name = entry.input.declaration.input_name
    if name.length() > remaining {
      return Err(WorkLimit)
    }
    remaining -= name.length()
    let actual = match registered.get(name) {
      None => return Err(ForeignInput(name))
      Some(i) => @pipeline.input_contract_at(pipeline, i).unwrap()
    }
    let expected = @environment.carrier_schema_value(
      @environment.source_view_carrier_schema(entry.carrier),
    )
    guard actual is @pipeline.CarrierInput(value) &&
      physical_equal(expected, value) else {
      return Err(ForeignInput(name))
    }
  }
  Ok({ inputs, stage, work: max_work - remaining, })
}

///|
pub fn attached_pipeline_inputs(v : PipelineAttachment) -> PipelineInputs {
  v.inputs
}

///|
pub fn attached_pipeline_stage(
  v : PipelineAttachment,
) -> @stages.CollectedStage {
  v.stage
}

///|
pub fn pipeline_attachment_work(v : PipelineAttachment) -> Int {
  v.work
}
