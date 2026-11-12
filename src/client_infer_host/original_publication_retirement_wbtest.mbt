///|
// Real Core Model/Scope, saved-input availability and Resource reservations.
// The fixture's current port is not physical IO or an installed cleanup ACK.
test "original publication reservation returns after stopped Model dependency retirement" {
  let current = Ref(true)
  let calls = Ref(0)
  let (active, ledger, _) = original_observation_test_start(
    provider=original_funded_start_provider(calls),
    restored_input=true,
    restored_custody=() => current.val,
  )
  // Preserve the restored constructor's real durable-call entry/settlement
  // protocol. This uses the existing checked fixture gate, not a disabled one.
  let (same, prepared, admission, prefix_work) = entry_gate_fixture(
    calls,
    Ref(evidence_account(@authorization.Allow)),
    Ref("2026-10-12T00:00:00.000Z"),
    Ref(Some(egress_fixture_observation())),
    start_original=Some(() => active),
    slots=1,
  )
  assert_true(physical_equal(same, active))
  bind_model_entry_persistence(active, prepared, admission, entry => {
    @model.model_call_entry_persistence(entry, prepared, () => {
      @model.Saved(
        @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
      )
    })
  }).unwrap()
  let mut poll = fixture_finish(active, initial_work=prefix_work)
  for _ in 0..<4 {
    if poll is AwaitIo(work~) {
      poll = fixture_finish(active, initial_work=work)
    }
  }
  let work = match poll {
    Settling(_, work~) => work
    _ => abort("restored original must retain its actual settlement")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
  assert_true(execution_stopped(active))
  let model = active.model.unwrap()
  let scope = active.call_scope.unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 11L, 13L).unwrap()
  assert_true(
    @model.original_model_publication_capacity_current(capacity, model, scope),
  )
  let before = @resources.ledger_usage(ledger)
  // Retire only the same restored input's supplied availability. No new Model
  // call, regrant, copied Scope or fabricated cleanup receipt is introduced.
  current.val = false
  assert_false(
    @publication_host.client_infer_call_scope_matches_rows(
      scope,
      active.rows.unwrap(),
      active.fixed_request_cid,
    ),
  )
  assert_false(
    @model.original_model_publication_capacity_current(capacity, model, scope),
  )
  assert_true(
    @model.grow_original_model_publication_capacity(
      capacity, model, scope, 12L, 14L,
    )
    is Err(@model.OutputIdentity),
  )
  assert_true(
    @model.reserve_original_model_publication_capacity(model, scope, 1L, 1L)
    is Err(@model.OutputIdentity),
  )
  assert_false(cleanup(active).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  let released = @resources.ledger_usage(ledger)
  assert_eq(
    released.reserved_retention_bytes,
    before.reserved_retention_bytes - 11L,
  )
  assert_eq(
    released.reserved_execution_bytes,
    before.reserved_execution_bytes - 13L,
  )
  assert_eq(released.attempts, before.attempts)
  // The existing retired-handle success is idempotent; it cannot settle or
  // refund another reservation or restore current use on the retired input.
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_eq(@resources.ledger_usage(ledger), released)
  assert_false(
    @model.original_model_publication_capacity_current(capacity, model, scope),
  )
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "original publication reservation refuses foreign Model Scope without settling either Ledger" {
  let (active, ledger, _) = original_observation_test_start(run_id="original")
  let (foreign, other_ledger, _) = original_observation_test_start(
    run_id="foreign",
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capacity = reserve_original_infer_publication_capacity(active, 11L, 13L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let other_before = @resources.ledger_usage(other_ledger)
  assert_false(
    @model.original_model_publication_capacity_current(
      capacity,
      foreign.model.unwrap(),
      foreign.call_scope.unwrap(),
    ),
  )
  assert_true(
    @model.grow_original_model_publication_capacity(
      capacity,
      foreign.model.unwrap(),
      foreign.call_scope.unwrap(),
      12L,
      14L,
    )
    is Err(@model.OutputIdentity),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(other_ledger), other_before)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(foreign).unwrap())
}
