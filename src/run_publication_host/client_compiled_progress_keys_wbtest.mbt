///|
test "compiled Pure progress retains the original fragment keys without reconstructing nodes" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "compiled-progress-keys",
  )
  let keys = compilation.standard_progress_keys.unwrap()
  let progress = inspect_client_remote_task_progress(
    prepared,
    compilation,
    admission,
    definition,
    retained_input_cid("c"),
    [],
  ).unwrap()
  assert_true(physical_equal(keys, progress.keys))
  assert_eq(keys.length(), 2)
  let fields = client_remote_task_progress_fields(progress)
  let original = keys[0]
  fields[0][1] = "foreign-copy"
  assert_eq(keys[0], original)
  assert_eq(client_remote_task_progress_fields(progress)[0][1], original)
}

///|
test "compiled Effect progress retains exact keys and unchanged cancellation meaning" {
  let baseline = effect_projection_fixture()
  let prepared = baseline.allowed.compilation.owner
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    normalization=Some(
      issue_prepared_client_effect_local_update_normalization(prepared).unwrap(),
    ),
  ).unwrap()
  let keys = compilation.compiled.standard_progress_keys.unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    retained_input_cid("a"),
    retained_input_cid("b"),
    "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "scope", "compiled-effect-keys", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  let progress = inspect_client_remote_effect_task_progress(
    allowed,
    definition,
    retained_input_cid("c"),
    [],
  ).unwrap()
  assert_true(physical_equal(keys, progress.progress.keys))
  assert_eq(keys, baseline.progress.keys)
  let projected = project_client_remote_effect_task_run(
    progress,
    "2026-10-09T00:01:00.000Z",
    true,
    effect_projection_claims(progress),
  ).unwrap()
  assert_eq(
    effect_projection_state(projected).get("status"),
    Some(Json::string("preparing")),
  )
  assert_true(
    inspect_client_remote_effect_task_progress(
      allowed,
      baseline.progress.definition,
      retained_input_cid("c"),
      [],
    )
    is Err(_),
  )
}

///|
test "nonstandard compilation bounds keep the original progress reconstruction path" {
  let (prepared, standard, _, _) = retained_input_run("standard-progress-keys")
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    1000001,
    100000,
    100,
  ).unwrap()
  assert_eq(compilation.standard_progress_keys, None)
  let allowed = issue_client_task_compiled_run(
    prepared,
    compilation,
    retained_input_cid("a"),
    retained_input_cid("b"),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    allowed, "scope", "custom-progress-keys", "2026-10-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let progress = inspect_client_remote_task_progress(
    prepared,
    compilation,
    client_compiled_run_admission(allowed),
    definition,
    retained_input_cid("c"),
    [],
  ).unwrap()
  assert_eq(progress.keys, standard.standard_progress_keys.unwrap())
}

///|
test "compiled progress key reuse requires the existing complete sequence and encoding bounds" {
  let standard = client_standard_values_sequence_limits()
  assert_true(
    client_task_graph_standard_progress_limits(standard, 1000000, 100000, 100),
  )
  assert_true(
    client_task_graph_standard_progress_limits(standard, 100000, 10000, 50),
  )
  for
    sequence in [
      { ..standard, max_steps: standard.max_steps + 1, },
      { ..standard, max_rows: standard.max_rows + 1, },
      { ..standard, max_cells: standard.max_cells + 1, },
      { ..standard, max_bindings: standard.max_bindings + 1, },
      { ..standard, max_name_bytes: standard.max_name_bytes + 1, },
      {
        ..standard,
        expressions: {
          ..standard.expressions,
          max_work: standard.expressions.max_work + 1,
        },
      },
    ] {
    assert_true(
      !client_task_graph_standard_progress_limits(
        sequence, 1000000, 100000, 100,
      ),
    )
  }
  assert_true(
    !client_task_graph_standard_progress_limits(standard, 1000001, 100000, 100),
  )
  assert_true(
    !client_task_graph_standard_progress_limits(standard, 1000000, 100001, 100),
  )
  assert_true(
    !client_task_graph_standard_progress_limits(standard, 1000000, 100000, 101),
  )
}
