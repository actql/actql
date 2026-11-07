///|
// Existing observed JSON Request preparation and explicit selected row profile.
// No Native Host, Account, Store, durable Run or physical backing is supplied.
fn native_publication_workspace_fixture() -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
) raise {
  let document = request_native_numeric_public_program(20000)
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_native_intake_wire(
    parent,
    input,
    document.length() * 6 + 4096,
  ).unwrap()
  let wire = request_numeric_local_environment(
    @publication_host.client_local_product_assets().environment,
    20000,
  )
  let environment = @publication_host.admit_client_check_environment(
    wire,
    request_numeric_environment_cid(wire),
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let writer = @encode.writer(document.length() * 6 + 1024, 4, 2)
  @encode.string_value(writer, document)
  let intent = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"text\":" +
    @encode.finish(writer) +
    ",\"format\":\"json\"},\"parameters\":null}",
    document.length() * 6 + 1024,
    8192,
    64,
  ).unwrap()
  finish_request_native_intake_wire(parent, input, intent).unwrap()
  retain_request_submitted_intent(parent, input, intent).unwrap()
  reserve_request_retained_intent_source(parent, input).unwrap() |> ignore
  prepare_request_default_source_computation_check(
    parent,
    input,
    request_document_test_source(document, "json"),
    native_json_reader,
    environment,
    publication,
    [],
    None,
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  finish_request_checked_computation(parent, input, environment, publication).unwrap()
  |> ignore
  prepare_request_program_module_body(
    parent,
    input,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=request_program_compilation_limits(parent, input).unwrap(),
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  (parent, input, parent.compiled_program.unwrap())
}

///|
test "Native publication row indices use original quoted workspace independently of evidence entries" {
  let (parent, _input, prepared) = native_publication_workspace_fixture()
  let assets = @publication_host.client_local_product_assets()
  let contracts = parent.program_source_free.unwrap().installed_contracts
  let requirements = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let before = requirements.maximum_limits()
  let (bridge_entries, evidence_entries) = requirements
    .publication_entry_limits(prepared)
    .unwrap()
  assert_eq(bridge_entries, 10000)
  assert_eq(evidence_entries, 10000)
  let (row_limits, limits) = requirements
    .publication_limits(prepared, 16777216)
    .unwrap()
  assert_true(limits.max_result_workspace_entries >= 20000)
  assert_eq(requirements.maximum_limits(), before)
  // Use the existing prepared managed route selected by the ordinary caller;
  // the legacy raw Host would retain another output allowance alongside this
  // live Request. No policy increase or separate Ledger repairs that mismatch.
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "publication-workspace-component",
  ).unwrap()
  let run = begin_request_program_managed_run(parent, request).unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    )
    .unwrap()
    .unwrap()
  let execution = match
    execute_source_free_local_tasks_guarded(
      setup,
      256,
      requirements.finalization_round_limit(prepared).unwrap(),
      () => true,
    ) {
    Ok(value) => value
    Err(failure) => {
      let issue = local_values_execution_failure_issue(failure)
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      retire_installed_managed_run(run) |> ignore
      let detail = match issue {
        InvalidLimits => "InvalidLimits"
        Fenced => "Fenced"
        UnsupportedGraph => "UnsupportedGraph"
        MissingLocalModule => "MissingLocalModule"
        FinalizationLimit => "FinalizationLimit"
        MissingOutput => "MissingOutput"
        Estimate(_) => "Estimate"
        Driver(original) =>
          match original {
            Configuration(InvalidLimits) => "Driver.Configuration.InvalidLimits"
            Configuration(LogicalIdentityUnsupported) =>
              "Driver.Configuration.LogicalIdentityUnsupported"
            Configuration(ComputeUnsupported) =>
              "Driver.Configuration.ComputeUnsupported"
            ManagedValues(Guard(_)) => "Driver.ManagedValues.Guard"
            ManagedValues(Admission(_)) => "Driver.ManagedValues.Admission"
            IdentityExport(ResultView(Limit)) =>
              "Driver.IdentityExport.ResultView.Limit"
            Execution(Physical(original)) =>
              "Driver.Execution.Physical." + @debug.to_string(original)
            Execution(ActivationNotAuthorized) =>
              "Driver.Execution.ActivationNotAuthorized"
            Execution(Compute(_)) => "Driver.Execution.Compute"
            Execution(_) => "Driver.Execution.Other"
            _ => "Driver.Other"
          }
      }
      fail("Component completed-output setup: " + detail)
    }
  }
  // The old, tighter request refuses the projection without revoking the
  // existing completed output. No business operation is replayed below.
  let old = { ..limits, max_result_workspace_entries: evidence_entries, }
  assert_true(
    execution.prepare_result_export(0, row_limits, bridge_entries, 65536, old)
    is Err(
      Export(@publication_host.Output(@execution.ResultView(@execution.Limit)))
    ),
  )
  let output = execution
    .prepare_result_export(0, row_limits, bridge_entries, 65536, limits)
    .unwrap()
  let stream = output.output_export()
  while stream.next().unwrap() is Some(_) {
    ()
  }
  stream.finish().unwrap() |> ignore
  assert_eq(stream.row_count().unwrap(), 20000)
  output.close()
  assert_true(execution.close())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Native publication phase entry bounds refuse foreign preparation without changing limits" {
  let prepared = source_free_requirements_prepared()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let requirements = prepare_source_free_local_requirements(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let before = requirements.maximum_limits()
  assert_eq(
    requirements.publication_entry_limits(prepared),
    Some((10000, 10000)),
  )
  assert_true(
    requirements.publication_entry_limits(source_free_requirements_prepared())
    is None,
  )
  assert_eq(requirements.maximum_limits(), before)
}
