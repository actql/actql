///|
// Actual original Model/Read/publication token. Provider responses and byte
// grants are component inputs, not SDK/Store/normal installation evidence.
fn usage_projection_provider(tokens : Int64) -> @model.ModelProvider {
  @model.install_model_provider("models/fixture", _ => {
    Ok({
      value: @admitted.object_value([
        ("reason", @admitted.null_value()),
        ("risk", @admitted.text_value("high", 100).unwrap()),
      ]).unwrap(),
      provider_model: "fixture",
      provider_request_id: "request",
      input_tokens: tokens,
      output_tokens: tokens,
      observed_at: "2026-10-02T00:00:00.000Z",
    })
  }).unwrap()
}

///|
test "original usage projection keeps actual tokens provenance and absent raw distinct from zero" {
  for tokens in [0L, 7L] {
    let (active, ledger, _) = original_observation_test_start(
      provider=usage_projection_provider(tokens),
    )
    assert_true(fixture_finish(active) is Complete(_, ..))
    let capture = acquire_capture(active).unwrap()
    let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
    let quantities = @resources.quantity_usage(ledger)
    let before = @resources.ledger_usage(ledger)
    let (wire, retained, execution) = project_original_infer_capture_usage(
      active, capacity, capture, 0, 1L, 1L, 4096,
    ).unwrap()
    assert_true(wire.contains("\"input_tokens\":" + tokens.to_string()))
    assert_true(wire.contains("\"output_tokens\":" + tokens.to_string()))
    assert_true(wire.contains("\"raw_response_artifact_cid\":null"))
    assert_true(wire.contains("\"observation_origin\":\"historical_admitted\""))
    assert_true(
      wire.contains(
        @publication.run_evidence_value_identity(
          @model.verified_model_capture_call_at(capture, 0).unwrap(),
        ),
      ),
    )
    assert_true(
      wire.contains(
        @publication.run_evidence_value_identity(
          @model.model_execution_invocation_evidence(active.model.unwrap(), 0).unwrap(),
        ),
      ),
    )
    for
      forbidden in [
        "structured_response", "provider_metadata", "rendered_input", "context_manifest",
      ] {
      assert_false(wire.contains(forbidden))
    }
    assert_true(
      @model.original_model_publication_capacity_covers(
        capacity, retained, execution,
      ),
    )
    let after = @resources.ledger_usage(ledger)
    assert_eq(after.live_reservations, before.live_reservations)
    assert_eq(after.attempts, before.attempts)
    assert_eq(after.transferred_bytes, before.transferred_bytes)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_true(@model.release_verified_model_capture(capture))
    assert_true(release_original_infer_publication_capacity(capacity).unwrap())
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "usage projection refuses foreign captures slots and retired publication without growth" {
  let (active, ledger, _) = original_observation_test_start()
  let (foreign, _, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let other = acquire_capture(foreign).unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    project_original_infer_capture_usage(
      active, capacity, other, 0, 1L, 1L, 4096,
    )
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    project_original_infer_capture_usage(
      active, capacity, capture, 1, 1L, 1L, 4096,
    )
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  let retired = @resources.ledger_usage(ledger)
  assert_true(
    project_original_infer_capture_usage(
      active, capacity, capture, 0, 1L, 1L, 4096,
    )
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), retired)
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(@model.release_verified_model_capture(other))
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(foreign).unwrap())
}

///|
test "usage output exact budget succeeds while one byte short retains original cleanup" {
  let mut exact = 0
  for trial in [0, 1, 2] {
    let (active, ledger, _) = original_observation_test_start()
    assert_true(fixture_finish(active) is Complete(_, ..))
    let capture = acquire_capture(active).unwrap()
    let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = project_original_infer_capture_usage(
      active,
      capacity,
      capture,
      0,
      1L,
      1L,
      if trial == 0 {
        4096
      } else if trial == 1 {
        exact
      } else {
        exact - 1
      },
    )
    if trial == 0 {
      exact = result.unwrap().0.length()
    } else if trial == 1 {
      assert_eq(result.unwrap().0.length(), exact)
    } else {
      assert_true(result is Err(Model(@model.OutputIdentity)))
    }
    // No new token, send/attempt quantity or release is inferred from refusal.
    assert_eq(
      @resources.ledger_usage(ledger).live_reservations,
      before.live_reservations,
    )
    assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
    assert_true(
      @model.original_model_publication_capacity_covers(capacity, 1L, 1L),
    )
    assert_false(cleanup(active).unwrap())
    assert_true(@model.release_verified_model_capture(capture))
    assert_true(release_original_infer_publication_capacity(capacity).unwrap())
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "usage growth exact and one short stays on the same original Ledger and preserves partial responsibility" {
  let mut needed_retained = 0L
  let mut needed_execution = 0L
  for trial in [0, 1, 2, 3] {
    let (active, ledger, _) = original_observation_test_start(
      spare_publication_slot=true,
    )
    assert_true(fixture_finish(active) is Complete(_, ..))
    let capture = acquire_capture(active).unwrap()
    let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
    let quantities = @resources.quantity_usage(ledger)
    let limits = @resources.ledger_limits(ledger)
    let filler = if trial == 0 {
      None
    } else {
      let before = @resources.ledger_usage(ledger)
      Some(
        @resources.reserve_capacity(
          ledger,
          limits.retained_bytes -
          before.held_bytes -
          before.reserved_retention_bytes -
          (needed_retained - 9L) -
          (if trial == 2 { -1L } else { 0L }),
          limits.execution_bytes -
          before.reserved_execution_bytes -
          (needed_execution - 9L) -
          (if trial == 3 { -1L } else { 0L }),
        ).unwrap(),
      )
    }
    let before = @resources.ledger_usage(ledger)
    let result = project_original_infer_capture_usage(
      active, capacity, capture, 0, 1L, 1L, 4096,
    )
    if trial == 0 {
      let (_, retained, execution) = result.unwrap()
      needed_retained = retained
      needed_execution = execution
    } else if trial == 1 {
      assert_true(result is Ok(_))
    } else if trial == 2 {
      assert_true(
        result is Err(Model(@model.Ledger(@resources.RetentionLimit))),
      )
    } else {
      assert_true(
        result is Err(Model(@model.Ledger(@resources.ExecutionLimit))),
      )
    }
    assert_eq(@resources.ledger_limits(ledger), limits)
    assert_eq(@resources.quantity_usage(ledger), quantities)
    assert_eq(
      @resources.ledger_usage(ledger).live_reservations,
      before.live_reservations,
    )
    assert_false(cleanup(active).unwrap())
    assert_true(@model.release_verified_model_capture(capture))
    assert_true(release_original_infer_publication_capacity(capacity).unwrap())
    if filler is Some(reservation) {
      @resources.settle_capacity(ledger, reservation).unwrap()
    }
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "usage control preparation refuses an actually stopped original Read before growing" {
  let (active, ledger, consumer) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  @publication_host.stop_client_model_read_consumer(consumer).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    prepare_original_infer_capture_usage(active, capacity, capture, 1L, 1L)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}
