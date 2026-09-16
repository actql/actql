///|
fn retained_join_validation_fixture(
  options : String,
  source_owner? : @lower.BoundPrepared = capture_fixture(),
) -> (
  @lower.BoundPrepared,
  @lower.PreparedInnerJoin,
  ProducerRead,
  ProducerRead,
  Ref[Bool],
) raise {
  let owner = source_owner
  let receiver = typed_receiver(
    owner,
    "[{\"join\":{\"with\":\"prior\",\"kind\":\"inner\",\"on\":[{\"left\":\"n\",\"right\":\"n\"}],\"select\":{\"n\":\"left.n\"}" +
    options +
    "}}]",
  )
  let profile = @lower.join_kernel_profile(
    @lower.prepare_join_kernel(receiver, 0, 100, 10000).unwrap(),
  )
  let source = export_fixture(owner)
  let memory = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    1000,
    10000,
  ).unwrap()
  let (receipt, text) = export_all(source)
  let live = Ref(true)
  let handle = retain_admitted_output_stream(
    completed_export_content(receipt),
    text,
    fn() { live.val },
  )
  let held = bind_completed_output_export(
    receipt,
    retained_output_material(handle),
  ).unwrap()
  let retained = rebind_producer_representation(memory, held).unwrap()
  (receiver, profile, memory, retained, live)
}

///|
test "shape-only join preflight accepts exact retained inputs with unchanged work limits" {
  let (owner, profile, memory, retained, live) = retained_join_validation_fixture(
    "",
  )
  let limits = { max_rows: 2, max_work: 1000, max_entries: 100, }
  assert_false(producer_read_has_cell_access(retained))
  let baseline = validate_fixed_join_inputs(owner, profile, [memory], limits).unwrap()
  let validated = validate_fixed_join_inputs(owner, profile, [retained], limits).unwrap()
  assert_eq(
    fixed_join_validation_usage(baseline),
    fixed_join_validation_usage(validated),
  )
  assert_true(
    fixed_join_validation_matches(validated, owner, profile, [retained]),
  )
  assert_false(
    fixed_join_validation_matches(validated, owner, profile, [memory]),
  )
  let (work, peak) = fixed_join_validation_usage(validated)
  assert_true(
    validate_fixed_join_inputs(owner, profile, [retained], {
      max_rows: 2,
      max_work: work,
      max_entries: peak,
    })
    is Ok(_),
  )
  assert_true(
    validate_fixed_join_inputs(owner, profile, [retained], {
      max_rows: 2,
      max_work: work - 1,
      max_entries: peak,
    })
    is Err(RowLimit),
  )
  assert_true(
    validate_fixed_join_inputs(owner, profile, [retained], {
      max_rows: 1,
      max_work: 1000,
      max_entries: 100,
    })
    is Err(RowLimit),
  )
  live.val = false
  assert_false(
    fixed_join_validation_matches(validated, owner, profile, [retained]),
  )
  assert_true(
    validate_fixed_join_inputs(owner, profile, [retained], limits)
    is Err(InputMismatch),
  )
  assert_true(producer_read_available(memory))
}

///|
test "shape-only retained validation never discharges value-sensitive join obligations" {
  for options in [",\"cardinality\":\"one_to_one\"", ",\"null_key\":\"fail\""] {
    let (owner, profile, memory, retained, _) = retained_join_validation_fixture(
      options,
    )
    let limits = { max_rows: 2, max_work: 1000, max_entries: 100, }
    assert_true(
      validate_fixed_join_inputs(owner, profile, [memory], limits) is Ok(_),
    )
    assert_true(
      validate_fixed_join_inputs(owner, profile, [retained], limits)
      is Err(InputMismatch),
    )
  }
}
