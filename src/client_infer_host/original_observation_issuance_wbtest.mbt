///|
// Real original Scope/Run/Model with an actual fixture provider and synthetic
// allowances. These are not installed Node profiles, Store ACKs or public E2E.
fn original_observation_setup_refusal(reason : String) -> Execution {
  println("Original observation setup refused: " + reason)
  abort(reason)
}

///|
fn original_observation_test_started(
  value : Result[Execution, Issue],
) -> Execution {
  match value {
    Ok(active) => active
    Err(OriginalCapacity(issue)) =>
      original_observation_setup_refusal(
        "OriginalCapacity(" + @debug.Repr(issue).to_string() + ")",
      )
    Err(Input(@input.RetainedInput(issue))) =>
      original_observation_setup_refusal(
        match issue {
          BindingMismatch => "Input.RetainedInput.BindingMismatch"
          InvalidDescriptor => "Input.RetainedInput.InvalidDescriptor"
          CustodyUnavailable => "Input.RetainedInput.CustodyUnavailable"
          Export(_) => "Input.RetainedInput.Export"
          Evidence(_) => "Input.RetainedInput.Evidence"
          Content(_) => "Input.RetainedInput.Content"
          Readmission(issue) =>
            "Input.RetainedInput.Readmission(" +
            @debug.Repr(issue).to_string() +
            ")"
          Import(_) => "Input.RetainedInput.Import"
        },
      )
    Err(Input(_)) => original_observation_setup_refusal("Input")
    Err(Model(_)) => original_observation_setup_refusal("Model")
    Err(Capacity(_)) => original_observation_setup_refusal("Capacity")
    Err(IdentityExport(_)) =>
      original_observation_setup_refusal("IdentityExport")
    Err(CallScope(_)) => original_observation_setup_refusal("CallScope")
    Err(InvalidAdvance) => original_observation_setup_refusal("InvalidAdvance")
  }
}

///|
fn original_observation_test_cold_setup(
  exported : @input.ClientInferRetainedInputExport,
  sequence : @relation.GeneratedSequence,
) -> (Int64, Int64) {
  let wire = @input.client_infer_retained_input_export_descriptor(exported)
  let bytes = 3 * wire.length()
  assert_true(bytes > 0 && bytes <= 24576) catch {
    _ => abort("fixture descriptor grammar")
  }
  let nodes = 128
  let fields = nodes - 1
  let depth = 8
  let parser = @source.json_shaped_construction_extent(
    bytes,
    nodes,
    depth,
    nodes,
    nodes,
    nodes,
    nodes,
    nodes,
    normalize_keys=false,
  ).unwrap()
  let index = @source.json_index_borrowed_construction_extent(
    nodes,
    fields,
    bytes.to_int64(),
    keep_spans=false,
    string_nodes=Some(nodes),
  ).unwrap()
  // Independent closed canonical DATA census: two coheld output trees,
  // ancestor Maps, recursive admission controls and the pinned sort frame.
  let n = nodes.to_int64()
  let k = fields.to_int64()
  let d = depth.to_int64() + 1L
  let maps = Int64::min(n, d)
  let members = Int64::min(k, maps * k)
  let mut size = fields
  let mut levels = 1L
  while size > 1 {
    size /= 2
    levels += 1L
  }
  let tree_h = n + 3L * n + k
  let tree_r = n + 10L * n + 4L * k
  let tree_w = n + 2L * n
  let descriptor = @relation.preparation_representation_cost({
    record_headers: 2L * tree_h +
    3L * maps +
    4L * members +
    (1L + 2L * d + n) +
    (8L + 8L * levels) +
    parser.record_headers +
    index.record_headers,
    reference_slots: 2L * tree_r +
    18L * maps +
    14L * members +
    (10L * d + 8L * n + 2L * k) +
    (5L + 13L * levels) +
    parser.reference_slots +
    index.reference_slots,
    scalar_words: 2L * tree_w +
    21L * maps +
    14L * members +
    (3L + 4L * d) +
    (9L + 27L * levels) +
    parser.scalar_words +
    index.scalar_words,
    owned_utf16_units: parser.owned_utf16_units + index.owned_utf16_units,
    owned_wire_bytes: bytes.to_int64(),
  }).unwrap()
  let observed = @input.read_client_infer_retained_input_descriptor(wire).unwrap()
  let rows = @input.client_infer_retained_input_export_rows(exported)
  let facts = @relation.prepare_retained_readmission_facts(
    @relation.generated_completion_preparation(sequence),
    observed,
    rows.length(),
    { producer_inputs: None, schema_columns: None, name_bytes: Some(10000), },
  ).unwrap()
  let mut text = 0
  for row in rows {
    text += row.length()
  }
  let importing = @input.client_infer_retained_input_facts_capacity(
    facts,
    observed.bytes,
    observed.nodes,
    observed.depth,
    text,
  ).unwrap()
  (
    descriptor + @relation.retained_readmission_facts_control_bytes(),
    @relation.execution_capacity_retained_bytes(importing),
  )
}

///|
fn original_observation_test_start(
  producer? : Ref[@resources.Reservation?]? = None,
  source? : String = infer_fixture_program,
  provider? : @model.ModelProvider = original_funded_start_provider(Ref(0)),
  run_id? : String = "run",
  spare_publication_slot? : Bool = false,
  input_body? : Bool = false,
  input_read_ceiling? : Int64? = None,
  restored_input? : Bool = false,
  restored_custody? : () -> Bool = () => true,
) -> (Execution, @resources.Ledger, @publication_host.ClientModelReadConsumer) {
  let (attempted, ledger, consumer) = original_observation_test_attempt(
    producer~,
    source~,
    provider~,
    run_id~,
    spare_publication_slot~,
    input_body~,
    input_read_ceiling~,
    restored_input~,
    restored_custody~,
  )
  (original_observation_test_started(attempted), ledger, consumer)
}

///|
fn original_observation_test_attempt(
  producer? : Ref[@resources.Reservation?]? = None,
  preparation_original? : Ref[
    (
      @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
      @resources.PreparationRetirement,
      @publication_host.ClientModelReadScope,
    )?,
  ]? = None,
  source? : String = infer_fixture_program,
  provider? : @model.ModelProvider = original_funded_start_provider(Ref(0)),
  run_id? : String = "run",
  spare_publication_slot? : Bool = false,
  input_body? : Bool = false,
  input_read_ceiling? : Int64? = None,
  restored_input? : Bool = false,
  restored_custody? : () -> Bool = () => true,
  short_restored_import? : Ref[(Int64, Int64)]? = None,
) -> (
  Result[Execution, Issue],
  @resources.Ledger,
  @publication_host.ClientModelReadConsumer,
) {
  let prepared = fixture_prepared(source~)
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let (compiled, _) = original_input_capacity_run(prepared, plan)
  // Select the original Result policy before issuing the checked read origin.
  // Do not replace an already issued Scope/Run with a newly compiled lookalike.
  let policy_wire = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let compiled = @publication_host.with_client_infer_result_policy(
    compiled,
    invocation_fixture_policy_cid(),
    policy_wire,
    16384,
    1024,
    20,
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "original-observation", run_id, "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let restored = if restored_input {
    let (occurrence, prefix) = original_composed_test_input(prepared)
    let (saved, exported) = original_restored_composed_test_saved(
      prepared, compiled, definition, occurrence, plan, restored_custody,
    ) catch {
      _ => abort("actual restored fixture must admit its original scope")
    }
    Some((occurrence, prefix, saved, exported))
  } else {
    None
  }
  let selected_retained = match short_restored_import {
    None => input_read_ceiling.unwrap_or(limits.model.ledger.retained_bytes)
    Some(observed) => {
      let (_, prefix, _, exported) = restored.unwrap()
      let (descriptor, importing) = original_observation_test_cold_setup(
        exported, prefix,
      )
      let selected = original_input_body_zero_spare_setup() +
        descriptor +
        importing -
        1L
      observed.val = (selected, importing)
      selected
    }
  }
  let ledger = @resources.create_ledger({
    ..limits.model.ledger,
    retained_bytes: selected_retained,
    attempts: Int::min(limits.model.ledger.attempts, 4),
    transfer_bytes: Int64::min(limits.model.ledger.transfer_bytes, 133072L),
  }).unwrap()
  let reservation_slots = (if producer is Some(_) { 5 } else { 4 }) +
    (if spare_publication_slot { 1 } else { 0 })
  let holding_slots = if producer is Some(_) { 3 } else { 2 }
  let original_scope = if preparation_original is Some(original) {
    let preparation : @resources.PreparationCapacity[
      @publication_host.PreparedClientProgram,
      @publication_host.PreparedClientProgram,
    ] = @resources.reserve_preparation_capacity(
      ledger,
      prepared,
      3L,
      2L,
      max_borrowers=1,
    ).unwrap()
    let identity = @resources.begin_preparation_capacity_inventory(
      preparation, prepared, reservation_slots, holding_slots, 0,
    ).unwrap()
    @resources.complete_preparation_capacity(
      preparation, prepared, prepared, 3L, 2L,
    ).unwrap()
    let retirement = @resources.transfer_preparation_retirement_to_run(
      preparation, prepared, prepared, ledger,
    ).unwrap()
    let holder = @resources.borrow_preparation_body(preparation).unwrap()
    let scope = @publication_host.bind_client_model_read_scope(
      compiled, definition, plan, ledger, identity,
    ).unwrap()
    original.val = Some((holder, retirement, scope))
    scope
  } else {
    let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
    @publication_host.begin_client_model_read_scope(
      compiled, definition, plan, ledger, bootstrap, reservation_slots, holding_slots,
      0,
    ).unwrap()
  }
  if producer is Some(record) {
    record.val = Some(@resources.reserve_attempt(ledger, 1L, 7L, 5L).unwrap())
  }
  let read = @publication_host.prepare_client_model_read(original_scope, 7L, 5L).unwrap()
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let attempted = if restored is Some((occurrence, prefix, saved, exported)) {
    start_original_restored_composed(
      occurrence,
      plan,
      prefix,
      provider,
      @input.client_infer_retained_input_export_binding(exported),
      @input.client_infer_retained_input_export_descriptor(exported),
      @input.client_infer_retained_input_export_rows(exported),
      restored_custody,
      saved,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
      input_body_read=if input_body { Some(read) } else { None },
    )
  } else if input_body {
    let (occurrence, prefix) = original_composed_test_input(prepared)
    start_original_composed(
      occurrence,
      plan,
      prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      100L,
      5L,
      input_body_read=Some(read),
    )
  } else {
    start_original_model_preparation(
      prepared,
      2,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      provider,
      limits,
      compiled,
      definition,
      plan,
      consumer,
      7L,
      5L,
      100L,
      5L,
    )
  }
  let active = match attempted {
    Err(issue) => return (Err(issue), ledger, consumer)
    Ok(value) => value
  }
  let configuration = evidence_account(@authorization.Allow)
  let permit = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-12T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-12T00:00:00.000Z")),
  ).unwrap()
  bind_dispatch_admission(active, permit).unwrap()
  (Ok(active), ledger, consumer)
}

///|
// One owner-boundary witness: the production initial-retention constructor
// extends its adopted preparation bootstrap through the same Resource resize.
// This isolates that transition on an already issued original binding; it is
// not execution of the complete Node caller or a physical cleanup ACK.
test "original issued binding retains current after same bootstrap publication growth" {
  let preparation : Ref[
    (
      @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
      @resources.PreparationRetirement,
      @publication_host.ClientModelReadScope,
    )?,
  ] = Ref(None)
  let (attempted, ledger, consumer) = original_observation_test_attempt(
    preparation_original=Some(preparation),
  )
  let active = original_observation_test_started(attempted)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  issuance_finish(issued)
  let bound = active.run_binding.unwrap()
  let binding = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  assert_true(invocation_binding_output(binding) is Some(_))
  assert_true(observation_issuance_value(issued) is Some(_))
  let before = @resources.ledger_usage(ledger)
  let (holder, retirement, scope) = preparation.val.unwrap()
  let body = @resources.preparation_body_borrow_value(holder).unwrap()
  @resources.reserve_preparation_publication_phase(holder, body, 4L, 3L).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.transferred_bytes, before.transferred_bytes)
  assert_true(
    !binding.output_use.released && !binding.output_use.owner.reclaimed,
  )
  assert_true(
    binding.issuance is Some(actual) && physical_equal(actual, issued),
  )
  let original_read_current = @publication_host.client_model_read_consumer_handed_off_current(
    consumer,
    bound.compiled,
    bound.definition,
    active.plan.unwrap(),
  )
  let model_capacity_current = @model.original_model_publication_capacity_current(
    capacity,
    active.model.unwrap(),
    active.call_scope.unwrap(),
  )
  let raw_output_live = output(binding.output_use) is Some(_)
  let issued_current = observation_issuance_value(issued) is Some(_)
  let bound_output_live = invocation_binding_output(binding) is Some(_)
  let result_after = start_result_publication(
    binding,
    0,
    publication_result_limits(),
  )
  let result_refused = match result_after {
    Err(InvalidState) => true
    Err(_) => abort("unexpected original Result publication issue")
    Ok(result) => {
      assert_true(release_result_publication(result))
      false
    }
  }
  println(
    "Same original bootstrap witness (read, model-capacity, raw-output, issuance, bound-output, Result-InvalidState): " +
    @debug.Repr(
      (
        original_read_current, model_capacity_current, raw_output_live, issued_current,
        bound_output_live, result_refused,
      ),
    ).to_string(),
  )
  assert_true(bound_output_live)
  assert_false(result_refused)
  assert_true(release_invocation_binding(binding))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
  @publication_host.settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      bound.compiled,
      bound.definition,
      active.plan.unwrap(),
      true,
    ).unwrap(),
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  assert_true(@resources.retire_transferred_preparation(retirement).unwrap())
}

///|
test "original observation issuance retains same completed producer output and pending scratch" {
  let producer : Ref[@resources.Reservation?] = Ref(None)
  let (active, ledger, _) = original_observation_test_start(
    producer=Some(producer),
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let producer = producer.val.unwrap()
  let output = @resources.retain_allocation(ledger, producer, 4L).unwrap()
  @resources.settle_completed_output_reservation(
    ledger,
    producer,
    Some(output),
    4L,
    3L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@resources.reservation_pending(producer))
  issuance_finish(issued)
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  // Publication retirement is not the independent producer scratch/output ACK.
  assert_true(@resources.reservation_pending(producer))
  @resources.settle_reservation(ledger, producer).unwrap()
  @resources.release_allocation(ledger, output).unwrap()
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation issuance keeps same funding through binding and caller retirement" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  // The existing metadata component is 16 * 4096 + 1 * 128. The execution
  // allowance is a synthetic test grant, not a full Node physical profile.
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(issued.state.count, 1)
  issuance_finish(issued)
  let after = @resources.ledger_usage(ledger)
  assert_eq(after.planning_work, before.planning_work + 3)
  assert_eq(after.attempts, before.attempts)
  assert_eq(after.reserved_retention_bytes, before.reserved_retention_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  let bound = active.run_binding.unwrap()
  let first = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  let second = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  assert_false(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_invocation_binding(first))
  assert_false(cleanup_observation_issuance(issued).unwrap())
  assert_true(invocation_binding_output(second) is Some(_))
  assert_true(release_invocation_binding(second))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(issued.state.funding is None)
  assert_true(issued.state.owners.is_empty())
  assert_true(issued.state.captures.is_empty())
  assert_true(issued.state.output_uses.is_empty())
  assert_true(issued.state.slots.is_empty())
  assert_true(observation_issuance_value(issued) is None)
  // Issuer cleanup is not acknowledgement of later Store bodies/alias cleanup.
  assert_eq(@resources.ledger_usage(ledger), after)
  assert_false(cleanup(active).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  // Retire the metadata payload and the carrier's one additional 8-byte
  // optional reference, which was admitted even while it contained None.
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    after.reserved_retention_bytes - 65672L,
  )
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation issuance refuses one short foreign and released borrows before capture" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let short = reserve_original_infer_publication_capacity(active, 65663L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let uses = active.output_uses
  assert_true(
    start_original_observation_issuance(active, short, issuance_limits())
    is Err(Model(@model.Ledger(@resources.RetentionLimit))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(active.output_uses, uses)
  assert_true(release_original_infer_publication_capacity(short).unwrap())
  assert_true(
    start_original_observation_issuance(active, short, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  let (foreign, foreign_ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(
    foreign, 65664L, 7L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let other_before = @resources.ledger_usage(foreign_ledger)
  assert_true(
    start_original_observation_issuance(active, capacity, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(foreign_ledger), other_before)
  assert_eq(active.output_uses, uses)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(foreign).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation cancellation after positive work keeps caller capacity" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_false(advance_observation_issuance(issued, 1).unwrap().0)
  assert_eq(
    @resources.ledger_usage(ledger).planning_work,
    before.planning_work + 1,
  )
  assert_true(cancel_observation_issuance(issued))
  assert_true(
    advance_observation_issuance(issued, 1) is Err(Model(@model.Cancelled)),
  )
  assert_true(observation_issuance_value(issued) is None)
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  assert_false(cleanup(active).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "original observation handed off read stop refuses new issuance without blocking cleanup" {
  let (active, ledger, consumer) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  @publication_host.stop_client_model_read_consumer(consumer).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    reserve_original_infer_publication_capacity(active, 65664L, 7L)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    start_original_observation_issuance(active, capacity, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    advance_observation_issuance(issued, 1) is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Stopping is not a new dispatch grant and is not release of this borrow.
  // It also must not require a dispatch Allow to retire already-owned metadata.
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "complete original observation refuses duplicate and foreign parent before metadata mutation" {
  let (active, ledger, _) = original_observation_test_start()
  let (foreign, foreign_ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let foreign_before = @resources.ledger_usage(foreign_ledger)
  for owners in [[], [active, active], [active, foreign]] {
    assert_true(
      start_complete_original_observation_issuance(
        owners,
        capacity,
        issuance_limits(),
      )
      is Err(Model(@model.OutputIdentity)),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
  }
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(foreign).unwrap())
}

///|
// Real checked two-Model Program, Task compiler, original Scope group and
// native Model executions. Provider/Account and finite Resource allowances are
// explicit component ports, not normal installed IO/backing or public Saved.
test "complete original observation keeps compiler order when the second Model owns the one publication borrow" {
  let source =
    #|{"version":"actql/0.1","id":"two-original-publications","stages":[{"id":"first","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"first"}]},"as":"seed"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"second","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"second"}]},"as":"seed"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}}],"results":{"first":{"from":{"stage":"first","result":"rows"}},"second":{"from":{"stage":"second","result":"rows"}}}}
  let prepared = fixture_prepared(source~)
  let occurrences = @publication_host.prepared_client_composed_infer_occurrences(
    prepared,
  ).unwrap()
  assert_eq(occurrences.length(), 2)
  let plans = occurrences.map(occurrence => {
    // Reuse the existing independent execution-contract fixture. The normal
    // installed graph issuer excludes per-component Result roots; the ONE
    // multi compiler below owns this Program's complete named Result roots.
    let contract = @publication_host.client_infer_plan_graph_execution_contract(
      call_identity_plan(prepared, occurrence=Some(occurrence)),
    )
    @publication_host.issue_installed_client_composed_infer_plan_graph(
      occurrence,
      contract,
      @publication_host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ).unwrap()
  })
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_multi_infer_compilation(
    prepared,
    plans,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = @publication_host.with_client_infer_result_policy(
    compiled,
    invocation_fixture_policy_cid(),
    "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    16384,
    1024,
    20,
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "two-original-models", "same-original", "2026-11-04T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let limits = standard_limits()
  let pair = @resources.add_ledger_limits(
    limits.model.ledger,
    limits.model.ledger,
  ).unwrap()
  let ledger = @resources.create_ledger({
    ..pair,
    retained_bytes: pair.retained_bytes + 1000017L,
    execution_bytes: pair.execution_bytes + 1000012L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 64, 64, 0,
  ).unwrap()
  // Real byte-only parent capacity, registered BEFORE the original Read
  // descriptor/child scopes. This is not an attempt or a replacement token.
  let parent_window = @resources.reserve_capacity(ledger, 13L, 17L).unwrap()
  let scopes = @publication_host.bind_client_model_read_scopes(
    compiled,
    definition,
    plans,
    ledger,
    identity,
    [7L, 7L],
    [5L, 5L],
  ).unwrap()
  let reads = [
    @publication_host.prepare_client_model_read(scopes[0], 7L, 5L).unwrap(),
    @publication_host.prepare_client_model_read(scopes[1], 7L, 5L).unwrap(),
  ]
  let owners : Array[Execution?] = [None, None]
  let calls = [Ref(0), Ref(0)]
  for index in [1, 0] {
    let provider = original_funded_start_provider(calls[index])
    let occurrence = occurrences[index]
    let prefix = @input.prepare_client_composed_infer_prefix(
      prepared,
      occurrence,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
    ).unwrap()
    let consumer = @publication_host.claim_client_model_read_preparation(
      reads[index],
      compiled,
      definition,
      plans[index],
      7L,
      5L,
    ).unwrap()
    let active = start_original_composed(
      occurrence,
      plans[index],
      prefix,
      [],
      provider,
      limits,
      compiled,
      definition,
      consumer,
      7L,
      5L,
      // Same independently selected startup sub-window as the existing
      // original-observation fixture, not the TOTAL per-Model ledger ceiling.
      // Actual attempt/publication reservations still spend that unchanged
      // total ceiling beside this startup; neither is removed or relaxed.
      100L,
      5L,
      input_body_read=Some(reads[index]),
    ).unwrap()
    // Multi-Model dispatch selects the existing original per-occurrence
    // BoundModelInvocationScope. The singular no-scope getter must refuse;
    // it cannot choose a first Plan or grant another member its authority.
    let account = Ref(evidence_account(@authorization.Allow))
    let (active, prepared_calls, admission, prefix_work) = entry_gate_fixture(
      calls[index],
      account,
      Ref("2026-11-04T00:00:00.000Z"),
      Ref(Some(egress_fixture_observation())),
      start_original=Some(() => active),
      slots=1,
    )
    bind_model_dispatch(active, prepared_calls, admission, entry => {
      @model.acknowledge_model_call_entry(entry, prepared_calls).unwrap()
      |> ignore
      true
    }).unwrap()
    let after = fixture_finish(active, initial_work=prefix_work)
    match after {
      Complete(_, ..) => ()
      Settling(_, work~) => {
        assert_true(
          @model.acknowledge_model_call_settlement(
            call_settlement(active).unwrap(),
          ),
        )
        assert_true(
          fixture_finish(active, initial_work=work) is Complete(_, ..),
        )
      }
      _ =>
        abort(
          "actual original Model must complete or retain its original settlement",
        )
    }
    owners[index] = Some(active)
    assert_true(active.identity_body.unwrap().retained > 7L)
  }
  assert_eq(calls[0].val + calls[1].val, 2)
  let ordered = [owners[0].unwrap(), owners[1].unwrap()]
  let before_quote = @resources.ledger_usage(ledger)
  let (publication_limits, publication_bytes) = original_model_observation_requirements(
    ordered, plans,
  ).unwrap()
  assert_eq(publication_limits.max_slots, 2)
  assert_eq(@resources.ledger_usage(ledger), before_quote)
  assert_true(
    original_model_observation_requirements([ordered[1], ordered[0]], plans)
    is None,
  )
  assert_true(
    original_model_observation_requirements(ordered, [plans[1], plans[0]])
    is None,
  )

  // Join the ordinary sequence: both Model inputs already grew on the same
  // Read, then the original parent window grows before publication uses its
  // retained descriptor. Its first snapshot remains the original minimum.
  let before_window = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  @resources.grow_capacity_reservation(ledger, parent_window, 29L, 31L).unwrap()
  let after_window = @resources.ledger_usage(ledger)
  assert_eq(
    after_window.reserved_retention_bytes,
    before_window.reserved_retention_bytes + 16L,
  )
  assert_eq(
    after_window.reserved_execution_bytes,
    before_window.reserved_execution_bytes + 14L,
  )
  assert_eq(after_window.live_reservations, before_window.live_reservations)
  assert_eq(after_window.attempts, before_window.attempts)
  assert_eq(after_window.planning_work, before_window.planning_work)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  let publication_extent = @model.original_model_publication_payload_extent(
    publication_bytes,
  ).unwrap()
  let publication = reserve_original_infer_publication_capacity(
    ordered[1],
    publication_bytes - 1L,
    publication_bytes,
  ).unwrap()
  let child = ordered[1].limits.model.ledger
  let parent = @resources.ledger_limits(ledger)
  assert_eq(
    @model.original_model_publication_retained_bytes(publication),
    publication_extent - 1L,
  )
  let before = @resources.ledger_usage(ledger)
  let issued = start_complete_original_observation_issuance(
    ordered, publication, publication_limits,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  issuance_finish(issued)
  let (observation, invocation) = observation_issuance_value(issued).unwrap()
  assert_eq(@publication.model_observation_slot_count(observation), Some(2))
  let before_projection = @resources.ledger_usage(ledger)
  assert_true(
    original_model_publication_inputs(issued, compiled, definition) is None,
  )
  assert_eq(@resources.ledger_usage(ledger), before_projection)
  grow_original_infer_publication_capacity(
    ordered[1],
    publication,
    publication_extent,
    publication_extent,
  ).unwrap()
  assert_eq(ordered[1].limits.model.ledger, child)
  assert_eq(@resources.ledger_limits(ledger), parent)
  {
    let (inputs, evidence) = original_model_publication_inputs(
      issued, compiled, definition,
    ).unwrap()
    let template = @publication_host.client_compiled_run_template(compiled)
    let policy = invocation_fixture_policy_cid()
    assert_true(
      @publication.model_invocation_matches(
        template, observation, invocation, inputs, policy,
      ),
    )
    assert_not_eq(inputs[0], inputs[1])
    assert_false(
      @publication.model_invocation_matches(
        template,
        observation,
        invocation,
        [inputs[1], inputs[0]],
        policy,
      ),
    )
    assert_false(
      @publication.model_invocation_matches(
        template,
        observation,
        invocation,
        inputs,
        "sha256:" + "9".repeat(64),
      ),
    )
    for index, owner in ordered {
      assert_eq(
        inputs[index],
        @publication.run_evidence_value_identity(
          @publication_host.client_infer_call_scope_artifact(
            owner.call_scope.unwrap(),
          ),
        ),
      )
      assert_true(
        physical_equal(evidence[index], invocation_evidence(owner, 0).unwrap()),
      )
    }
  }
  // This publication lifetime may exceed the immutable component limit if
  // the same parent Ledger admits it, with no Model work or extra authority.
  grow_original_infer_publication_capacity(
    ordered[1],
    publication,
    Int64::max(publication_extent, child.retained_bytes + 1L),
    Int64::max(publication_extent, child.execution_bytes + 1L),
  ).unwrap()
  assert_eq(ordered[1].limits.model.ledger, child)
  assert_eq(@resources.ledger_limits(ledger), parent)
  // Bind EVERY original execution to the SAME complete issuer. The second
  // execution still owns the one publication borrow; child order is not a
  // substitute for the checked Unit coordinate in either observation.
  let bindings = ordered.map(active => {
    bind_issued_invocation(active, compiled, definition, issued).unwrap()
  })
  let originals = bindings.mapi((index, binding) => {
    let outcomes = invocation_binding_original_model_outcomes(binding).unwrap()
    let receipt = local_model_observation_test_export(outcomes)
    let projection = invocation_binding_original_model_observation_capacity(
      binding, receipt, 4096,
    ).unwrap()
    grow_original_infer_publication_capacity(
      ordered[1],
      publication,
      child.retained_bytes +
      1L +
      @relation.execution_capacity_retained_bytes(projection),
      child.execution_bytes +
      1L +
      @relation.execution_capacity_execution_bytes(projection),
    ).unwrap()
    let original = issue_invocation_binding_original_model_observation(
      binding, receipt, 4096, 1024, 20,
    ).unwrap()
    assert_eq(
      original_local_model_observation_coordinates(original).unwrap().1,
      index,
    )
    let inputs = original_local_model_observation_input_bodies(original).unwrap()
    assert_eq(
      inputs[0],
      (
        "relation_value",
        "{\"sort\":\"relation\",\"value\":[{\"id\":\"a\",\"text\":\"" +
        (if index == 0 { "first" } else { "second" }) +
        "\"}]}",
      ),
    )
    @relation.cancel_completed_relation_export_receipt(receipt)
    original
  })
  assert_false(
    @publication.captured_effect_dependency_body_cid(
      original_local_model_observation_body(originals[0]).unwrap(),
    ) ==
    @publication.captured_effect_dependency_body_cid(
      original_local_model_observation_body(originals[1]).unwrap(),
    ),
  )
  assert_false(cleanup_observation_issuance(issued).unwrap())
  for binding in bindings {
    assert_true(release_invocation_binding(binding))
  }
  for original in originals {
    assert_true(original_local_model_observation_coordinates(original) is None)
  }
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(
    original_model_publication_inputs(issued, compiled, definition) is None,
  )
  assert_true(release_original_infer_publication_capacity(publication).unwrap())
  for index in 0..<2 {
    assert_true(cleanup(ordered[index]).unwrap())
    @publication_host.settle_client_model_read(reads[index], true).unwrap()
  }
  @resources.settle_capacity(ledger, parent_window).unwrap()
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      plans[0],
      true,
    ).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scopes[1],
      compiled,
      definition,
      plans[1],
      true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 2)
}

///|
test "original observation metadata quote reads the same completed row inventory without debit" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(
    original_observation_issuance_metadata_bytes(active, issuance_limits())
    is None,
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  let before = @resources.ledger_usage(ledger)
  let uses = active.output_uses
  assert_eq(
    original_observation_issuance_metadata_bytes(active, issuance_limits()),
    Some(65664L),
  )
  assert_true(
    original_observation_issuance_metadata_bytes(active, {
      ..issuance_limits(),
      max_slots: 0,
    })
    is None,
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(active.output_uses, uses)
  cancel(active) |> ignore
  assert_true(cleanup(active).unwrap())
  assert_true(
    original_observation_issuance_metadata_bytes(active, issuance_limits())
    is None,
  )
}
