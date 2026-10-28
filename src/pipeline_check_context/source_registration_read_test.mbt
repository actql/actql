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
  assert_eq(complete_registration_local(read), RegistrationComplete)
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
  assert_eq(complete_registration_local(read), RegistrationFailed)
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
    reference_slots: 10L,
    scalar_words: 9L,
  })
}

///|
test "original Source registration retains new selection work without recharging collection" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(source_registration_selection_work(read), 0)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  let collected = source_registration_collected_inputs(read).unwrap()
  let prefix = source_registration_collection_work(read)
  assert_eq(prefix, @source_inputs.work(collected))
  assert_eq(source_registration_selection_work(read), 0)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  let selected = source_registration_selection_work(read)
  assert_true(selected > 0)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(complete_registration_local(read), RegistrationComplete)
  assert_eq(advance_source_registration(read), RegistrationComplete)
  let (views, _) = take_source_registration_result(read).unwrap().unwrap()
  let resolved = @sourceviews.pipeline_resolution(views)
  assert_true(physical_equal(@sourceviews.inputs(resolved), collected))
  assert_eq(@sourceviews.work(resolved), prefix + selected)
  clear_source_registration(read)
  assert_eq(source_registration_selection_work(read), selected)
  assert_eq(source_registration_collection_work(read), prefix)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  // A distinct original reader under a tighter original budget: the first
  // Catalog root's field-count charge refuses before any new selection work.
  let short = begin_source_registration(
    source,
    catalog,
    { ..limits, max_work: prefix + 1, },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(short), RegistrationSelect)
  assert_eq(advance_source_registration(short), RegistrationFailed)
  assert_true(
    take_source_registration_result(short)
    is Some(Err(Selection({ kind: WorkLimit, .. }))),
  )
  assert_eq(source_registration_collection_work(short), prefix)
  assert_eq(source_registration_selection_work(short), 0)
}

///|
test "original Source registration retains new pipeline work without recharging resolution" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(source_registration_pipeline_work(read), 0)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_eq(source_registration_pipeline_work(read), 0)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  // The authored fixture has two Stages, two remote declarations, and the
  // original names remote(6) and remote_again(12): new work2+2+6+12 =22.
  assert_eq(source_registration_pipeline_work(read), 22)
  assert_eq(complete_registration_local(read), RegistrationComplete)
  let (views, _) = take_source_registration_result(read).unwrap().unwrap()
  let resolved = @sourceviews.pipeline_resolution(views)
  let inherited = @sourceviews.work(resolved)
  assert_eq(@sourceviews.count(resolved), 2)
  assert_eq(@sourceviews.pipeline_inputs_work(views), inherited + 22)
  assert_eq(
    inherited,
    source_registration_collection_work(read) +
    source_registration_selection_work(read),
  )
  clear_source_registration(read)
  assert_eq(source_registration_pipeline_work(read), 22)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  let (result, spent) = @sourceviews.observe_prepare_pipeline_inputs(
    resolved,
    inherited + 22,
  )
  let registered = result.unwrap()
  assert_true(
    physical_equal(@sourceviews.pipeline_resolution(registered), resolved),
  )
  assert_eq(spent, 22)
  for
    (extra, expected) in [
      (-1, 0),
      (0, 0),
      (1, 0),
      (2, 2),
      (4, 4),
      (10, 10),
      (21, 10),
    ] {
    let (result, spent) = @sourceviews.observe_prepare_pipeline_inputs(
      resolved,
      inherited + extra,
    )
    assert_true(result is Err(WorkLimit))
    assert_eq(spent, expected)
  }
  let (result, spent) = @sourceviews.observe_prepare_pipeline_inputs(
    resolved, -1,
  )
  assert_true(result is Err(InvalidLimits))
  assert_eq(spent, 0)
  let short = begin_source_registration(
    source,
    catalog,
    { ..limits, max_work: inherited + 21, },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(short), RegistrationSelect)
  assert_eq(advance_source_registration(short), RegistrationPipeline)
  assert_eq(advance_source_registration(short), RegistrationFailed)
  assert_true(
    take_source_registration_result(short) is Some(Err(Registration(WorkLimit))),
  )
  assert_eq(source_registration_pipeline_work(short), 10)
  clear_source_registration(short)
  assert_eq(source_registration_pipeline_work(short), 10)
  assert_eq(source_registration_phase(short), RegistrationTransferred)
}

///|
test "original registration binds and retains resolver construction metadata once" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(source_registration_resolution_inspection_bound(read) is None)
  assert_true(observe_source_registration_resolution_construction(read) is None)
  assert_true(source_registration_resolution_construction(read) is None)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  let original = source_registration_collected_inputs(read).unwrap()
  let maximum = source_registration_resolution_inspection_bound(read).unwrap()
  let work = observe_source_registration_resolution_construction(read).unwrap()
  assert_true(work > 0L && work <= maximum)
  assert_eq(
    observe_source_registration_resolution_construction(read),
    Some(work),
  )
  assert_eq(source_registration_resolution_inspection_work(read), Some(work))
  let quote = source_registration_resolution_construction(read).unwrap()
  assert_eq(source_registration_resolution_construction(read), Some(quote))
  assert_true(
    physical_equal(
      source_registration_collected_inputs(read).unwrap(),
      original,
    ),
  )
  let held = source_registration_resolution_inspection_retained_extent()
  let peak = source_registration_resolution_inspection_extent()
  assert_true(
    held.record_headers <= peak.record_headers &&
    held.reference_slots <= peak.reference_slots &&
    held.scalar_words <= peak.scalar_words,
  )
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_true(observe_source_registration_resolution_construction(read) is None)
  assert_true(source_registration_resolution_construction(read) is None)
  assert_eq(source_registration_resolution_inspection_work(read), Some(work))
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(complete_registration_local(read), RegistrationComplete)
  let (views, _) = take_source_registration_result(read).unwrap().unwrap()
  assert_true(
    physical_equal(
      @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
      original,
    ),
  )
  assert_true(source_registration_resolution_inspection_work(read) is None)
  clear_source_registration(read)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  assert_true(source_registration_resolution_construction(read) is None)
}

///|
test "original registration pipeline construction uses only same held resolution and limits" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(source_registration_pipeline_construction(read) is None)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  assert_true(source_registration_pipeline_construction(read) is None)
  let original_inputs = source_registration_collected_inputs(read).unwrap()
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  let quote = source_registration_pipeline_construction(read).unwrap()
  // Original fixture2Stages/2entries: Array count3, reference items4.
  assert_eq(quote.returned, {
    record_headers: 15L,
    reference_slots: 59L,
    scalar_words: 10L,
  })
  assert_eq(source_registration_pipeline_construction(read), Some(quote))
  assert_eq(source_registration_pipeline_work(read), 0)
  assert_true(
    physical_equal(
      source_registration_collected_inputs(read).unwrap(),
      original_inputs,
    ),
  )
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_true(source_registration_pipeline_construction(read) is None)
  assert_eq(source_registration_pipeline_work(read), 22)
  assert_eq(complete_registration_local(read), RegistrationComplete)
  let (pipeline, _) = take_source_registration_result(read).unwrap().unwrap()
  let resolved = @sourceviews.pipeline_resolution(pipeline)
  assert_true(physical_equal(@sourceviews.inputs(resolved), original_inputs))
  assert_eq(
    quote,
    @sourceviews.pipeline_preparation_construction(resolved, limits.max_work).unwrap(),
  )
  clear_source_registration(read)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  assert_true(source_registration_pipeline_construction(read) is None)
  assert_eq(source_registration_initial_construction_extent(), {
    record_headers: 5L,
    reference_slots: 10L,
    scalar_words: 9L,
  })
}

///|
// These finite original fixtures have two Stages and at most two snapshots.
// This is a test observation bound, never a product budget or changed oracle.
fn complete_registration_local(
  read : SourceRegistrationRead,
) -> SourceRegistrationPhase raise {
  let mut steps = 0
  while source_registration_phase(read) == RegistrationLocal {
    assert_true(steps < 20)
    let _ = advance_source_registration(read)
    steps += 1
  }
  source_registration_phase(read)
}

///|
test "original registration keeps one private Local continuation through its actual phases" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(source_registration_local_phase(read) is None)
  assert_eq(advance_source_registration(read), RegistrationSelect)
  let original = source_registration_collected_inputs(read).unwrap()
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_true(source_registration_local_phase(read) is None)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(
    source_registration_local_phase(read),
    Some(@local_inputs.LocalEnvironmentIndex),
  )
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(
    source_registration_local_phase(read),
    Some(@local_inputs.LocalEnvironmentGroups),
  )
  assert_eq(complete_registration_local(read), RegistrationComplete)
  assert_eq(
    source_registration_local_phase(read),
    Some(@local_inputs.LocalEnvironmentTransferred),
  )
  let (pipeline, locals) = take_source_registration_result(read)
    .unwrap()
    .unwrap()
  assert_true(
    physical_equal(
      @sourceviews.inputs(@sourceviews.pipeline_resolution(pipeline)),
      original,
    ),
  )
  assert_true(physical_equal(@local_inputs.environment_program(locals), source))
  assert_true(source_registration_local_phase(read) is None)
  clear_source_registration(read)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  assert_true(take_source_registration_result(read) is None)
}

///|
test "original registration retains failed Local handoff and clears only its own child aliases" {
  let (source, catalog, limits, _) = registration_read_fixture()
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
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(
    source_registration_local_phase(read),
    Some(@local_inputs.LocalEnvironmentIndex),
  )
  assert_eq(complete_registration_local(read), RegistrationFailed)
  // The child handed off its actual typed error once, retaining the failed
  // frame aliases until this original registration is taken/cleared.
  assert_eq(
    source_registration_local_phase(read),
    Some(@local_inputs.LocalEnvironmentTransferred),
  )
  let failed_at = source_registration_local_failure_phase(read)
  assert_true(failed_at is Some(_))
  assert_eq(advance_source_registration(read), RegistrationFailed)
  assert_eq(source_registration_local_failure_phase(read), failed_at)
  assert_true(
    take_source_registration_result(read) is Some(Err(LocalInputs(_))),
  )
  assert_true(source_registration_local_phase(read) is None)
  clear_source_registration(read)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  assert_true(take_source_registration_result(read) is None)
  let pending = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_eq(advance_source_registration(pending), RegistrationSelect)
  assert_eq(advance_source_registration(pending), RegistrationPipeline)
  assert_eq(advance_source_registration(pending), RegistrationLocal)
  assert_eq(advance_source_registration(pending), RegistrationLocal)
  assert_eq(advance_source_registration(pending), RegistrationLocal)
  assert_eq(
    source_registration_local_phase(pending),
    Some(@local_inputs.LocalEnvironmentGroups),
  )
  clear_source_registration(pending)
  assert_eq(source_registration_phase(pending), RegistrationRetired)
  assert_true(source_registration_local_phase(pending) is None)
  assert_eq(advance_source_registration(pending), RegistrationRetired)
  assert_true(take_source_registration_result(pending) is None)
}
