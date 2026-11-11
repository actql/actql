///|
test "selected Values row limit preserves checker identity and other budgets" {
  let rows = Array::makei(121, index => {
    "{\"id\":" + (index + 1).to_string() + "}"
  }).join(",")
  let document = "{\"version\":\"actql/0.1\",\"id\":\"read-121\",\"stages\":[{\"id\":\"source\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    rows +
    "]},\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"source\",\"result\":\"rows\"}}}}"
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let standard = prepared_client_values_sequence_limits(prepared)
  // The default covers the actual 121 authored rows. An explicit smaller
  // envelope still refuses the same unchanged input.
  assert_eq(standard.max_rows, 121)
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared, 0, standard, 100000, 10000, 100,
    )
    is Ok(_),
  )
  let short = with_prepared_client_values_row_limit(prepared, 120).unwrap()
  assert_true(
    emit_prepared_client_values_pipeline(
      short,
      0,
      prepared_client_values_sequence_limits(short),
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let selected = with_prepared_client_values_row_limit(prepared, 121).unwrap()
  let limits = prepared_client_values_sequence_limits(selected)
  assert_eq(limits.max_rows, 121)
  assert_eq(limits.max_cells, standard.max_cells)
  assert_eq(limits.max_bindings, standard.max_bindings)
  assert_eq(limits.expressions, standard.expressions)
  assert_eq(
    prepared_client_identity(selected),
    prepared_client_identity(prepared),
  )
  assert_eq(
    prepared_client_check_environment_cid(selected),
    prepared_client_check_environment_cid(prepared),
  )
  assert_true(
    emit_prepared_client_values_pipeline(
      selected, 0, limits, 100000, 10000, 100,
    )
    is Ok(_),
  )
  assert_true(with_prepared_client_values_row_limit(prepared, 0) is None)
  for rows in [10001, 100000, 2147483647] {
    let larger = with_prepared_client_values_row_limit(prepared, rows).unwrap()
    let larger_limits = prepared_client_values_sequence_limits(larger)
    assert_eq(larger_limits.max_rows, rows)
    assert_eq(larger_limits.max_cells, standard.max_cells)
    assert_eq(larger_limits.expressions, standard.expressions)
    assert_eq(
      prepared_client_identity(larger),
      prepared_client_identity(prepared),
    )
  }
  assert_true(with_prepared_client_values_row_limit(prepared, -1) is None)
  assert_eq(prepared_client_values_sequence_limits(prepared).max_rows, 121)
}

///|
test "task compilation uses checked authored demand beyond the old Local default" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for count in [101, 1000] {
    let rows = Array::makei(count, index => "{\"id\":" + index.to_string() + "}").join(
      ",",
    )
    let document = "{\"version\":\"actql/0.1\",\"id\":\"compile-demand\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
      rows +
      "]},\"as\":\"v\"}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
    let prepared = prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      client_standard_program_preparation_limits(),
    ).unwrap()
    let limits = prepared_client_values_sequence_limits(prepared)
    assert_eq(limits.max_rows, count)
    let compilation = issue_prepared_client_task_compilation(
      prepared,
      run_materials_manifests(),
      limits,
      1000,
      1000,
      65536,
      8192,
      64,
    ).unwrap()
    assert_eq(client_task_compilation_result_names(compilation), ["answer"])
    assert_true(
      issue_prepared_client_task_compilation(
        prepared,
        run_materials_manifests(),
        { ..limits, max_rows: count - 1, },
        1000,
        1000,
        65536,
        8192,
        64,
      )
      is Err(_),
    )
  }
}
