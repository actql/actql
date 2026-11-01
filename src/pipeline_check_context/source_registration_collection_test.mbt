///|
test "Source registration collection quote retains the same original observation without collecting twice" {
  let (source, catalog, limits, _) = registration_read_fixture()
  let read = begin_source_registration(
    source,
    catalog,
    limits,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(source_registration_collection_inspection_work(read) is None)
  assert_true(source_registration_collection_construction(read) is None)
  let maximum = source_registration_collection_inspection_bound(read).unwrap()
  let first = observe_source_registration_collection_construction(read)
  let work = first.unwrap()
  assert_true(work > 0L && work <= maximum)
  assert_true(
    physical_equal(
      first,
      observe_source_registration_collection_construction(read),
    ),
  )
  assert_true(
    physical_equal(first, source_registration_collection_inspection_work(read)),
  )
  let quote = source_registration_collection_construction(read).unwrap()
  assert_eq(source_registration_collection_construction(read), Some(quote))
  assert_eq(source_registration_phase(read), RegistrationCollect)
  assert_true(source_registration_collected_inputs(read) is None)
  assert_eq(source_registration_collection_work(read), 0)
  assert_eq(@source_inputs.collect_construction_geometry_extent(), {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 21L,
  })
  assert_eq(source_registration_collection_inspection_retained_extent(), {
    record_headers: 4L,
    reference_slots: 3L,
    scalar_words: 24L,
  })
  let peak = source_registration_collection_inspection_extent()
  assert_true(
    peak.record_headers >= 4L &&
    peak.reference_slots >= 3L &&
    peak.scalar_words >= 24L,
  )
  assert_eq(advance_source_registration(read), RegistrationSelect)
  let inputs = source_registration_collected_inputs(read).unwrap()
  assert_true(physical_equal(@source_inputs.source(inputs), source))
  assert_eq(@source_inputs.count(inputs), 2)
  assert_true(source_registration_collection_work(read) > 0)
  assert_true(observe_source_registration_collection_construction(read) is None)
  assert_true(source_registration_collection_construction(read) is None)
  assert_eq(source_registration_collection_inspection_work(read), first)
  assert_eq(advance_source_registration(read), RegistrationPipeline)
  assert_eq(advance_source_registration(read), RegistrationLocal)
  assert_eq(complete_registration_local(read), RegistrationComplete)
  let (views, _) = take_source_registration_result(read).unwrap().unwrap()
  assert_true(
    physical_equal(
      @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
      inputs,
    ),
  )
  assert_true(source_registration_collection_inspection_work(read) is None)
  clear_source_registration(read)
  assert_eq(source_registration_phase(read), RegistrationTransferred)
  assert_true(source_registration_collection_construction(read) is None)
}

///|
test "Source collection metadata preserves original zero-work refusal and untransferred retirement" {
  let (source, catalog, limits, _) = registration_read_fixture()
  for finish in [true, false] {
    let read = begin_source_registration(
      source,
      catalog,
      { ..limits, max_work: 0, },
      max_inputs=2,
      max_views=100,
      max_order_keys=100,
    ).unwrap()
    let work = observe_source_registration_collection_construction(read).unwrap()
    assert_true(work > 0L)
    assert_true(source_registration_collection_construction(read) is Some(_))
    if finish {
      assert_eq(advance_source_registration(read), RegistrationFailed)
      assert_eq(source_registration_collection_work(read), 0)
      assert_eq(
        source_registration_collection_inspection_work(read),
        Some(work),
      )
      assert_true(
        take_source_registration_result(read)
        is Some(Err(Declarations(WorkLimit))),
      )
    }
    clear_source_registration(read)
    assert_true(source_registration_collection_inspection_work(read) is None)
    assert_true(source_registration_collection_inspection_bound(read) is None)
    assert_true(
      observe_source_registration_collection_construction(read) is None,
    )
    assert_true(source_registration_collection_construction(read) is None)
    assert_eq(
      source_registration_phase(read),
      if finish {
        RegistrationTransferred
      } else {
        RegistrationRetired
      },
    )
  }
}
