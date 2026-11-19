///|
extern "js" fn preadopted_failure_imported_consumer(
  loader : RequestDiagnosticTestLoader,
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  failure : Result[
    @host_driver.PreparedTaskDispatch?,
    @host_driver.ComputeHostIssue[@strategy.RunIssue],
  ],
  original : (
    String,
    String,
    Int,
    Int,
    Bool,
    Bool,
    Array[(Int, String?)],
    String,
  )?,
) -> Bool =
  #|(load, host, failure, original) => {
  #| const {runtimeCore}=load('../../../../../adapters/host-common/runtime-core.mjs');
  #| const {runtimeField}=load('../../../../../adapters/host-common/compiler-binding.generated.mjs');
  #| const {dispatchFailureSnapshot,publicBudgetFailureMessage}=load('../../../../../adapters/host-node/client-dispatch-diagnostic.mjs');
  #| const core=runtimeCore({strategyRemoteManagedOutputEvidenceKind:()=> 'unused',strategyHostNext:()=>failure});
  #| let caught,calls=0;
  #| try {core.next(host,actual=>{if(actual!==host) throw Error('foreign Host');calls++;return original;});}
  #| catch(error){caught=error;}
  #| const facts=dispatchFailureSnapshot(caught)?.primaryDiagnostic;
  #| const wrapper=Object.assign(new Error('original wrapper'),{primaryFailure:caught});
  #| return calls===1 && caught?.cause===runtimeField(failure,0) && facts?.phase==='adaptive_dispatch' &&
  #|   facts.kind==='resources' && facts.task===0 && facts.assessmentCount===0 &&
  #|   facts.complete===false && facts.truncated===false && facts.assessments.length===0 &&
  #|   facts.decision==='unavailable' && facts.candidateCount==='unavailable' &&
  #|   dispatchFailureSnapshot(wrapper)?.primaryDiagnostic===facts && publicBudgetFailureMessage(caught)===undefined;
  #| }

///|
// SAME original Events Program and unchanged ordinary Node Resource parent.
// This explicit component retains the pre-adoption loan at normal 1m/100k/64;
// no Provider executes and there is no Journal, Store or physical ACK.
test "pre-adopted original Explanation propagates actual Estimate failure through the imported consumer" {
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
  let scope = capture.unwrap()
  let driver = @builtin.configured_host_driver(host)
  let runtime = @builtin.configured_host_runtime(host)
  let captured = @host_driver.dispatch_driver_run(driver)
  let ledger = @strategy.captured_dag_ledger(captured)
  @host_driver.refresh_compute_host(runtime).unwrap()
  assert_eq(@strategy.strategy_report_count(captured), 1)
  assert_eq(
    @strategy.strategy_assessment_rejection_code(
      @strategy.strategy_report_at(captured, 0).unwrap(),
    ),
    None,
  )
  let usage = @resources.ledger_usage(ledger)
  let limits = @resources.ledger_limits(ledger)
  @resources.charge_planning(ledger, limits.planning_work - usage.planning_work).unwrap()
  let pressure = @resources.reserve_capacity(ledger, 0L, 1L).unwrap()
  let failure = @host_driver.prepare_next_compute_task(runtime, ())
  assert_true(failure is Err(Estimate(Resources(PlanningLimit))))
  let before = @resources.ledger_usage(ledger)
  let original = client_program_observe_original_dispatch_failure(scope, host)
  let (projected, outcome) = match original {
    Ok(Some(value)) =>
      (
        preadopted_failure_imported_consumer(
          request_diagnostic_test_loader(request_diagnostic_test_url()),
          host,
          failure,
          Some(value),
        ),
        "projected",
      )
    Ok(None) => (false, "absent")
    Err(Capacity(ForeignOriginal)) => (false, "capacity.foreign_original")
    Err(_) => (false, "other_refusal")
  }
  let after = @resources.ledger_usage(ledger)
  @resources.settle_capacity(ledger, pressure).unwrap() |> ignore
  @host_driver.stop_dispatch_driver(driver)
  client_program_return_original_explanation_capture(scope).unwrap() |> ignore
  client_program_preparation_borrow_return(holder).unwrap() |> ignore
  @client_local_host.retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  println("PREADOPTED_ORIGINAL_ESTIMATE_FAILURE \{outcome}")
  assert_true(projected)
  assert_eq(
    after.reserved_retention_bytes,
    before.reserved_retention_bytes + 424L,
  )
  assert_eq(
    after.reserved_execution_bytes,
    before.reserved_execution_bytes + 424L,
  )
}
