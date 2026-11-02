///|
fn selected_model_limits_composition_fixture(
  read_retained : Int64,
) -> @infer_host.Limits {
  let selected = @infer_host.standard_limits()
  {
    ..selected,
    model: {
      ..selected.model,
      ledger: {
        planning_work: 3,
        attempts: 4,
        holdings: 5,
        transfer_bytes: 6L,
        retained_bytes: 10L,
        execution_bytes: 20L,
      },
    },
    mapping: {
      ..selected.mapping,
      logical: {
        ..selected.mapping.logical,
        max_live_value_bytes: read_retained,
      },
    },
    identity: {
      ..selected.identity,
      wire: { ..selected.identity.wire, max_bytes: 13, },
    },
  }
}

///|
test "physical Model recipe reads the same stored Model ledger separately from legacy read allowances" {
  let selected = selected_model_limits_composition_fixture(7L)
  let model = client_program_composed_infer_model_ledger_bytes(selected)
  assert_eq(model, [10L, 20L])
  assert_eq(client_program_composed_infer_retained_limits(selected).length(), 9)
  assert_eq(client_program_composed_infer_retained_limits(selected)[4], 7L)
  assert_eq(client_program_composed_infer_retained_limits(selected)[5], 13L)
  model[0] = 999L
  assert_eq(selected.model.ledger.retained_bytes, 10L)
  assert_eq(client_program_composed_infer_model_ledger_bytes(selected), [
    10L, 20L,
  ])
}

///|
// This calls the existing actual Pure/Effect requirement consumer, not an
// ordinary Model operation or an assertion that these DATA bounds are funded.
test "Model limit composition cannot admit a positive wrapped read overlap" {
  let selected = selected_model_limits_composition_fixture(9223372036854775807L)
  let base = [1L, 2L, 3L, 4L, 5L, 6L]
  assert_true(
    combine_installed_mock_model_run_requirements(base, selected)
    is Err(InsufficientCapacity),
  )
  assert_eq(base, [1L, 2L, 3L, 4L, 5L, 6L])
}

///|
test "Model limit controls preserve original vector and selected census fields" {
  let selected = selected_model_limits_composition_fixture(11L)
  let selected = {
    ..selected,
    input: {
      ..selected.input,
      rows: {
        ..selected.input.rows,
        operation_entries: 17,
        retained_entries: 19,
        metadata_entries: 23,
      },
    },
  }
  let base = [1L, 2L, 3L, 4L, 5L, 6L]
  let result = combine_installed_mock_model_run_requirements(base, selected).unwrap()
  assert_true(physical_equal(result, base))
  assert_eq(result, [
    4L, 6L, 8L, 10L, 37L, 52L, 11L, 13L, 11L, 13L, 11L, 13L, 17L, 19L, 23L,
  ])
}

///|
test "retained Model bounds project the same stored consumer fields before a Run" {
  let selected = selected_model_limits_composition_fixture(11L)
  let selected = {
    ..selected,
    input: {
      ..selected.input,
      rows: {
        ..selected.input.rows,
        operation_entries: 17,
        retained_entries: 19,
        metadata_entries: 23,
      },
    },
  }
  // These are deliberately different from the consumer's read/Model pairs.
  // A projection must not replace the existing allowances with Ledger totals.
  assert_eq(selected.model.ledger.retained_bytes, 10L)
  assert_eq(selected.model.ledger.execution_bytes, 20L)
  let fields = client_program_composed_infer_retained_limits(selected)
  assert_eq(fields, [11L, 13L, 11L, 13L, 11L, 13L, 17L, 19L, 23L])
  fields[0] = 999L
  assert_eq(client_program_composed_infer_retained_limits(selected), [
    11L, 13L, 11L, 13L, 11L, 13L, 17L, 19L, 23L,
  ])
}

///|
test "Model limit controls admit exact Int64 overlap without cross-dimension restriction" {
  let selected = selected_model_limits_composition_fixture(4611686018427387903L)
  let selected = {
    ..selected,
    model: {
      ..selected.model,
      ledger: { ..selected.model.ledger, retained_bytes: 0L, },
    },
  }
  let result = combine_installed_mock_model_run_requirements(
    [1L, 2L, 3L, 4L, 1L, 6L],
    selected,
  ).unwrap()
  assert_eq(result[4], 9223372036854775807L)
  assert_eq(result[5], 52L)
}

///|
test "Model limit controls refuse invalid base without partial mutation" {
  let selected = selected_model_limits_composition_fixture(11L)
  for
    base in [
      [],
      [1L, 2L, 3L, 4L, 5L],
      [-1L, 2L, 3L, 4L, 5L, 6L],
      [2147483648L, 2L, 3L, 4L, 5L, 6L],
      [2147483647L, 2L, 3L, 4L, 5L, 6L],
      [1L, 2L, 3L, -1L, 5L, 6L],
      [1L, 2L, 3L, 4L, 9223372036854775807L, 6L],
      [1L, 2L, 3L, 4L, 5L, 9223372036854775807L],
    ] {
    let before = base.copy()
    assert_true(
      combine_installed_mock_model_run_requirements(base, selected)
      is Err(InsufficientCapacity),
    )
    assert_eq(base, before)
  }
}
