///|
fn registered_stage(
  source : @stages.Source,
  registrations : Array[(String, @pipeline.InputContract)],
  stage_index? : Int = 0,
) -> @stages.CollectedStage {
  let body = @decode.open_object(
    @syntax.stage_body(@stages.stage_at(source, stage_index).unwrap()),
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    registrations,
    Some(@stages.declarations(source)),
    @decode.lookup(body, "from"),
    {
      max_steps: 100,
      max_work: 1000000,
      max_text_bytes: 1000000,
      max_nodes: 100000,
      max_tokens: 100000,
      max_depth: 100,
    },
  ).unwrap()
  @stages.collect(source, stage_index, pipeline, {
    max_work: 1000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 1000000,
    max_direct_text_bytes: 1000000,
  }).unwrap()
}

///|
fn check_pipeline_stages_fixture(
  catalog : @environment.SourceRequestContracts,
  input : String,
) -> Unit raise {
  let stages = "{\"id\":\"a\",\"inputs\":{\"remote\":" +
    input +
    ",\"other\":" +
    input +
    "},\"from\":\"remote\",\"steps\":[],\"results\":{\"r\":{}}}," +
    "{\"id\":\"b\",\"inputs\":{\"remote\":" +
    input +
    "},\"steps\":[],\"results\":{\"r\":{}}}," +
    "{\"id\":\"c\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}"
  let source_inputs = fixture_inputs(input, stage_bodies=Some(stages))
  let resolved = resolve(source_inputs, catalog, caps()).unwrap()
  let prepared = prepare_pipeline_inputs(resolved, 10000000).unwrap()
  assert_eq(pipeline_input_count(prepared, 0), Some(2))
  assert_eq(pipeline_input_count(prepared, 1), Some(1))
  assert_eq(pipeline_input_count(prepared, 2), Some(0))
  assert_true(pipeline_input_source(prepared, 2, 0) is None)
  assert_eq(
    declaration(pipeline_input_source(prepared, 1, 0).unwrap()).stage_index,
    1,
  )
  let registrations = [
    pipeline_input_at(prepared, 0, 1).unwrap(),
    pipeline_input_at(prepared, 0, 0).unwrap(),
  ]
  let source = @inputs.source(source_inputs)
  let first = registered_stage(source, registrations)
  registrations.clear()
  assert_true(attach_pipeline_inputs(prepared, first, 10000000) is Ok(_))
  let second = registered_stage(
    source,
    [pipeline_input_at(prepared, 1, 0).unwrap()],
    stage_index=1,
  )
  assert_true(attach_pipeline_inputs(prepared, second, 10000000) is Ok(_))
}

///|
fn check_pipeline_fixture(
  resolved : Resolved,
  foreign_catalog : @environment.SourceRequestContracts,
  foreign_source : @inputs.Inputs,
) -> Unit raise {
  let prepared = prepare_pipeline_inputs(resolved, 10000000).unwrap()
  assert_true(physical_equal(pipeline_resolution(prepared), resolved))
  assert_eq(pipeline_input_count(prepared, 0), Some(1))
  assert_true(pipeline_input_count(prepared, -1) is None)
  assert_true(pipeline_input_count(prepared, 1) is None)
  assert_true(pipeline_input_at(prepared, 0, 1) is None)
  assert_true(pipeline_input_at(prepared, -1, 0) is None)
  assert_true(pipeline_input_source(prepared, 1, 0) is None)
  assert_true(
    physical_equal(
      pipeline_input_source(prepared, 0, 0).unwrap(),
      at(resolved, 0).unwrap(),
    ),
  )
  let registration = pipeline_input_at(prepared, 0, 0).unwrap()
  let registrations = [registration]
  let source = @inputs.source(inputs(resolved))
  let stage = registered_stage(source, registrations)
  registrations.clear()
  let attached = attach_pipeline_inputs(prepared, stage, 10000000).unwrap()
  assert_true(physical_equal(attached_pipeline_inputs(attached), prepared))
  assert_true(physical_equal(attached_pipeline_stage(attached), stage))
  assert_true(
    prepare_pipeline_inputs(resolved, pipeline_inputs_work(prepared)) is Ok(_),
  )
  assert_true(
    prepare_pipeline_inputs(resolved, pipeline_inputs_work(prepared) - 1)
    is Err(WorkLimit),
  )
  assert_true(prepare_pipeline_inputs(resolved, -1) is Err(InvalidLimits))
  assert_true(
    attach_pipeline_inputs(prepared, stage, pipeline_attachment_work(attached))
    is Ok(_),
  )
  assert_true(
    attach_pipeline_inputs(
      prepared,
      stage,
      pipeline_attachment_work(attached) - 1,
    )
    is Err(WorkLimit),
  )
  assert_true(attach_pipeline_inputs(prepared, stage, -1) is Err(InvalidLimits))
  let other = prepare_pipeline_inputs(
    resolve(inputs(resolved), foreign_catalog, caps()).unwrap(),
    10000000,
  ).unwrap()
  let same_shape = registered_stage(source, [
    pipeline_input_at(other, 0, 0).unwrap(),
  ])
  assert_true(
    attach_pipeline_inputs(prepared, same_shape, 10000000)
    is Err(ForeignInput("remote")),
  )
  let foreign = registered_stage(@inputs.source(foreign_source), [registration])
  assert_true(
    attach_pipeline_inputs(prepared, foreign, 10000000) is Err(ForeignStage),
  )
  // A reconstructed Carrier is not the selected contract owner even when its
  // row contract is shared and its complete type is equal.
  guard registration.1 is @pipeline.CarrierInput(carrier) else {
    fail("carrier registration")
  }
  if @carrier.relation_rows(carrier) is Some(rows) {
    let copied = @carrier.relation(rows)
    let copied_stage = registered_stage(source, [
      (registration.0, @pipeline.CarrierInput(copied)),
    ])
    assert_true(
      attach_pipeline_inputs(prepared, copied_stage, 10000000)
      is Err(ForeignInput("remote")),
    )
  }
}
