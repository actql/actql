///|
// Actual checked base Row acquisition and same-Request Plan/Run. The existing
// physical Node admission and empty Compute providers are component ports;
// this proves no Native Files backing, Account, authorization or physical ACK.
fn original_row_capture_fixture(
  current? : () -> Bool = () => true,
  transport_bytes? : Int64 = 4096L,
  transport_execution? : Int64 = 2048L,
  original_declaration? : @row_source_host.RowDeclaration? = None,
  original_environment? : @checked.CheckEnvironment? = None,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientInstalledManagedRun,
  ClientInstalledManagedCapturePlan,
  @row_source_host.RowDeclaration,
) raise {
  let declaration = original_declaration.unwrap_or_else(
    pure_provider_declaration,
  )
  let environment = match original_environment {
    Some(original) => original
    None => pure_provider_environment(declaration)
  }
  let document =
    #|{"version":"actql/0.1","id":"pure-provider-original","stages":[{"id":"acquire","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"filter":"true"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("fixture checked Pure provider Source")
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
    "same-original-pure-provider",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    0,
    0,
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
    [transport_bytes],
    [transport_execution],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  (parent, run, plan, declaration)
}

///|
test "original base Row read reuses the retained Request Plan without a provider replacement" {
  let calls = Ref(0)
  let (parent, owner, plan, declaration) = original_row_capture_fixture(current=() => {
    calls.val += 1
    true
  })
  // Its root belongs to the later Compute stage, so this same checked Query
  // prefix keeps the existing narrow acquisition choice.
  assert_true(
    select_installed_source_input(plan.prepared, plan.request, 0, 0).unwrap()
    is @sourceviews.QueryRoute(_),
  )
  let original = plan.captures[0]
  assert_true(original.provider is None)
  let acquisition = original.acquisition.unwrap()
  let copied_declaration = pure_provider_declaration()
  assert_eq(copied_declaration.catalog_cid, declaration.catalog_cid)
  let before = calls.val
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      copied_declaration,
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, before)
  assert_true(owner.reads[0] is None)
  let (read, requirement, observed, capacity) = match
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    ) {
    Ok(value) => value
    Err(ForeignOriginal) =>
      fail("RetainedOriginalBaseRowRefusedAsForeignOriginal")
    Err(_) => fail("UnexpectedRetainedOriginalBaseRowIssue")
  }
  assert_eq(calls.val - before, 1)
  assert_true(physical_equal(read, owner.reads[0].unwrap()))
  assert_true(physical_equal(requirement, original.requirement))
  assert_true(physical_equal(observed, acquisition))
  assert_true(physical_equal(capacity, original))
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "original base Row read keeps its partial child when current replaces the Plan capacity" {
  let selected : Ref[ClientInstalledManagedCapturePlan?] = Ref(None)
  let replacement : Ref[ClientInstalledCaptureCapacity?] = Ref(None)
  let (parent, owner, plan, declaration) = original_row_capture_fixture(current=() => {
    if selected.val is Some(plan) && replacement.val is Some(other) {
      plan.captures[0] = other
    }
    true
  })
  let original = plan.captures[0]
  let acquisition = original.acquisition.unwrap()
  replacement.val = installed_row_capture_capacity(acquisition)
  selected.val = Some(plan)
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    )
    is Err(ForeignOriginal),
  )
  let read = owner.reads[0].unwrap()
  assert_true(
    read.acquisition is Some(held) && physical_equal(held, acquisition),
  )
  assert_true(read.declaration is None)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  selected.val = None
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "managed Source correspondence keeps the exact retained read and Ledger" {
  let (parent, owner, plan, declaration) = original_row_capture_fixture()
  let (read, _, _, _) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  check_installed_source_read_ledger(read, parent.ledger).unwrap()
  check_installed_source_read_retained_ledger(read, parent.ledger).unwrap()
  let copied = { ..read, }
  assert_true(
    check_installed_source_read_ledger(copied, parent.ledger)
    is Err(ForeignOriginal),
  )
  let foreign = @resources.create_ledger(
    @resources.ledger_limits(parent.ledger),
  ).unwrap()
  assert_true(
    check_installed_source_read_ledger(read, foreign) is Err(ForeignOriginal),
  )
  retire_installed_source_read(read).unwrap()
  assert_true(physical_equal(owner.reads[0].unwrap(), read))
  assert_true(
    check_installed_source_read_ledger(read, parent.ledger) is Err(Retired),
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "managed Source current callback cannot revive its synchronously retired read" {
  let selected : Ref[ClientInstalledSourceRead?] = Ref(None)
  let retired = Ref(false)
  let (parent, owner, plan, declaration) = original_row_capture_fixture(current=() => {
    if selected.val is Some(read) {
      // Clear the callback selection before cleanup; retain the same parent's
      // slot to exercise the post-current fence rather than slot replacement.
      selected.val = None
      retired.val = retire_installed_source_read(read) is Ok(_)
    }
    true
  })
  let (read, _, _, _) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  selected.val = Some(read)
  assert_true(
    check_installed_source_read_ledger(read, parent.ledger) is Err(Retired),
  )
  assert_true(retired.val)
  assert_true(
    check_installed_source_read_retained_ledger(read, parent.ledger)
    is Err(Retired),
  )
  assert_true(physical_equal(owner.reads[0].unwrap(), read))
  assert_true(read.ledger is None && read.managed_run is None)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "managed Source retained fence rejects retirement after an earlier successful observation" {
  let selected : Ref[ClientInstalledSourceRead?] = Ref(None)
  let retired = Ref(false)
  let (parent, owner, plan, declaration) = original_row_capture_fixture(current=() => {
    if selected.val is Some(read) {
      selected.val = None
      retired.val = retire_installed_source_read(read) is Ok(_)
    }
    true
  })
  let (read, _, _, _) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  check_installed_source_read_ledger(read, parent.ledger).unwrap()
  check_installed_source_read_retained_ledger(read, parent.ledger).unwrap()
  selected.val = Some(read)
  // A later original-current observer can still succeed for the same parent
  // after its callback retires only this Source. It does not validate the read.
  assert_true(
    physical_equal(require_installed_managed_run(owner).unwrap(), parent.ledger),
  )
  assert_true(retired.val)
  assert_true(physical_equal(owner.reads[0].unwrap(), read))
  assert_true(
    check_installed_source_read_retained_ledger(read, parent.ledger)
    is Err(Retired),
  )
  retire_installed_managed_run(owner).unwrap()
}
