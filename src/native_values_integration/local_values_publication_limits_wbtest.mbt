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

///|
fn publication_row_policy_prepared(
  artifact_rows : Int,
  relation_rows? : Int = 1000,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(body) &&
    body["host_policy_profile"] is Object(profile) &&
    profile["capacity"] is Object(capacity) else {
    fail("fixture original Host capacity")
  }
  body.remove("evidence_bundle_cid")
  capacity["max_artifact_rows"] = Json::number(artifact_rows.to_double())
  capacity["max_relation_output_rows"] = Json::number(relation_rows.to_double())
  let evidence = @identity.from_json(Json::object(body), 10000, 100, 100000)
  let cid = @identity.cid_value(evidence, 100000, 10000, 100)
  body["evidence_bundle_cid"] = cid.to_json()
  let wire = @identity.stringify_value(
    @identity.from_json(Json::object(body), 10000, 100, 100000),
    100000,
    10000,
    100,
  )
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let context = @frontend.bind_query_context(
    [],
    @program_check.checking_environment_cid(environment),
  ).unwrap()
  let lowered = @frontend.lower(
    "SELECT 0 AS n UNION ALL SELECT 1 AS n",
    @frontend.Sql,
    Some(context),
  ).unwrap()
  let parsed = lowered.program.unwrap()
  @publication_host.prepare_parsed_effect_free_client_program(
    parsed,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "checked artifact row policy refuses the complete UNION before publication and releases its pin" {
  for artifact_rows in [1, 2] {
    let prepared = publication_row_policy_prepared(artifact_rows)
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
    let run = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(setup),
    )
    let execution = @client_local_host.execute_source_free_local_tasks_guarded(
      setup,
      64,
      10000,
      () => true,
    ).unwrap()
    assert_eq(execution.rows().unwrap(), ["{\"n\":0}", "{\"n\":1}"])
    let requirements = publication_requirements(prepared)
    let (row, limits) = requirements
      .publication_limits(prepared, 1000000)
      .unwrap()
    // The independent checked publication restriction must still apply when
    // the physical Plan and caller's export envelope admit both actual rows.
    assert_true(limits.max_rows >= 2)
    let exported = execution.prepare_captured_result_export(
      run, 0, row, 10000, 10000, limits,
    )
    if artifact_rows == 1 {
      assert_true(
        exported
        is Err(
          @client_local_host.Export(
            @publication_host.Output(
              @execution.Admission(@execution.CaptureLimit)
            )
          )
        ),
      )
    } else {
      let retained = exported.unwrap()
      let stream = retained.output_export()
      let output = StringBuilder()
      while stream.next().unwrap() is Some(chunk) {
        output.write_string(chunk)
      }
      output.write_string(stream.finish().unwrap())
      assert_eq(output.to_string(), "[{\"n\":0},{\"n\":1}]")
      retained.close()
    }
    assert_true(execution.close())
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).live_reservations,
      0,
    )
  }
}

///|
test "checked Append relation row policy refuses UNION independently of artifact capacity" {
  let prepared = publication_row_policy_prepared(1000, relation_rows=1)
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
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let failure = @client_local_host.execute_source_free_local_tasks_guarded(
    setup,
    64,
    10000,
    () => true,
  ).unwrap_err()
  assert_true(
    @client_local_host.local_values_execution_failure_issue(failure)
    is @client_local_host.Driver(Configuration(Execution(Rows(_, RowLimit)))),
  )
  assert_true(
    @client_local_host.retry_local_values_execution_failure_cleanup(failure),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).live_reservations,
    0,
  )
}
