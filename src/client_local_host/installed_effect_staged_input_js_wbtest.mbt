///|
// Real typed Plan/preparation/operation owners with explicit no-I/O Resource
// ports. This is not ordinary Host, HTTP, Store or physical ACK evidence.
fn staged_effect_input_fixture(
  current? : () -> Unit = () => (),
  physical_initial? : @execution.ExecutionCapacity? = None,
  parent_limit? : Int64? = None,
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  ClientInstalledManagedRun,
  @resources.Ledger,
) raise {
  let (prepared, request, contracts) = effect_operation_plan_inputs(
    rows="[{\"id\":1},{\"id\":2}]",
  )
  let capture = prepare_installed_effect_staged_extent(
    prepare_installed_effect_capture_extent(
      "capture",
      @execution.execution_capacity(10L, 20L).unwrap(),
      @execution.execution_capacity(2L, 3L).unwrap(),
    ).unwrap(),
    prepare_installed_effect_capture_extent(
      "capture",
      @execution.execution_capacity(1000000000L, 2000000000L).unwrap(),
      @execution.execution_capacity(1000000L, 2000000L).unwrap(),
    ).unwrap(),
  ).unwrap()
  let send = prepare_installed_effect_staged_extent(
    prepare_installed_effect_operation_extent(
      "send",
      physical_initial.unwrap_or(@execution.execution_capacity(5L, 8L).unwrap()),
      7L,
      true,
    ).unwrap(),
    prepare_installed_effect_operation_extent(
      "send",
      @execution.execution_capacity(1000000000L, 2000000000L).unwrap(),
      7L,
      true,
    ).unwrap(),
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [capture],
    [send],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let quote = prepared_installed_effect_managed_requirements(plan)
  assert_true(quote[4] < 1000000000L)
  assert_true(quote[5] < 2000000000L)
  quote[4] += 512L
  quote[5] += 512L
  if parent_limit is Some(limit) {
    // Existing preparation helper adds its separate original ten-byte carrier.
    quote[4] = limit - 10L
    quote[5] = limit - 10L
  }
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    quote,
    current~,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  (prepared, request, plan, owner, owner.ledger.unwrap())
}

///|
// The production described-record composer supplies the COMPLETE child:
// received HTTP backing + the original Core-selected secret bound + metadata.
// Other recipe inputs below cannot grant this child any surrounding allowance.
fn hubspot_full_metadata_response_quote(
  metadata : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity {
  let zero = @execution.execution_capacity(0L, 0L).unwrap()
  installed_described_effect_recipe_capacities(
    Some([
      (zero, None, None),
      (zero, None, None),
      (zero, None, None),
      (metadata, None, None),
    ]),
    Some([zero, zero, zero]),
    256,
    16,
    4,
    128,
    8,
    2,
    64,
    32,
    true,
    16,
    32,
    16,
    524288,
    installed_source_reader_policy()[0],
    7,
    16384,
    256,
    64,
    4,
    0L,
    response_read_quantum=16384,
    metadata_on_child=true,
    metadata_occurrences=6,
    target_occurrences=12,
    target_on_child=true,
    host_input_bytes=Some(0),
  ).unwrap()[7]
}

///|
test "full HubSpot response InputBegin reproduces current coheld execution refusal" {
  let property_limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  let initial = hubspot_full_metadata_response_quote(
    @hubspot_catalog.effect_metadata_construction_capacity(
      0, 9, property_limits,
    ).unwrap(),
  )
  println(
    "Full initial R=\{@execution.execution_capacity_retained_bytes(initial)} E=\{@execution.execution_capacity_execution_bytes(initial)}",
  )
  assert_eq(@execution.execution_capacity_retained_bytes(initial), 10692246L)
  assert_eq(@execution.execution_capacity_execution_bytes(initial), 12333318L)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(initial),
    parent_limit=Some(536870912L),
  )
  assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  let before = @resources.ledger_usage(ledger)
  let holding_reservation = @resources.reserve_attempt(
    ledger,
    0L,
    27452533L - before.held_bytes,
    0L,
  ).unwrap()
  let holding = @resources.retain_allocation(
    ledger,
    holding_reservation,
    27452533L - before.held_bytes,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let outside = @resources.reserve_capacity(
    ledger,
    419448946L - before.reserved_retention_bytes,
    477625077L - before.reserved_execution_bytes,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.held_bytes, 27452533L)
  assert_eq(before.reserved_retention_bytes, 419448946L)
  assert_eq(before.reserved_execution_bytes, 477625077L)
  // Historical actual next-total remains refused: it is never relabeled as
  // a successful new quote, or reduced by the measured shortage constant.
  let observed = prepare_installed_effect_operation_extent(
    "send",
    @execution.execution_capacity(13553144L, 72617509L).unwrap(),
    7L,
    true,
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_input(child, observed)
    is Err(Ledger(@resources.ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.settle_capacity(ledger, outside).unwrap()
  @resources.release_allocation(ledger, holding).unwrap()
  @resources.settle_reservation(ledger, holding_reservation).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "full HubSpot response InputBegin funds only original borrowed body and actual parser input" {
  let property_limits : @hubspot_catalog.PropertyLimits = {
    max_bytes: 524288,
    max_nodes: 65536,
    max_depth: 32,
    max_properties: 256,
    max_name_units: 6003,
  }
  // Independent large input with two unknown-field layouts. No actual body,
  // configuration, stopped Run or guessed geometry is used by this component.
  let properties = Array::makei(245, index => {
    "{\"name\":\"field_" +
    index.to_string() +
    "\",\"type\":\"string\",\"fieldType\":\"text\",\"description\":\"" +
    String::make(1050, 'x') +
    "\",\"shape\":[" +
    Array::make(
      if index % 2 == 0 {
        11
      } else {
        12
      },
      "{\"a\":0,\"b\":0,\"c\":0,\"d\":0,\"e\":0}",
    ).join(",") +
    "]}"
  })
  let body = @utf8.encode("{\"results\":[" + properties.join(",") + "]}")
  let path = "/crm/v3/properties/companies"
  let initial = hubspot_full_metadata_response_quote(
    @hubspot_catalog.effect_metadata_construction_capacity(
      0, 9, property_limits,
    ).unwrap(),
  )
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(
    physical_initial=Some(initial),
    parent_limit=Some(536870912L),
  )
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  start_installed_effect_operation(child).unwrap()
  let before = @resources.ledger_usage(ledger)
  let holding_reservation = @resources.reserve_attempt(
    ledger,
    0L,
    27452533L - before.held_bytes,
    0L,
  ).unwrap()
  let holding = @resources.retain_allocation(
    ledger,
    holding_reservation,
    27452533L - before.held_bytes,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let outside = @resources.reserve_capacity(
    ledger,
    419448946L - before.reserved_retention_bytes,
    477625077L - before.reserved_execution_bytes,
  ).unwrap()
  // The full initial physical token, with its real preflight floor, is now
  // live beside the captured coheld amounts before the Source view is built.
  let prepared_source = @hubspot_catalog.prepare_property_response_source(
    body, path, "companies", property_limits,
  )
  let data = @hubspot_catalog.property_response_source_geometry_data(
    prepared_source,
  )
  assert_eq(data.length(), 12)
  let selected = hubspot_full_metadata_response_quote(
    @hubspot_catalog.effect_metadata_observed_construction_capacity(
      body.length(),
      9,
      property_limits,
      data,
    ).unwrap(),
  )
  println(
    "Full independent body=\{body.length()} R=\{@execution.execution_capacity_retained_bytes(selected)} E=\{@execution.execution_capacity_execution_bytes(selected)} outsideE=465291759",
  )
  let input = prepare_installed_effect_operation_extent(
    "send", selected, 7L, true,
  ).unwrap()
  begin_installed_effect_operation_input(child, input).unwrap()
  let active = @resources.ledger_usage(ledger)
  let catalog = @hubspot_catalog.consume_property_response_source(
    prepared_source, path, body,
  ).unwrap()
  @hubspot_catalog.recheck_property_catalog(catalog, catalog, 256).unwrap()
  @hubspot_catalog.retire_property_response_source(prepared_source)
  complete_installed_effect_operation_response_projection(child).unwrap()
  let completed = @resources.ledger_usage(ledger)
  assert_eq(completed.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_true(
    completed.reserved_execution_bytes < active.reserved_execution_bytes,
  )
  assert_eq(completed.attempts, active.attempts)
  assert_eq(completed.transferred_bytes, active.transferred_bytes)
  assert_eq(completed.held_bytes, active.held_bytes)
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  @resources.settle_capacity(ledger, outside).unwrap()
  @resources.release_allocation(ledger, holding).unwrap()
  @resources.settle_reservation(ledger, holding_reservation).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "recovered member input keeps all row outputs and one sequential request workspace on the same quote" {
  let (prepared, request, contracts) = effect_operation_plan_inputs(
    rows="[{\"id\":1},{\"id\":2}]",
  )
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  // An original Native constructor with small returned material and a larger
  // private workspace. Recovery maps these two requests synchronously, as the
  // existing Salesforce recovery adapter does; both outputs remain retained.
  let native = @execution.execution_capacity(17L, 100000000L).unwrap()
  let warm = described_recipe_fixture(
    empty,
    true,
    request_original=Some(native),
    host_input_bytes=Some(0),
  )
  let cold = described_recipe_fixture(
    empty,
    true,
    request_original=Some(native),
    host_input_bytes=Some(32),
  )
  let maximum = described_recipe_fixture(
    empty,
    true,
    request_original=Some(native),
  )
  let capture = (recipe : Array[@execution.ExecutionCapacity]) => {
    prepare_installed_effect_host_input_capture_recipe_extent(
      "capture",
      [recipe[0], recipe[1], recipe[2], recipe[3], recipe[4], recipe[5]],
      256,
      16,
      4,
    ).unwrap()
  }
  let demand = prepare_installed_effect_operation_demand_with_controls(
    prepared,
    0,
    "save",
    [
      prepare_installed_effect_staged_extent(capture(warm), capture(maximum)).unwrap(),
    ],
    [
      prepare_installed_effect_operation_extent("request", warm[2], 0L, false).unwrap(),
    ],
    warm[4],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let quote = prepared_installed_effect_managed_requirements(plan)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan, quote,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let limits = @resources.ledger_limits(ledger)
  retain_installed_effect_operation_controls_before_construction(
    owner, prepared, request, plan,
  ).unwrap()
  |> ignore
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let selected = capture(cold)
  match begin_installed_effect_operation_input(child, selected) {
    Ok(_) => ()
    Err(Ledger(@resources.ExecutionLimit)) =>
      fail("recovered member InputBegin returned Ledger(ExecutionLimit)")
    Err(_) => fail("recovered member InputBegin returned another refusal")
  }
  let active = @resources.ledger_usage(ledger)
  assert_eq(@resources.ledger_limits(ledger), limits)
  assert_eq(active.attempts, before.attempts)
  assert_eq(active.reserved_attempts, before.reserved_attempts)
  assert_eq(active.transferred_bytes, before.transferred_bytes)
  assert_eq(active.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_true(active.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(
    begin_installed_effect_operation_input(child, selected) is Err(AlreadyBound),
  )
  complete_installed_effect_operation_construction(child).unwrap()
  let returned = @resources.ledger_usage(ledger)
  assert_eq(returned.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_true(
    returned.reserved_execution_bytes < active.reserved_execution_bytes,
  )
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "staged Effect input resolves the same two rows and grows one original constructor before work" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(current=() => {
    calls.val += 1
  })
  assert_eq(plan.rows, 2)
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let input = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(20L, 30L).unwrap(),
    @execution.execution_capacity(3L, 5L).unwrap(),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let observations = calls.val
  begin_installed_effect_operation_input(child, input).unwrap()
  assert_eq(calls.val, observations + 1)
  let grown = @resources.ledger_usage(ledger)
  assert_eq(
    grown.reserved_retention_bytes - before.reserved_retention_bytes,
    12L,
  )
  assert_eq(
    grown.reserved_execution_bytes - before.reserved_execution_bytes,
    26L,
  )
  assert_eq(grown.attempts, before.attempts)
  assert_eq(grown.reserved_attempts, before.reserved_attempts)
  assert_eq(grown.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_true(
    begin_installed_effect_operation_input(child, input) is Err(AlreadyBound),
  )
  complete_installed_effect_operation_construction(child).unwrap()
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    grown.reserved_execution_bytes - 14L,
  )
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  assert_true(
    begin_installed_effect_operation_input(child, input) is Err(Retired),
  )
  retire_installed_managed_run(owner).unwrap()
}

///|
test "cold recovered input grows the same deferred child below its unused warm workspace" {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  // The two original rows make the warm template14R/26E. Cold recovery
  // borrows its saved wire instead of regenerating it:20R/24E, not26E.
  let input = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(16L, 18L).unwrap(),
    @execution.execution_capacity(2L, 3L).unwrap(),
  ).unwrap()
  assert_eq(child.execution_limit, 26L)
  let limits = @resources.ledger_limits(ledger)
  let before = @resources.ledger_usage(ledger)
  let occupied = @resources.reserve_capacity(
    ledger,
    0L,
    limits.execution_bytes - before.reserved_execution_bytes,
  ).unwrap()
  let full = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_input(child, input)
    is Err(Ledger(@resources.ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), full)
  assert_false(child.input_selected)
  assert_false(child.started)
  @resources.settle_capacity(ledger, occupied).unwrap()
  begin_installed_effect_operation_input(child, input).unwrap()
  let active = @resources.ledger_usage(ledger)
  assert_eq(
    active.reserved_retention_bytes - before.reserved_retention_bytes,
    6L,
  )
  assert_eq(
    active.reserved_execution_bytes - before.reserved_execution_bytes,
    10L,
  )
  assert_eq(child.execution_limit, 24L)
  assert_eq(@resources.ledger_limits(ledger), limits)
  // Only byte backing grew. The same child, spent coordinate and all other
  // work/attempt/transfer/holding history remain with the original Ledger.
  assert_eq(
    {
      ..active,
      reserved_retention_bytes: before.reserved_retention_bytes,
      reserved_execution_bytes: before.reserved_execution_bytes,
      peak_retention_bytes: before.peak_retention_bytes,
    },
    before,
  )
  complete_installed_effect_operation_construction(child).unwrap()
  let returned = @resources.ledger_usage(ledger)
  assert_eq(returned.reserved_retention_bytes, active.reserved_retention_bytes)
  assert_eq(
    returned.reserved_execution_bytes,
    active.reserved_execution_bytes - 4L,
  )
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "cold input cannot replace a warm constructor whose original workspace is live" {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  begin_installed_effect_operation_construction(child).unwrap()
  let active = @resources.ledger_usage(ledger)
  let input = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(16L, 18L).unwrap(),
    @execution.execution_capacity(2L, 3L).unwrap(),
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_input(child, input) is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), active)
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "staged Effect input preserves the same physical attempt and rejects a foreign purpose or ceiling" {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture()
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  let input = prepare_installed_effect_operation_extent(
    "send",
    @execution.execution_capacity(9L, 14L).unwrap(),
    7L,
    true,
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_input(child, input) is Err(ForeignOriginal),
  )
  start_installed_effect_operation(child).unwrap()
  let before = @resources.ledger_usage(ledger)
  // The physical operation's warm execution backing is already live. Cold
  // input cannot use the deferred-constructor rule to shrink that envelope.
  let smaller_live_workspace = prepare_installed_effect_operation_extent(
    "send",
    @execution.execution_capacity(5L, 7L).unwrap(),
    7L,
    true,
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_input(child, smaller_live_workspace)
    is Err(InsufficientCapacity),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let foreign = prepare_installed_effect_operation_extent(
    "other",
    @execution.execution_capacity(9L, 14L).unwrap(),
    7L,
    true,
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_input(child, foreign)
    is Err(ForeignOriginal),
  )
  let too_large = prepare_installed_effect_operation_extent(
    "send",
    @execution.execution_capacity(1000000001L, 2000000001L).unwrap(),
    7L,
    true,
  ).unwrap()
  assert_true(
    begin_installed_effect_operation_input(child, too_large)
    is Err(InsufficientCapacity),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  begin_installed_effect_operation_input(child, input).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_eq(grown.attempts, before.attempts)
  assert_eq(grown.reserved_attempts, before.reserved_attempts)
  assert_eq(grown.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_eq(
    grown.reserved_retention_bytes - before.reserved_retention_bytes,
    4L,
  )
  assert_eq(
    grown.reserved_execution_bytes - before.reserved_execution_bytes,
    6L,
  )
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "staged Effect input retains original backing on refusal and reentrant retirement" {
  let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
  let retire = Ref(false)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(current=() => {
    if retire.val {
      retire.val = false
      retire_installed_effect_operation(selected.val.unwrap(), true).unwrap()
      |> ignore
    }
  })
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let input = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(20L, 30L).unwrap(),
    @execution.execution_capacity(3L, 5L).unwrap(),
  ).unwrap()
  let usage = @resources.ledger_usage(ledger)
  let occupied = @resources.reserve_capacity(
    ledger,
    0L,
    @resources.ledger_limits(ledger).execution_bytes -
    usage.reserved_execution_bytes,
  ).unwrap()
  let full = @resources.ledger_usage(ledger)
  assert_true(
    begin_installed_effect_operation_input(child, input)
    is Err(Ledger(@resources.ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), full)
  assert_true(!child.input_selected)
  @resources.settle_capacity(ledger, occupied).unwrap()
  selected.val = Some(child)
  retire.val = true
  assert_true(
    begin_installed_effect_operation_input(child, input) is Err(Retired),
  )
  assert_true(child.retired)
  retire_installed_managed_run(owner).unwrap()
}

///|
test "selected outcome control wire bound preserves the original Local envelope and full fallback" {
  let empty = "{\"result\":{},\"state\":\"applied\"}".length()
  assert_eq(
    installed_effect_control_wire_bound(empty, 1000000).unwrap(),
    installed_local_file_store_control_wire_bound(),
  )
  assert_eq(
    installed_effect_control_wire_bound(100000, 1000000).unwrap(),
    // Receipt envelope is881 bytes; the smaller empty receipt previously
    // selected the1510-byte Ledger maximum instead.
    100881,
  )
  assert_eq(
    installed_effect_control_wire_bound(1000000, 1000000).unwrap(),
    1000000,
  )
  assert_eq(
    installed_effect_control_wire_bound(2147483647, 1000000).unwrap(),
    1000000,
  )
  assert_true(
    installed_effect_control_wire_bound(0, 1000000) is Err(Unsupported),
  )
  assert_true(
    installed_effect_control_wire_bound(100000, 0) is Err(Unsupported),
  )
}

///|
test "physical response projection returns only its same original workspace without cleanup or history refund" {
  let calls = Ref(0)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(current=() => {
    calls.val += 1
  })
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  assert_true(
    complete_installed_effect_operation_response_projection(child)
    is Err(Unsupported),
  )
  start_installed_effect_operation(child).unwrap()
  let input = prepare_installed_effect_operation_extent(
    "send",
    @execution.execution_capacity(9L, 48L).unwrap(),
    7L,
    true,
  ).unwrap()
  begin_installed_effect_operation_input(child, input).unwrap()
  charge_installed_effect_operation(child, 2L).unwrap()
  guard child.backing
    is Some(@resources.NodeManagedRunOperationBacking::Physical(original)) else {
    fail("original physical token missing")
  }
  @resources.mark_transfer_uncertain(ledger, original, 1L).unwrap()
  @resources.mark_cleanup_pending(ledger, original).unwrap()
  let before = @resources.ledger_usage(ledger)
  let current = calls.val
  complete_installed_effect_operation_response_projection(child).unwrap()
  assert_eq(calls.val, current + 1)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after, {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - 39L,
  })
  assert_true(@resources.reservation_open(original))
  assert_true(@resources.reservation_pending(original))
  assert_true(child.input_selected && child.started && !child.retired)
  assert_true(
    complete_installed_effect_operation_construction(child) is Err(Unsupported),
  )
  complete_installed_effect_operation_response_projection(child).unwrap()
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_true(
    begin_installed_effect_operation_input(child, input) is Err(AlreadyBound),
  )
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "physical response projection preserves original current reentry fence before workspace return" {
  let selected : Ref[ClientInstalledEffectOperationBorrow?] = Ref(None)
  let reenter = Ref(false)
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture(current=() => {
    if reenter.val {
      selected.val.unwrap().retired = true
    }
  })
  let child = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "send",
  ).unwrap()
  selected.val = Some(child)
  start_installed_effect_operation(child).unwrap()
  begin_installed_effect_operation_input(
    child,
    prepare_installed_effect_operation_extent(
      "send",
      @execution.execution_capacity(9L, 48L).unwrap(),
      7L,
      true,
    ).unwrap(),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  reenter.val = true
  assert_true(
    complete_installed_effect_operation_response_projection(child)
    is Err(Retired),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Whitebox reentry simulation only; restore the original fixture for cleanup.
  reenter.val = false
  child.retired = false
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
}

///|
test "selected constructor input grows through one original preflight without another operation" {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let input = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(20L, 30L).unwrap(),
    @execution.execution_capacity(3L, 5L).unwrap(),
  ).unwrap()
  assert_true(
    grow_installed_effect_operation_input(child, input) is Err(AlreadyBound),
  )
  begin_installed_effect_operation_input(child, input).unwrap()
  let before = @resources.ledger_usage(ledger)
  let larger = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(30L, 50L).unwrap(),
    @execution.execution_capacity(3L, 5L).unwrap(),
  ).unwrap()
  grow_installed_effect_operation_input(child, larger).unwrap()
  let grown = @resources.ledger_usage(ledger)
  assert_eq(
    grown.reserved_retention_bytes - before.reserved_retention_bytes,
    10L,
  )
  assert_eq(
    grown.reserved_execution_bytes - before.reserved_execution_bytes,
    20L,
  )
  assert_eq(grown.attempts, before.attempts)
  assert_eq(grown.reserved_attempts, before.reserved_attempts)
  assert_eq(grown.transferred_bytes, before.transferred_bytes)
  assert_eq(grown.reserved_transfer_bytes, before.reserved_transfer_bytes)
  assert_true(
    grow_installed_effect_operation_input(child, input)
    is Err(InsufficientCapacity),
  )
  assert_eq(@resources.ledger_usage(ledger), grown)
  complete_installed_effect_operation_construction(child).unwrap()
  let completed = @resources.ledger_usage(ledger)
  assert_true(
    grow_installed_effect_operation_input(child, larger) is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(ledger), completed)
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "nested constructor growth preserves full-budget refusal without spending or losing prior backing" {
  let (prepared, request, plan, owner, ledger) = staged_effect_input_fixture()
  let child = retain_installed_effect_operation_construction(
    owner, prepared, request, plan, 0, false, 0, 0, "capture",
  ).unwrap()
  let input = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(20L, 30L).unwrap(),
    @execution.execution_capacity(3L, 5L).unwrap(),
  ).unwrap()
  begin_installed_effect_operation_input(child, input).unwrap()
  let usage = @resources.ledger_usage(ledger)
  let occupied = @resources.reserve_capacity(
    ledger,
    0L,
    @resources.ledger_limits(ledger).execution_bytes -
    usage.reserved_execution_bytes,
  ).unwrap()
  let full = @resources.ledger_usage(ledger)
  let larger = prepare_installed_effect_capture_extent(
    "capture",
    @execution.execution_capacity(30L, 50L).unwrap(),
    @execution.execution_capacity(3L, 5L).unwrap(),
  ).unwrap()
  assert_true(
    grow_installed_effect_operation_input(child, larger)
    is Err(Ledger(@resources.ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), full)
  @resources.settle_capacity(ledger, occupied).unwrap()
  grow_installed_effect_operation_input(child, larger).unwrap()
  complete_installed_effect_operation_construction(child).unwrap()
  assert_true(retire_installed_effect_operation(child, false) is Ok(false))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
