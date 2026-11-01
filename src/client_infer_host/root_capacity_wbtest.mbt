///|
test "caller Ledger does not fund an original Model root before input construction" {
  let prepared = fixture_prepared()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let prefix = @input.prepare_client_composed_infer_prefix(
    prepared,
    occurrence,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
  ).unwrap()
  let limits = standard_limits()
  // Retain the existing independent estimate; it is not allocation authority.
  let capacity = keyed_root_capacity(occurrence, prefix, None, limits).unwrap()
  let retained = @relation.execution_capacity_retained_bytes(capacity)
  let executing = @relation.execution_capacity_execution_bytes(capacity)
  assert_true(retained > 0L && executing > 0L)
  let constructed = Ref(0)
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.ProviderError)
  }).unwrap()
  for mode in 0..<3 {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 1,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: if mode == 0 {
        retained - 1L
      } else {
        retained
      },
      execution_bytes: if mode == 1 {
        executing - 1L
      } else {
        executing
      },
    }).unwrap()
    let before = @resources.ledger_usage(ledger)
    let quantities = @resources.quantity_usage(ledger)
    let binding = start_occurrence(
      occurrence,
      None,
      Physical(provider),
      @publication_host.client_infer_plan_graph_request_cid(
        call_identity_plan(prepared),
      ),
      limits,
      Some(call_identity_plan(prepared)),
      _ => {
        constructed.val += 1
        Err(@input.UnsupportedProgram)
      },
      root=Some((prefix, None, ledger)),
    )
    assert_true(
      binding is Err(OriginalCapacity(@publication_host.ForeignInput)),
    )
    assert_eq(constructed.val, 0)
    assert_eq(calls.val, 0)
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}
