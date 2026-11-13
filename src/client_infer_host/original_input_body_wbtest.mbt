///|
// Actual checked input/Read/Model with the existing fixture provider and
// synthetic explicit byte grants. This is not installed physical admission.
test "original first input scan retains its body through Model and the same accepted observation" {
  let calls = Ref(0)
  let (active, ledger, consumer) = original_observation_test_start(
    provider=original_funded_start_provider(calls),
    input_body=true,
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
  let scan = active.identity.unwrap()
  let receipt = @relation.completed_relation_identity_scan_body_receipt(scan).unwrap()
  let expected = "{\"sort\":\"relation\",\"value\":[{\"id\":\"a\",\"text\":\"hello\"}]}"
  assert_eq(
    @relation.completed_relation_identity_scan_body(scan, receipt),
    Some(expected),
  )
  assert_true(active.identity_body.unwrap().retained > 7L)
  let held = acquire_output(active).unwrap()
  let bound = active.run_binding.unwrap()
  let (_, outcomes) = borrow_original_live_model_relations(
    held,
    bound.compiled,
    bound.definition,
    active.plan.unwrap(),
  ).unwrap()
  let outcome_receipt = local_model_observation_test_export(outcomes)
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  issuance_finish(issued)
  let observation = issue_original_local_model_observation_from_scope(
    held, issued, outcome_receipt, 10000, 1000, 20,
  ).unwrap()
  let work = @relation.completed_relation_identity_scan_work(scan)
  let bodies = original_local_model_observation_input_bodies(observation).unwrap()
  assert_eq(bodies[0], ("relation_value", expected))
  assert_eq(
    bodies[1],
    (
      "relation_schema",
      @relation.relation_schema_wire(
        @relation.completed_relation_export_schema_identity(receipt),
      ),
    ),
  )
  let dependencies = original_local_model_observation_input_dependency_bodies(
    observation,
  ).unwrap()
  assert_eq(
    dependencies[0],
    (
      "relation_value",
      @relation.logical_relation_cid(
        @relation.completed_relation_export_identity(receipt),
      ),
      expected,
    ),
  )
  assert_eq(
    dependencies[1],
    (
      "relation_schema",
      @relation.relation_schema_cid(
        @relation.completed_relation_export_schema_identity(receipt),
      ),
      bodies[1].1,
    ),
  )
  // The real inventory consumer requires the original CID for hashed bodies.
  // Its strict original admission must accept each exact body/CID pair.
  for (kind, cid, wire) in dependencies {
    let admitted = @publication.admit_captured_effect_dependency_body(
      kind,
      Some(cid),
      wire,
      10000,
      1000,
      20,
    ).unwrap()
    assert_eq(@publication.captured_effect_dependency_body_cid(admitted), cid)
    assert_true(
      @publication.admit_captured_effect_dependency_body(
        kind,
        None,
        wire,
        10000,
        1000,
        20,
      )
      is Err(@publication.InvalidBody),
    )
  }
  assert_eq(@relation.completed_relation_identity_scan_work(scan), work)
  assert_eq(calls.val, 1)
  assert_true(release_output(held))
  assert_true(
    original_local_model_observation_input_bodies(observation) is None,
  )
  assert_true(
    original_local_model_observation_input_dependency_bodies(observation)
    is None,
  )
  @relation.cancel_completed_relation_export_receipt(outcome_receipt)
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(
    @relation.completed_relation_identity_scan_body(scan, receipt) is None,
  )
  original_composed_test_release(ledger, consumer)
}

///|
test "original first input scan capacity refusal preserves its read and never calls Model" {
  let calls = Ref(0)
  let (active, ledger, consumer) = original_observation_test_start(
    provider=original_funded_start_provider(calls),
    input_body=true,
    input_read_ceiling=Some(10L),
  )
  assert_true(
    fixture_finish(active)
    is Failed(
      OriginalCapacity(
        @publication_host.Read(
          @publication_host.Resource(
            @resources.Resource(@resources.RetentionLimit)
          )
        )
      ),
      ..
    ),
  )
  assert_eq(calls.val, 0)
  assert_true(active.identity is None)
  assert_true(active.original_preparation is Some(_))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(cleanup(active).unwrap())
  original_composed_test_release(ledger, consumer)
}

///|
test "original restored input body refuses capacity and cancellation before scanning or Model" {
  for stop in [false, true] {
    let calls = Ref(0)
    let (active, ledger, consumer) = original_observation_test_start(
      provider=original_funded_start_provider(calls),
      input_body=true,
      restored_input=true,
      input_read_ceiling=if stop { None } else { Some(10L) },
    )
    assert_true(active.identity_body is Some(_))
    assert_true(active.identity is None)
    if stop {
      assert_true(cancel(active))
      assert_true(fixture_finish(active) is Stopped(..))
    } else {
      assert_true(
        fixture_finish(active)
        is Failed(
          OriginalCapacity(
            @publication_host.Read(
              @publication_host.Resource(
                @resources.Resource(@resources.RetentionLimit)
              )
            )
          ),
          ..
        ),
      )
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
    }
    assert_eq(calls.val, 0)
    assert_true(active.identity is None)
    assert_true(active.original_preparation is Some(_))
    assert_true(cleanup(active).unwrap())
    original_composed_test_release(ledger, consumer)
  }
}

///|
test "original restored input body rejects a foreign checked Read before scan construction" {
  let prepared = fixture_prepared()
  let (occurrence, prefix) = original_composed_test_input(prepared)
  let plan = call_identity_plan(prepared)
  let limits = standard_limits()
  let calls = Ref(0)
  let (compiled, definition, ledger, read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let consumer = @publication_host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  let (foreign_compiled, foreign_definition, foreign_ledger, foreign_read) = original_funded_start_read(
    prepared, plan, limits,
  )
  let foreign_consumer = @publication_host.claim_client_model_read_preparation(
    foreign_read, foreign_compiled, foreign_definition, plan, 7L, 5L,
  ).unwrap()
  let (saved, exported) = original_restored_composed_test_saved(
    prepared,
    compiled,
    definition,
    occurrence,
    plan,
    () => true,
  )
  let foreign_before = @resources.ledger_usage(foreign_ledger)
  let active = start_original_restored_composed(
    occurrence,
    plan,
    prefix,
    original_funded_start_provider(calls),
    @input.client_infer_retained_input_export_binding(exported),
    @input.client_infer_retained_input_export_descriptor(exported),
    @input.client_infer_retained_input_export_rows(exported),
    () => true,
    saved,
    limits,
    compiled,
    definition,
    consumer,
    7L,
    5L,
    100L,
    5L,
    input_body_read=Some(foreign_read),
  ).unwrap()
  assert_true(
    fixture_finish(active)
    is Failed(
      OriginalCapacity(@publication_host.Read(@publication_host.ForeignRun)),
      ..
    ),
  )
  assert_eq(calls.val, 0)
  assert_true(active.identity is None)
  assert_eq(@resources.ledger_usage(foreign_ledger), foreign_before)
  assert_true(cleanup(active).unwrap())
  original_composed_test_release(ledger, consumer)
  original_composed_test_release(foreign_ledger, foreign_consumer)
}
