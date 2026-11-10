///|
// Real admitted Definition and existing Run Ledger; explicit component current
// ports supply no HTTP/Store/physical-close or ordinary execution evidence.
fn definition_capacity_fixture(
  run_id : String,
  current? : () -> Unit = () => (),
) -> (
  ClientInstalledEffectCaptureRecovery,
  ClientInstalledManagedRun,
  @resources.Ledger,
  @publication.PublicationContract,
) {
  let (prepared, request, definition) = capture_recovery_originals(run_id~)
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[4] = 536870912L
  quote[5] = 536870912L
  let (input, initial, _, capacity) = effect_preparation_test_capacity(
    plan,
    quote,
    current~,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let recovery = prepare_installed_effect_capture_recovery(
    run, prepared, request, definition, 100000, 10000, 100,
  ).unwrap()
  (recovery, run, run.ledger.unwrap(), definition)
}

///|
test "Definition success retains actual Unicode tree and full text then SAME begin regrows before admission" {
  for text in ["small", "😀漢字,:[\\\"".repeat(1024)] {
    let (owner, run, ledger, definition) = definition_capacity_fixture(text)
    assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
    let wire = @publication.publication_contract_json(definition)
    let (bytes, nodes, depth) = @publication.publication_contract_wire_usage(
      definition,
    ).unwrap()
    // Eight required scalars, version, identity, optional selection, one object.
    let expected_nodes = if @publication.publication_contract_effect_target_selections_cid(
        definition,
      )
      is Some(_) {
      12
    } else {
      11
    }
    assert_eq((nodes, depth), (expected_nodes, 1))
    if text != "small" {
      assert_true(bytes > wire.length())
      assert_true(wire.length() > 10000)
    }
    let original_fixed = owner.fixed.unwrap()
    let peak = @resources.ledger_usage(ledger)
    begin_installed_effect_capture_recovery(owner).unwrap()
    let admitted = @publication.admit_publication_contract(
      "run_definition", wire, bytes, nodes, depth,
    ).unwrap()
    assert_eq(@publication.publication_contract_json(admitted), wire)
    complete_installed_effect_capture_recovery(owner).unwrap()
    let completed = @resources.ledger_usage(ledger)
    let released = @execution.execution_capacity_inventory_bytes([
      {
        unit: ValueNodeSlots,
        count: (wire.length() - nodes).to_int64(),
        copies: 1,
      },
    ]).unwrap()
    assert_true(released > 0L)
    assert_eq(completed, {
      ..peak,
      reserved_retention_bytes: peak.reserved_retention_bytes - released,
      reserved_execution_bytes: peak.reserved_execution_bytes - released,
    })
    assert_true(physical_equal(owner.fixed.unwrap(), original_fixed))
    // Complete returned tree and the unchanged entire text/control allowance
    // remain held. A completed constructor does not settle its owner.
    let retained = request_effect_capture_recovery_capacity(
      0,
      wire.length(),
      100000,
      10000,
      100,
      definition_nodes=Some(nodes),
    ).unwrap()
    assert_true(
      @resources.capacity_reservation_matches(
        ledger,
        original_fixed,
        @execution.execution_capacity_retained_bytes(retained),
        @execution.execution_capacity_execution_bytes(retained),
      ),
    )
    assert_eq(@publication.publication_contract_json(admitted), wire)
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    let free = 536870912L - completed.reserved_execution_bytes
    let pressure = @resources.reserve_capacity(ledger, 0L, free - released + 1L).unwrap()
    let pressured = @resources.ledger_usage(ledger)
    assert_true(
      begin_installed_effect_capture_recovery(owner)
      is Err(Ledger(ExecutionLimit)),
    )
    assert_eq(@resources.ledger_usage(ledger), pressured)
    assert_true(physical_equal(owner.fixed.unwrap(), original_fixed))
    @resources.settle_capacity(ledger, pressure).unwrap()
    begin_installed_effect_capture_recovery(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger), peak)
    // A failed subsequent constructor has no completion: the full peak stays.
    assert_true(
      @publication.admit_publication_contract(
        "run_definition",
        wire,
        bytes,
        nodes - 1,
        depth,
      )
      is Err(_),
    )
    assert_eq(@resources.ledger_usage(ledger), peak)
    retire_installed_effect_capture_recovery(owner).unwrap()
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "Definition completion and regrowth keep foreign current and reentry responsibility" {
  let (other, other_run, foreign_ledger, _) = definition_capacity_fixture(
    "other",
  )
  for completing in [true, false] {
    for selected_mode in [1, 2, 3] {
      let selected : Ref[ClientInstalledEffectCaptureRecovery?] = Ref(None)
      let mode = Ref(0)
      let reentry_refused = Ref(false)
      let (owner, run, ledger, _) = definition_capacity_fixture(
        "漢字".repeat(512),
        current=() => {
          if mode.val == 1 {
            capture_recovery_current_refusal()
          }
          if mode.val == 2 {
            selected.val.unwrap().closing = true
          }
          if mode.val == 3 {
            reentry_refused.val = begin_installed_effect_capture_recovery(
                selected.val.unwrap(),
              )
              is Err(Retired)
          }
        },
      )
      selected.val = Some(owner)
      if !completing {
        complete_installed_effect_capture_recovery(owner).unwrap()
      }
      let before = @resources.ledger_usage(ledger)
      let foreign = { ..owner, ledger: Some(foreign_ledger), }
      let foreign_before = @resources.ledger_usage(foreign_ledger)
      assert_true(complete_installed_effect_capture_recovery(foreign) is Err(_))
      assert_true(begin_installed_effect_capture_recovery(foreign) is Err(_))
      assert_eq(@resources.ledger_usage(ledger), before)
      assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
      mode.val = selected_mode
      let result = if completing {
        complete_installed_effect_capture_recovery(owner)
      } else {
        begin_installed_effect_capture_recovery(owner)
      }
      if selected_mode == 3 {
        assert_true(result is Ok(_))
        assert_true(reentry_refused.val)
      } else {
        assert_true(result is Err(_))
        assert_eq(@resources.ledger_usage(ledger), before)
      }
      // A failed physical current is not revived for another constructor.
      // Its same original owner proceeds only through retirement.
      mode.val = 0
      owner.closing = false
      retire_installed_effect_capture_recovery(owner).unwrap()
      assert_true(
        begin_installed_effect_capture_recovery(owner) is Err(Retired),
      )
      retire_installed_managed_run(run).unwrap()
    }
  }
  retire_installed_effect_capture_recovery(other).unwrap()
  retire_installed_managed_run(other_run).unwrap()
}
