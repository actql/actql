///|
test "installed Model root reserves its original envelope until cleanup" {
  let prepared = fixture_prepared()
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let prefix = @input.prepare_client_composed_infer_prefix(
    prepared, occurrence, infer_fixture_registry, infer_fixture_values,
  ).unwrap()
  let limits = standard_limits()
  let capacity = keyed_root_capacity(occurrence, prefix, None, limits).unwrap()
  let retained = @relation.execution_capacity_retained_bytes(capacity)
  let executing = @relation.execution_capacity_execution_bytes(capacity)
  assert_true(retained > 0L && executing > 0L)
  let ledger_limits : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: retained,
    execution_bytes: executing,
  }
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.ProviderError)
  }).unwrap()
  let open = ledger => {
    start_composed(
      occurrence,
      call_identity_plan(prepared),
      prefix,
      [],
      provider,
      limits,
      root=Some((None, ledger)),
    ).unwrap()
  }
  let constructed = Ref(0)
  for short_retention in [true, false] {
    let ledger = @resources.create_ledger({
      ..ledger_limits,
      retained_bytes: if short_retention {
        retained - 1L
      } else {
        retained
      },
      execution_bytes: if short_retention {
        executing
      } else {
        executing - 1L
      },
    }).unwrap()
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
    if short_retention {
      assert_true(binding is Err(Resources(RetentionLimit)))
    } else {
      assert_true(binding is Err(Resources(ExecutionLimit)))
    }
    assert_eq(constructed.val, 0)
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
  let ledger = @resources.create_ledger(ledger_limits).unwrap()
  let active = open(ledger)
  assert_true(
    local_component(active, _ => @connector.ComputeUnsupported)
    is Err(InvalidAdvance),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, retained)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, executing)
  assert_true(!cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, retained)
  assert_true(cancel(active))
  assert_true(advance_root(active, 1).unwrap() is Stopped(_))
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(cleanup(active).unwrap())
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(calls.val, 0)

  // A failed input constructor cannot leave an unowned capacity reservation.
  // The constructor observes the live reservation before it rejects.
  let failed_ledger = @resources.create_ledger(ledger_limits).unwrap()
  let observed_reservation = Ref((0L, 0L))
  let rejected = start_occurrence(
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
      let usage = @resources.ledger_usage(failed_ledger)
      observed_reservation.val = (
        usage.reserved_retention_bytes,
        usage.reserved_execution_bytes,
      )
      Err(@input.UnsupportedProgram)
    },
    root=Some((prefix, None, failed_ledger)),
  )
  assert_true(rejected is Err(Input(UnsupportedProgram)))
  assert_eq(constructed.val, 1)
  assert_eq(observed_reservation.val, (retained, executing))
  assert_eq(@resources.ledger_usage(failed_ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(failed_ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(failed_ledger).attempts, 1)
}
