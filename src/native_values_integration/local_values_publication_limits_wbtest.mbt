///|
fn publication_requirements(
  prepared : @publication_host.PreparedClientProgram,
) -> @client_local_host.ClientLocalRequirements raise {
  @client_local_host.prepare_source_free_local_requirements(
    prepared,
    native_values_installed_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    None,
  ).unwrap()
}

///|
test "Local Values publication retains original checked plan and separate decoder guards" {
  let prepared = local_values_guard_prepared()
  let original = publication_requirements(prepared)
  let (row, output) = original.publication_limits(prepared, 536870912).unwrap()
  // Independent one-row/one-Number-column envelope; quote, execution and
  // publication retain the same original checked requirements. One projection
  // field, matched reference and source-column lookup cost three mapping units;
  // one row container and one Number are two nodes, plus three wire wrappers.
  assert_eq(row.max_bytes, 65536)
  assert_eq(row.max_nodes, 10000)
  assert_eq(row.max_depth, 64)
  assert_eq(row.max_text_bytes, 65536)
  assert_eq(output.max_rows, 1)
  assert_eq(output.max_result_fields, 1)
  assert_eq(output.max_result_mapping_work, 3)
  assert_eq(output.max_result_order_work, 1)
  // The original one-row/one-column envelope has two row slots and thirteen
  // field slots, below the existing workspace floor100. Metadata/receipt
  // traversal has its independent original entry ceilings, never this bound.
  assert_eq(output.max_result_workspace_entries, 100)
  assert_eq(original.publication_entry_limits(prepared), Some((10000, 10000)))
  assert_eq(output.values.max_nodes, 2)
  assert_eq(output.values.max_text_bytes, 1)
  assert_eq(output.values.max_depth, 100)
  assert_eq(output.values.max_work, 20000000)
  for wire in [output.logical_wire, output.payload_wire] {
    assert_eq(wire.max_columns, 1)
    assert_eq(wire.max_order_work, 1000000)
    assert_eq(wire.max_bytes, 68)
    assert_eq(wire.max_nodes, 5)
    assert_eq(wire.max_depth, 64)
  }
  assert_eq(output.schema.max_bytes, 65536)
  assert_eq(output.max_batch_bytes, 65536)
}

///|
test "Local Values publication intersects a smaller installed Store ceiling" {
  let prepared = local_values_guard_prepared()
  let original = publication_requirements(prepared)
  let (_, output) = original.publication_limits(prepared, 17).unwrap()
  assert_eq(output.logical_wire.max_bytes, 17)
  assert_eq(output.payload_wire.max_bytes, 17)
  assert_eq(output.schema.max_bytes, 17)
  assert_eq(output.max_batch_bytes, 17)
  assert_eq(output.max_rows, 1)
  assert_eq(output.values.max_work, 20000000)
  assert_true(
    original.publication_limits(local_values_guard_prepared(), 17) is None,
  )
  for invalid in [0, -1] {
    assert_true(original.publication_limits(prepared, invalid) is None)
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
      native_values_installed_contracts(),
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
