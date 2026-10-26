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
