///|
// The original public retained Events Program. This component stops after its
// first original dispatch preparation with the normal Node publication-identity
// policy: no provider execution, durable publication, Journal or Store.
let retained_events_publication_identity_program : String =
  #|{"version":"actql/0.1","id":"public-retained-events","stages":[{"id":"values","inputs":{},"steps":[{"values":{"schema":{"event_id":{"type":"number","nullable":false},"occurred_at":{"type":"number","nullable":false},"payload":{"type":"string","nullable":false}},"rows":[{"event_id":1,"occurred_at":5,"payload":"first"},{"event_id":2,"occurred_at":15,"payload":"second"}]},"as":"out"}],"results":{"r":{"from":"out","fields":["event_id","occurred_at","payload"]}}},{"id":"events","inputs":{"rows":{"result":{"stage":"values","result":"r"}}},"steps":[{"from":"rows","to_events":{"id":"event_id","time":"occurred_at"},"as":"source"},{"from":"source","watermark_events":{"watermark_ms":10,"policy":"mark"},"as":"marked"},{"from":"marked","events":true,"as":"out"}],"results":{"r":{"from":"out","fields":["event_id","occurred_at","payload","watermark_ms","late","watermark_decision"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"events","result":"r"}}},"steps":[{"select":["event_id","late"],"as":"out"}],"results":{"r":{"from":"out","fields":["event_id","late"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"events","result":"r"}}},"steps":[{"select":["watermark_decision","event_id"],"as":"out"}],"results":{"r":{"from":"out","fields":["watermark_decision","event_id"]}}}],"results":{"published":{"from":{"stage":"events","result":"r"}},"consumed_a":{"from":{"stage":"consumer_a","result":"r"}},"consumed_b":{"from":{"stage":"consumer_b","result":"r"}}}}

///|
test "original retained Events first dispatch coexists with its original explanation loan" {
  let environment = @publication_host.admit_client_check_environment(
    node_closed_carrier_demand_environment,
    "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261",
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    graph=true,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  // This existing Node fixture supplies the original Resource admission port,
  // with the unchanged installed policy. It is not normal physical backing.
  let (parent, input) = request_diagnostic_test_parent()
  client_program_prepare_request_native_computation(
    parent,
    input,
    request_diagnostic_test_json(retained_events_publication_identity_program),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  ).unwrap()
  assert_eq(
    client_program_finish_request_computation(
      parent, input, environment, publication,
    ).unwrap(),
    "effect_free",
  )
  client_program_prepare_request_program_normalization(parent, input).unwrap()
  |> ignore
  client_program_prepare_request_program_authoring_context(parent, input).unwrap()
  |> ignore
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = client_prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  // The actual normal manager prepares this optional same-Request loan after
  // compilation and before the module. Preserve its exact installed bounds.
  let artifact = client_program_prepare_request_program_compilation(
    parent, input, contracts, true,
  ).unwrap()
  let explanation = client_program_prepare_request_original_explanation(
    parent, input, 1000000, 100000, 64,
  ).unwrap()
  client_program_prepare_request_program_module_body(
    parent,
    input,
    contracts,
    true,
    None,
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-events-publication-identity",
  ).unwrap()
  let run = match explanation {
    None =>
      client_program_adopt_request_program_preparation(parent, request).unwrap()
    Some(original) =>
      client_program_adopt_request_program_with_explanation(
        parent, request, original,
      ).unwrap()
  }
  let capture = match explanation {
    None => None
    Some(original) => {
      let compiled = match artifact {
        Values(value) =>
          @publication_host.issue_client_values_compiled_run(
            prepared,
            value,
            "sha256:" + "a".repeat(64),
            "sha256:" + "b".repeat(64),
            "2099-01-01T00:00:00.000Z",
          ).unwrap()
        Tasks(value) =>
          @publication_host.issue_client_task_compiled_run(
            prepared,
            value,
            "sha256:" + "a".repeat(64),
            "sha256:" + "b".repeat(64),
            "2099-01-01T00:00:00.000Z",
          ).unwrap()
        Effects(_) => fail("expected original pure compilation")
      }
      let definition = @publication_host.issue_client_compiled_run_definition(
        compiled, "events-explanation-component", "same-original-events", "2026-11-19T00:00:00.000Z",
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
      let scope = client_program_capture_request_original_explanation(
        original, compiled, definition,
      ).unwrap()
      client_program_original_explanation_plan_wire(scope).unwrap() |> ignore
      client_program_original_explanation_facts_wire(scope).unwrap() |> ignore
      // Existing typed payload-ACK port only. This component has no physical
      // Journal, COMMIT or external release acknowledgement.
      client_program_acknowledge_original_explanation_capture(scope).unwrap()
      Some(scope)
    }
  }
  let host = client_program_open_installed_managed_source_free_host(
      run,
      prepared,
      request,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      true,
    )
    .unwrap()
    .unwrap()
  // Match the existing normal Node entry policy before any dispatch request.
  // The original component did not select publication identity requirements.
  assert_true(
    strategy_host_configure_managed_identity(host, true, false, false, false),
  )
  let driver = @builtin.configured_host_driver(host)
  let captured = @host_driver.dispatch_driver_run(driver)
  let ledger = @strategy.captured_dag_ledger(captured)
  let before_dispatch_usage = @resources.ledger_usage(ledger)
  let admission = @resources.ledger_admission_limits(ledger)
  let original = @host_driver.prepare_next_compute_task(
    @builtin.configured_host_runtime(host),
    (),
  )
  let outcome = match original {
    Ok(Some(_)) => "prepared"
    Ok(None) => "empty"
    Err(Estimate(NoStrategy)) => "estimate.no_strategy"
    Err(Estimate(InvalidConfiguration)) => "estimate.invalid_configuration"
    Err(Estimate(ForeignSelection)) => "estimate.foreign_selection"
    Err(Estimate(EstimateOverflow)) => "estimate.overflow"
    Err(Estimate(Resources(_))) => "estimate.resources"
    Err(Estimate(Search(_))) => "estimate.search"
    Err(Estimate(Implementation(_))) => "estimate.implementation"
    Err(Dispatch(_)) => "dispatch"
    Err(Installation(_)) => "installation"
    Err(ForeignInstallation) => "foreign_installation"
  }
  let report = Array::makei(@strategy.strategy_report_count(captured), index => {
    let assessment = @strategy.strategy_report_at(captured, index).unwrap()
    let reason = @strategy.strategy_assessment_rejection_code(assessment).unwrap_or(
      "feasible",
    )
    "\{reason}:execution=\{assessment.execution_bytes}:retained=\{assessment.retained_bytes}"
  })
  println(
    "ORIGINAL_EVENTS_EXECUTION_BOUNDS limit=\{admission.execution_bytes} held=\{before_dispatch_usage.reserved_execution_bytes}",
  )
  let explanation_state = if capture is Some(_) {
    "retained"
  } else {
    "declined"
  }
  println(
    "ORIGINAL_EVENTS_EXPLANATION_FIRST_DISPATCH \{outcome} explanation=\{explanation_state} assessments=\{report.join(",")}",
  )
  // No physical child was started. Retire this component's actual owners before
  // the assertion, including when the original planning call refused.
  @host_driver.stop_dispatch_driver(driver)
  match capture {
    Some(scope) =>
      client_program_return_original_explanation_capture(scope).unwrap()
      |> ignore
    None => ()
  }
  client_program_preparation_borrow_return(holder).unwrap() |> ignore
  @client_local_host.retire_installed_managed_run(run).unwrap()
  assert_eq(outcome, "prepared")
}
