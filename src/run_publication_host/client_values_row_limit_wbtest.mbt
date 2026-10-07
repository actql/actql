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
  assert_eq(standard.max_rows, 100)
  assert_true(
    emit_prepared_client_values_pipeline(
      prepared, 0, standard, 100000, 10000, 100,
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
  assert_true(with_prepared_client_values_row_limit(prepared, 10001) is None)
  assert_eq(prepared_client_values_sequence_limits(prepared).max_rows, 100)
}
