///|
test "collection original Request module finalizes the same9999 under selected Local policy" {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  let sql = "WITH d AS (" +
    digits.join(" UNION ALL ") +
    ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < 9999"
  let environment = collection_capacity_selected_environment(
    client_local_materialized_row_ceiling(client_local_resource_policy()).unwrap(),
  )
  let cid = @checked.checking_environment_cid(environment)
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" + cid + "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, input) = native_driver_parent(sql)
  parse_request_query_syntax(parent, input, sql, @frontend.Sql).unwrap()
  |> ignore
  lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    None,
    public_primary=true,
  ).unwrap()
  |> ignore
  let limits = @publication_host.client_standard_program_preparation_limits()
  let check = prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    None,
    [],
    limits.checking,
  ).unwrap()
  prepare_program_check_input(check).unwrap()
  prepare_program_check_prelude(check).unwrap() |> ignore
  prepare_program_check_registry(check).unwrap() |> ignore
  prepare_program_check_contents(check).unwrap() |> ignore
  prepare_program_check_references(check).unwrap() |> ignore
  prepare_program_check_policies(check).unwrap() |> ignore
  prepare_program_check_values(check).unwrap() |> ignore
  prepare_program_check_views(check).unwrap() |> ignore
  prepare_program_check_carriers(check).unwrap() |> ignore
  prepare_program_check_requests(check).unwrap() |> ignore
  reconcile_program_check_requests(check).unwrap()
  assert_true(
    finish_program_check_preparation(check).unwrap() is @checked.Checked(_),
  )
  let prepared = compile_program_check_preparation(check, limits).unwrap()
  continue_request_program_preparation(parent, input).unwrap() |> ignore
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  let plan = parent.program_source_free.unwrap()
  println(
    "request-finalization-policy " +
    @debug.to_string(
      (
        @publication_host.prepared_client_values_max_rows(prepared),
        plan.capacity_plan.execution.rows.max_rows,
        plan.capacity_plan.execution.rows.output_values,
      ),
    ),
  )
  let holder = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same9999-request-finalization",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      false,
    )
    .unwrap()
    .unwrap()
  let result = execute_source_free_local_tasks_guarded(setup, 32, 100000, () => {
    true
  })
  let output = match result {
    Ok(value) => value
    Err(failure) => {
      let family = match local_values_execution_failure_issue(failure) {
        Driver(
          @local_driver.ManagedValues(
            @execution.Admission(@execution.CaptureLimit)
          )
        ) => "ManagedValues/Admission/CaptureLimit"
        _ => "different checked failure"
      }
      let cleaned = retry_local_values_execution_failure_cleanup(failure)
      fail("request-finalization " + family + " cleanup=" + cleaned.to_string())
    }
  }
  let rows = output.rows().unwrap()
  assert_eq(rows.length(), 9999)
  for row in rows {
    assert_eq(row, "{\"n\":0}")
  }
  assert_true(output.close())
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
