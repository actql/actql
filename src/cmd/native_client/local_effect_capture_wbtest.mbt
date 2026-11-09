///|
test "Native Work capture exposes the original owner method without a supplied journal" {
  // This compiles the real Host method, not an uninstalled CLI adapter. It opens no Source, Store or Provider and
  // is not evidence that the Native physical component fixture executed.
  let caller = fn(
    work : @local_host.NativeClientEffectSourceWork,
    retention : @publication.PublicationContract,
    limits : @run_host.PublicationOutputExportLimits,
    max_bytes : Int,
    max_nodes : Int,
    max_depth : Int,
  ) {
    work.prepare_original_capture_context(
      retention, limits, max_bytes, max_nodes, max_depth,
    )
  }
  caller |> ignore
  assert_true(
    @local_host.NativeClientEffectCaptureIssue::Normalization(
      @run_host.MissingOriginalJournal,
    )
    is Normalization(@run_host.MissingOriginalJournal),
  )
}

///|
// Real Native Request/Plan/operation owners. No Source, Provider, Account,
// Journal or mutation is executed by this constructor-lifetime control.
test "Native first member retains one original capture before input and full recipe growth" {
  let facility = native_mock_readme_request_facility()
  facility.arena.enter_domain_retained_execution(facility.physical).unwrap()
  let environment = @run_host.admit_client_check_environment(
    local_effect_prefix_fixture_environment_wire,
    "sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[]}",
  ).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    local_effect_prefix_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let (submitted, body) = @local_host.prepare_native_client_submitted_request_input(
    facility.parent,
    facility.input,
    intent,
    environment,
    publication,
  ).unwrap()
  guard @local_host.native_client_submitted_preparation(submitted)
    is EffectComputation(prepared) else {
    fail("original Effect preparation")
  }
  let first = local_effect_prefix_fixture_original(submitted) catch {
    ClientStop(message) => fail(message)
  }
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let initial = [
    @execution.execution_capacity(10L, 20L).unwrap(),
    @execution.execution_capacity(2L, 3L).unwrap(),
    empty,
    empty,
    empty,
    empty,
  ]
  let future = initial.copy()
  future[0] = @execution.execution_capacity(30L, 50L).unwrap()
  let maximum = initial.copy()
  maximum[0] = @execution.execution_capacity(10000L, 20000L).unwrap()
  let capture = @local_values.prepare_installed_effect_staged_extent(
    @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", initial,
    ).unwrap(),
    @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", maximum,
    ).unwrap(),
  ).unwrap()
  let demand = @local_values.prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [capture],
    [],
  ).unwrap()
  let assets = @run_host.client_local_product_assets()
  let contracts = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let plan = @local_values.prepare_installed_effect_managed_plan(
    prepared,
    first.request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  @local_host.return_native_client_submitted_request_body(body).unwrap()
  |> ignore
  @local_values.complete_request_effect_preparation(
    facility.parent,
    facility.input,
    plan,
  ).unwrap()
  let run = @local_values.begin_request_effect_managed_run(
    facility.parent,
    first.request,
  ).unwrap()
  facility.run = Some(run)
  let child = native_mock_effect_capture_operation(
    run,
    prepared,
    first.request,
    plan,
    0,
  ).unwrap()
  let retained = [child]
  let entered = @local_values.begin_installed_effect_operation_input(
    child,
    @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", initial,
    ).unwrap(),
  )
  let issue = match entered {
    Err(@local_values.ForeignOriginal) =>
      Some("old auto-started constructor refused InputBegin")
    Err(_) => Some("original Native InputBegin refused")
    Ok(_) => {
      assert_true(physical_equal(child, retained[0]))
      @local_values.grow_installed_effect_operation_input(
        retained[0],
        @local_values.prepare_installed_effect_capture_recipe_extent(
          "native.mock.file.capture", future,
        ).unwrap(),
      ).unwrap()
      @local_values.complete_installed_effect_operation_construction(child).unwrap()
      None
    }
  }
  assert_true(
    @local_values.retire_installed_effect_operation(child, true).unwrap(),
  )
  @local_values.quiesce_installed_managed_run(run).unwrap()
  assert_true(@local_values.retire_installed_managed_run(run) is Err(_))
  facility.arena.leave_domain_retained_execution(facility.physical).unwrap()
  facility.arena.close_domain_retained_execution(facility.physical).unwrap()
  @local_values.retire_installed_managed_run(run).unwrap()
  facility.arena.close_domain_after_owner_ack(facility.domain).unwrap()
  facility.arena.try_close().unwrap()
  if issue is Some(message) {
    fail(message)
  }
}
