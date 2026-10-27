///|
test "Local Values publication preserves the existing finite transport and value bounds" {
  let prepared = local_values_guard_prepared()
  let (row, output) = @client_local_host.client_local_values_publication_limits(
    prepared, 536870912,
  ).unwrap()
  // Independent expectations from the existing Local execution envelope.
  assert_eq(row.max_bytes, 65536)
  assert_eq(row.max_nodes, 10000)
  assert_eq(row.max_depth, 64)
  assert_eq(row.max_text_bytes, 65536)
  assert_eq(output.max_rows, 100)
  assert_eq(output.max_result_fields, 100)
  assert_eq(output.max_result_mapping_work, 10000)
  assert_eq(output.max_result_workspace_entries, 10000)
  assert_eq(output.values.max_nodes, 20000)
  assert_eq(output.values.max_text_bytes, 500000)
  assert_eq(output.values.max_depth, 100)
  assert_eq(output.values.max_work, 20000000)
  for wire in [output.logical_wire, output.payload_wire] {
    assert_eq(wire.max_columns, 100)
    assert_eq(wire.max_order_work, 1000000)
    assert_eq(wire.max_bytes, 1000000)
    assert_eq(wire.max_nodes, 100000)
    assert_eq(wire.max_depth, 64)
  }
  assert_eq(output.schema.max_bytes, 65536)
  assert_eq(output.max_batch_bytes, 65536)
}

///|
test "Local Values publication intersects a smaller installed Store ceiling" {
  let prepared = local_values_guard_prepared()
  let (_, output) = @client_local_host.client_local_values_publication_limits(
    prepared, 17,
  ).unwrap()
  assert_eq(output.logical_wire.max_bytes, 17)
  assert_eq(output.payload_wire.max_bytes, 17)
  assert_eq(output.schema.max_bytes, 17)
  assert_eq(output.max_batch_bytes, 17)
  assert_eq(output.max_rows, 100)
  assert_eq(output.values.max_work, 20000000)
  for invalid in [0, -1] {
    assert_true(
      @client_local_host.client_local_values_publication_limits(
        prepared, invalid,
      )
      is None,
    )
  }
}

///|
test "CLI supported SELECT text reaches the original Local Values Owner without JSON repair" {
  let environment = local_values_guard_environment()
  let context = @frontend.bind_query_context(
    [],
    @program_check.checking_environment_cid(environment),
  ).unwrap()
  for format in [@frontend.Sql, @frontend.Text] {
    let lowered = @frontend.lower("SELECT 1 AS n", format, Some(context)).unwrap()
    let parsed = match lowered.program {
      Some(value) => value
      None =>
        @syntax.parse(
          lowered.document,
          @publication_host.client_standard_program_preparation_limits().checking.input,
          format=lowered.format,
        ).unwrap()
    }
    let prepared = @publication_host.prepare_parsed_effect_free_client_program(
      parsed,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 0)
    assert_eq(@publication_host.prepared_client_result_count(prepared), 1)
    let setup = @client_local_host.open_source_free_local_retained_host(
      prepared,
      @client_local_host.prepare_installed_sequence_contracts(
        @identity.stringify_value(registered_body(), 100000, 10000, 100),
        @identity.stringify_value(registered_values(), 100000, 10000, 100),
        Some(
          @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
        ),
        None,
      ).unwrap(),
      @identity.stringify_value(registered_values(), 100000, 10000, 100),
      1L,
      0L,
      0L,
      0L,
      fragment_body=Some(
        @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
      ),
    ).unwrap()
    let execution = @client_local_host.execute_source_free_values_guarded(
      setup,
      16,
      1000,
      () => true,
    ).unwrap()
    assert_eq(execution.rows().unwrap(), ["{\"n\":1}"])
    assert_true(execution.close())
    assert_true(execution.close())
  }
}
