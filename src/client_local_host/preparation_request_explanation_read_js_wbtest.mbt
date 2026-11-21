///|
test "structural read uses one original Request and excludes Result work" {
  let input = [1]
  let owner = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let original_capacity = owner.capacity
  let before = @resources.ledger_usage(owner.ledger)
  begin_request_explanation_read(owner, input).unwrap()
  let entry = @resources.ledger_usage(owner.ledger)
  assert_true(entry.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_true(entry.reserved_execution_bytes > before.reserved_execution_bytes)
  assert_eq(entry.live_reservations, before.live_reservations)
  assert_true(physical_equal(owner.capacity, original_capacity))
  assert_true(
    reserve_request_explanation_read(owner, [1], 4096, 4096, 128, 32)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), entry)
  reserve_request_explanation_read(owner, input, 4096, 4096, 128, 32).unwrap()
  let ready = @resources.ledger_usage(owner.ledger)
  assert_true(ready.reserved_retention_bytes > entry.reserved_retention_bytes)
  assert_true(ready.reserved_execution_bytes > entry.reserved_execution_bytes)
  assert_eq(ready.live_reservations, before.live_reservations)
  assert_true(owner.result_read is None && owner.result_read_metadata is None)
  assert_true(
    reserve_request_result_read(owner, input, 1, 1, 1, 2, 1) is Err(WrongPhase),
  )
  assert_true(
    reserve_request_explanation_read(owner, input, 4096, 4096, 128, 32)
    is Err(WrongPhase),
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
}

///|
test "structural read entry refuses one short before metadata constructors" {
  let policy = client_local_resource_policy()
  let baseline = client_request_preparation_control_capacity(policy).unwrap().0
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  for short in [false, true] {
    let input = [1]
    let entry = request_explanation_read_entry_bytes
    let shortage = if short { 1L } else { 0L }
    let owner = begin_request_preparation(
      request_parent_fixture(
        input,
        initial_limits=Some({
          ..limits,
          retained_bytes: baseline + entry - shortage,
          execution_bytes: entry,
        }),
      ),
      input,
      policy,
    ).unwrap()
    let before = @resources.ledger_usage(owner.ledger)
    let result = begin_request_explanation_read(owner, input)
    if short {
      assert_true(result is Err(Capacity(Resource(@resources.RetentionLimit))))
      assert_eq(@resources.ledger_usage(owner.ledger), before)
      assert_true(owner.phase == Open)
    } else {
      result.unwrap()
      assert_true(owner.phase == ExplanationRead)
      let admitted = @resources.ledger_usage(owner.ledger)
      assert_true(
        reserve_request_explanation_read(owner, input, 4096, 4096, 128, 32)
        is Err(Capacity(_)),
      )
      assert_eq(@resources.ledger_usage(owner.ledger), admitted)
      assert_true(owner.phase == ExplanationRead)
    }
    abort_request_preparation_after_cleanup(owner).unwrap()
    assert_eq(
      @resources.ledger_usage(owner.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "structural read constructor enforces admitted bounds and same Request through original map binding" {
  let (producer, run, prepared, compiled, definition) = original_explanation_capture_fixture()
  let captured = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  let (view, facts) = installed_original_explanation_capture_wires(captured).unwrap()
  let definition_wire = @publication.publication_contract_json(definition)
  let plan_wire = @publication.publication_contract_json(
    @publication_host.client_compiled_run_plan(compiled),
  )
  let stored = [definition_wire, plan_wire, view, facts].fold(init=142, (
    total,
    wire,
  ) => total + @scalar.admit_utf8_length(wire, 1000000).unwrap())
  let input = [7]
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let active = Ref(false)
  let fenced = Ref(false)
  let owner = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      if active.val && selected.val is Some(owner) {
        fenced.val = abort_request_preparation_after_cleanup(owner)
          is Err(WrongPhase)
      }
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  selected.val = Some(owner)
  let original_capacity = owner.capacity
  begin_request_explanation_read(owner, input).unwrap()
  reserve_request_explanation_read(owner, input, stored, 65536, 8192, 64).unwrap()
  let before = @resources.ledger_usage(owner.ledger)
  let identity = @publication_host.prepared_client_identity(prepared)
  let definition_cid = @publication.publication_contract_identity(definition)
  assert_true(
    read_request_explanation_view(
      owner,
      input,
      definition_wire,
      Some(plan_wire),
      Some(view),
      Some(facts),
      identity.program_definition_cid,
      identity.parameter_values_cid,
      "explanation-component",
      "sha256:" + "a".repeat(64),
      definition_cid,
      stored + 1,
      65536,
      8192,
      64,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  active.val = true
  {
    let wire = read_request_explanation_view(
      owner,
      input,
      definition_wire,
      Some(plan_wire),
      Some(view),
      Some(facts),
      identity.program_definition_cid,
      identity.parameter_values_cid,
      "explanation-component",
      "sha256:" + "a".repeat(64),
      definition_cid,
      stored,
      65536,
      8192,
      64,
    ).unwrap()
    assert_true(
      @publication.parse_interactive_run_control_shape(
        "run_explanation_view", wire, 65536, 8192, 64,
      )
      is Ok(_),
    )
    assert_true(fenced.val)
    assert_true(owner.phase == ExplanationReadComplete)
    assert_true(physical_equal(owner.capacity, original_capacity))
    assert_eq(
      @resources.ledger_usage(owner.ledger).live_reservations,
      before.live_reservations,
    )
    assert_true(
      @resources.ledger_usage(owner.ledger).reserved_execution_bytes >
      before.reserved_execution_bytes,
    )
  }
  active.val = false
  // The read-local output/parser frames above have unwound. Original stored
  // input fixtures still belong to their separate producing Run, not this Read.
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(owner.ledger).reserved_execution_bytes, 0L)
  return_installed_original_explanation_capture(captured).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(
    @resources.ledger_usage(producer.ledger).reserved_retention_bytes,
    0L,
  )
}

///|
test "legacy retained wire extent preserves the public encoding rejection" {
  let (producer, run, prepared, compiled, definition) = original_explanation_capture_fixture()
  let captured = capture_installed_managed_run_explanation(
    run, prepared, compiled, definition, 65536, 8192, 64,
  ).unwrap()
  let (view, facts) = installed_original_explanation_capture_wires(captured).unwrap()
  let definition_wire = @publication.publication_contract_json(definition)
  let plan_wire = @publication.publication_contract_json(
    @publication_host.client_compiled_run_plan(compiled),
  )
  let bytes = wire => @scalar.admit_utf8_length(wire, 1000000).unwrap()
  let identity = @publication_host.prepared_client_identity(prepared)
  let view_bytes = bytes(view)
  assert_true(bytes(facts) < view_bytes)
  // Use the exact issued Plan and Facts for the Plan one-short case. For the
  // independent Facts boundary simulate an oversized stored representation
  // of those same facts, with the complete original Plan inside the limit.
  let oversized_facts = facts + " ".repeat(view_bytes - bytes(facts) + 1)
  for
    (max_bytes, facts_wire) in [
      (view_bytes - 1, facts),
      (view_bytes, oversized_facts),
    ] {
    let stored = 142 +
      bytes(definition_wire) +
      bytes(plan_wire) +
      view_bytes +
      bytes(facts_wire)
    let input = [7]
    let owner = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    begin_request_explanation_read(owner, input).unwrap()
    reserve_request_explanation_read(owner, input, stored, max_bytes, 8192, 64).unwrap()
    let outcome = read_request_explanation_view(
      owner,
      input,
      definition_wire,
      Some(plan_wire),
      Some(view),
      Some(facts_wire),
      identity.program_definition_cid,
      identity.parameter_values_cid,
      "explanation-component",
      "sha256:" + "a".repeat(64),
      @publication.publication_contract_identity(definition),
      stored,
      max_bytes,
      8192,
      64,
    )
    guard outcome is Err(issue) else {
      fail("expected bounded legacy rejection")
    }
    assert_true(issue is Projection(Contract(InvalidWire)))
    assert_eq(
      request_explanation_read_issue_code(issue),
      "RunExplanationEncodingRejected",
    )
    abort_request_preparation_after_cleanup(owner).unwrap()
    assert_eq(
      @resources.ledger_usage(owner.ledger).reserved_retention_bytes,
      0L,
    )
  }
  return_installed_original_explanation_capture(captured).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(
    @resources.ledger_usage(producer.ledger).reserved_retention_bytes,
    0L,
  )
}
