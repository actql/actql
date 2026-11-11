///|
// Actual Request check/compiler/adoption and unknown-row Source declaration.
// Currentness and physical installation are component ports, not public ACKs.
fn keyed_capture_parent_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientInstalledManagedRun,
  ClientInstalledManagedCapturePlan,
  @row_source_host.RowDeclaration,
  @publication_host.ClientKeyedAcquisition,
) raise {
  let (declaration, wire) = original_keyed_declaration_environment(
    relation_versions=true,
  )
  guard @json.parse(wire) is Object(body) &&
    body.get("evidence_bundle_cid") is Some(String(environment_cid)) else {
    fail("original environment identity")
  }
  let environment = @publication_host.admit_client_check_environment(
    wire,
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"keyed-parent","stages":[{"id":"read","inputs":{"contents":{"connector":"content-fixture","resource":"contents"},"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"selected"},{"join":{"left":"selected","with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["name","content"]}}}],"results":{"rows":{"from":{"stage":"read","result":"rows"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("unknown-row keyed Source must check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  reserve_request_program_plan(parent, input).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "keyed-parent",
  ).unwrap()
  let keyed = @publication_host.select_client_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  let (stage, source, _) = @publication_host.client_keyed_direct_acquisition_coordinates(
    keyed,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    stage,
    source,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let acquisition = @row_source_host.prepare_row_acquisition(
    declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
  ).unwrap()
  let capacity = installed_row_capture_capacity(acquisition).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  (parent, owner, plan, declaration, keyed)
}

///|
test "managed keyed Source borrows its original Request Ledger without another whole-budget quote" {
  let (parent, owner, plan, declaration, keyed) = keyed_capture_parent_fixture()
  assert_true(
    @publication_host.client_keyed_lookup_capacity(keyed, 4096, 100000).unwrap().0
    is None,
  )
  let (read, _, acquisition, capacity) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  let ledger = prepare_installed_managed_run_ledger(
    owner,
    plan.prepared,
    plan.request,
    [capacity],
    [4096L],
    [2048L],
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  ).unwrap()
  assert_true(physical_equal(ledger, parent.ledger))
  assert_eq(@resources.ledger_usage(ledger), before)
  let foreign = installed_row_capture_capacity(acquisition).unwrap()
  assert_true(
    prepare_installed_managed_run_ledger(
      owner,
      plan.prepared,
      plan.request,
      [foreign],
      [4096L],
      [2048L],
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  let other_request = @publication_host.prepare_source_free_client_request_identity(
    plan.prepared,
    "sha256:" + "b".repeat(64),
    "foreign-keyed-parent",
  ).unwrap()
  assert_true(
    prepare_installed_managed_run_ledger(
      owner,
      plan.prepared,
      other_request,
      [capacity],
      [4096L],
      [2048L],
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    @resources.reserve_capacity(
      ledger,
      @resources.ledger_limits(ledger).retained_bytes + 1L,
      0L,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "managed keyed Host retains the original configuration and rejects a foreign Ledger" {
  let (parent, owner, plan, declaration, keyed) = keyed_capture_parent_fixture()
  let (read, _, acquisition, _) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "keyed-parent-empty",
    _ => true,
    4096L,
    2048L,
  ).unwrap()
  let issuer = @admitted.bind_reference_issuer((_, _) => false, _ => false)
  // This fixture selected 2048 execution bytes above. Its page cannot borrow
  // the separate 4096-byte transfer allowance as execution backing.
  @row_source_host.begin_row_run(
    rows,
    2048,
    3,
    3,
    reference_issuer=Some(issuer),
  ).unwrap()
  let bytes = @utf8.encode("[]")
  let charged = @row_source_host.charge_row_run_page(rows, bytes).unwrap()
  @row_source_host.accept_charged_row_run_page(rows, charged, bytes).unwrap()
  |> ignore
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let source = @row_source_host.row_capture_source(capture).unwrap()
  let left = @publication_host.prepare_client_keyed_capture_left_read(
    keyed, source, 1000, 4096,
  ).unwrap()
  // A different Ledger is an explicit negative fixture, never a fallback.
  let foreign = @resources.create_ledger(
    @resources.ledger_limits(parent.ledger),
  ).unwrap()
  let wrong = @publication_host.start_client_keyed_lookup_input(
    left, foreign, 4096, 100000,
  ).unwrap()
  assert_true(
    open_installed_managed_keyed_capture_host(
      owner,
      plan.prepared,
      plan.request,
      wrong,
    )
    is Err(Keyed(_)),
  )
  assert_true(owner.source_free_captured is None)
  @publication_host.stop_client_keyed_lookup_input(wrong)
  while !@publication_host.cleanup_client_keyed_lookup_input(wrong, 10).unwrap() {

  }
  let left = @publication_host.prepare_client_keyed_capture_left_read(
    keyed, source, 1000, 4096,
  ).unwrap()
  let lookup = @publication_host.start_client_keyed_lookup_input(
    left,
    parent.ledger,
    4096,
    100000,
  ).unwrap()
  let (_, dag, sequences) = open_installed_managed_keyed_capture_host(
    owner,
    plan.prepared,
    plan.request,
    lookup,
  ).unwrap()
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), parent.ledger))
  assert_true(physical_equal(sequences, plan.sequences))
  assert_true(
    owner.source_free_captured is Some(original) &&
    physical_equal(original, dag),
  )
  assert_true(
    open_installed_managed_keyed_capture_host(
      owner,
      plan.prepared,
      plan.request,
      lookup,
    )
    is Err(Managed(AlreadyBound)),
  )
  @strategy.stop_captured_dag(dag)
  @publication_host.stop_client_keyed_lookup_input(lookup)
  while !@publication_host.cleanup_client_keyed_lookup_input(lookup, 10).unwrap() {

  }
  @row_source_host.close_accounted_row_run(rows).unwrap()
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
