///|
fn registration_read_fixture() -> (
  @stages.Source,
  @environment.SourceRequestContracts,
  @local_inputs.Limits,
  Int,
) {
  let remote = []
  let (_, wiring, _, _, _, _) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
  )
  (
    @stage_results.wiring_source(wiring),
    @sourceviews.catalog(@sourceviews.pipeline_resolution(remote[0])),
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    @sourceviews.pipeline_inputs_work(remote[0]),
  )
}

///|
test "original Source registration advances once with the same collected partition" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(source_registration_phase(read), RegistrationCollect)
  assert_true(take_source_registration_result(read) is None)
  assert_true(source_registration_collected_inputs(read) is None)
  assert_eq(source_registration_collection_work(read), 0)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  let inputs = source_registration_collected_inputs(read).unwrap()
  let spent = @source_inputs.work(inputs)
  assert_true(spent > 0)
  assert_eq(source_registration_collection_work(read), spent)
  assert_true(physical_equal(@source_inputs.source(inputs), source))
  assert_eq(@source_inputs.count(inputs), 2)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_true(
    physical_equal(source_registration_collected_inputs(read).unwrap(), inputs),
  )
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(advance_source_registration(read), RegistrationComplete)
  assert_eq(advance_source_registration(read), RegistrationComplete)
  assert_eq(source_registration_collection_work(read), spent)
  let (views, locals) = take_source_registration_result(read).unwrap().unwrap()
  assert_true(
    physical_equal(
      @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
      inputs,
    ),
  )
  assert_true(
    physical_equal(
      @sourceviews.catalog(@sourceviews.pipeline_resolution(views)),
      catalog,
    ),
  )
  assert_true(physical_equal(@local_inputs.environment_program(locals), source))
  for stage in 0..<2 {
    let local_stage = @local_inputs.program_environment_stage(locals, stage).unwrap()
    assert_true(
      physical_equal(
        @local_inputs.sourceview_inputs(
          @local_inputs.snapshot_inputs(
            @local_inputs.environment_assertions(local_stage),
          ),
        ).unwrap(),
        inputs,
      ),
    )
  }
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  assert_true(source_registration_collected_inputs(read) is None)
  clear_source_registration(read)
  clear_source_registration(read)
  assert_eq(advance_source_registration(read), RegistrationTransferred)
  assert_true(take_source_registration_result(read) is None)
  assert_eq(source_registration_collection_work(read), spent)
}

///|
test "original Source registration retains collection prefix and typed selection refusal" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let empty = begin_source_registration(
    source,
    catalog,
    { ..limits, max_work: 0, },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(empty), RegistrationFailed)
  assert_eq(source_registration_collection_work(empty), 0)
  assert_true(
    take_source_registration_result(empty) is Some(Err(Declarations(WorkLimit))),
  )
  clear_source_registration(empty)
  assert_eq(source_registration_phase(empty), RegistrationTransferred)
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=0,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(read), RegistrationSelect)
  let inputs = source_registration_collected_inputs(read).unwrap()
  let spent = @source_inputs.work(inputs)
  assert_true(spent > 0)
  assert_eq(advance_source_registration(read), RegistrationFailed)
  assert_eq(advance_source_registration(read), RegistrationFailed)
  assert_true(
    physical_equal(source_registration_collected_inputs(read).unwrap(), inputs),
  )
  assert_true(
    take_source_registration_result(read)
    is Some(Err(Selection({ kind: InputLimit, .. }))),
  )
  assert_eq(source_registration_collection_work(read), spent)
  clear_source_registration(read)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
}

///|
test "original Source registration preserves pipeline one-short and Local refusal boundaries" {
  let (source, catalog, limits, registered_work) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    { ..limits, max_work: registered_work - 1, },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(read), RegistrationSelect)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_eq(advance_source_registration(read), RegistrationFailed)
  assert_true(
    take_source_registration_result(read) is Some(Err(Registration(WorkLimit))),
  )
  let read = begin_source_registration(
    source,
    catalog,
    { ..limits, max_nodes: 0, },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(read), RegistrationSelect)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(advance_source_registration(read), RegistrationFailed)
  assert_true(
    take_source_registration_result(read) is Some(Err(LocalInputs(_))),
  )
}

///|
test "original Source registration clearing retires only its own untransferred aliases" {
  let (source, catalog, limits, _) = registration_read_fixture()
  for collected in [false, true] {
    let read = begin_source_registration(
      source,
      catalog,
      limits,
      max_inputs=2,
      max_views=100,
      max_order_keys=100,
    ).unwrap()
    if collected {
      assert_eq(advance_source_registration(read), RegistrationSelect)
      assert_true(source_registration_collected_inputs(read) is Some(_))
    }
    let spent = source_registration_collection_work(read)
    clear_source_registration(read)
    clear_source_registration(read)
    assert_eq(advance_source_registration(read), RegistrationRetired)
    assert_true(source_registration_collected_inputs(read) is None)
    assert_true(take_source_registration_result(read) is None)
    assert_eq(source_registration_collection_work(read), spent)
  }
  assert_true(
    begin_source_registration(
      source,
      catalog,
      limits,
      max_inputs=2,
      max_views=100,
      max_order_keys=-1,
    )
    is Err(InvalidLimits),
  )
  assert_eq(source_registration_initial_construction_extent(), {
    record_headers: 5L,
    reference_slots: 8L,
    scalar_words: 7L,
  })
}
