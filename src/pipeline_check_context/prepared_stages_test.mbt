///|
test "Local Stage integration shares exact budgets and retains preparation owners" {
  let prepared = prepared_stage_fixture()
  let apps = Array::makei(2, i => prepared_stage_applications(prepared, i))
  let checked = check_prepared_local_stages(
    prepared,
    apps,
    policy(),
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  assert_true(
    physical_equal(
      stage_operations(checked),
      @stage_results.local_source_operations(prepared),
    ),
  )
  assert_true(
    physical_equal(
      stage_results(checked),
      @stage_results.local_source_results(prepared),
    ),
  )
  let (work, text) = stage_usage(checked)
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=work,
      max_text_bytes=text,
      proof_owners=Some([[], []]),
      input_owners=Some([[], []]),
    )
    is Ok(_),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
  let contexts = Array::makei(2, i => stage_context_at(checked, i).unwrap())
  let manual = attach_stage_contexts(
    stage_operations(checked),
    stage_results(checked),
    contexts,
    policy(),
    max_work=work,
    max_text_bytes=text,
  ).unwrap()
  let (manual_work, manual_text) = stage_usage(manual)
  assert_eq(work, manual_work + 2)
  assert_eq(text, manual_text)
}

///|
test "Local Stage integration rejects late foreign evidence and malformed ownership collections" {
  let prepared = prepared_stage_fixture()
  let foreign = prepared_stage_fixture()
  let apps = Array::makei(2, i => prepared_stage_applications(prepared, i))
  assert_true(
    check_prepared_local_stages(
      prepared,
      [apps[0], prepared_stage_applications(foreign, 1)],
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
    )
    is Err(Stage(1, Context(Capacity(ForeignPipeline(_))))),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      [],
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
    )
    is Err(StageCount),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
      proof_owners=Some([]),
    )
    is Err(StageCount),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=10000000,
      max_text_bytes=10000000,
      input_owners=Some([]),
    )
    is Err(StageCount),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=-1,
      max_text_bytes=10000000,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    check_prepared_local_stages(
      prepared,
      apps,
      policy(),
      max_work=10000000,
      max_text_bytes=-1,
    )
    is Err(InvalidLimits),
  )
}
