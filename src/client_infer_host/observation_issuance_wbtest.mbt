///|
fn issuance_ledger(bytes : Int64, work? : Int = 4) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: work,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: bytes,
    execution_bytes: 0L,
  }).unwrap()
}

///|
fn issuance_limits(work? : Int = 4) -> ObservationIssuanceLimits {
  { max_slots: 2, max_wire_bytes: 4096, max_work: work, }
}

///|
fn issuance_finish(issued : ObservationIssuance) -> Unit raise {
  for _ in 0..<(issued.state.count + 1) {
    assert_true(!advance_observation_issuance(issued, 1).unwrap().0)
    assert_true(observation_issuance_value(issued) is None)
  }
  assert_true(advance_observation_issuance(issued, 1).unwrap().0)
}

///|
test "common observation issuer includes every adopted slot and retains custody" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    rows="[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]",
    mixed=true,
  )
  evidence_authorize(active)
  let bound = active.run_binding.unwrap()
  assert_true(fixture_finish(active) is Complete(_, ..))
  // Declared wire workspace: 16 * 4096 + 2 * 128, not an observed peak.
  let ledger = issuance_ledger(65792L)
  let issued = start_observation_issuance(active, ledger, issuance_limits()).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 65792L)
  assert_true(!cleanup(active).unwrap())
  issuance_finish(issued)
  let (observation, invocation) = observation_issuance_value(issued).unwrap()
  assert_eq(@publication.model_observation_slot_count(observation), Some(2))
  for index in 0..<2 {
    assert_eq(
      @publication.model_observation_slot_at(observation, index),
      Some(
        @publication.run_evidence_value_identity(
          issued_slot_capture(active, index).unwrap(),
        ),
      ),
    )
  }
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      "\"consistency\":\"no_external_sources\"",
    ),
  )
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      "\"capture_started_at\":null",
    ),
  )
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
  assert_true(
    physical_equal(invocation_binding_invocation(first).unwrap(), invocation),
  )
  assert_eq(
    @relation.completed_row_count(invocation_binding_output(first).unwrap()),
    2,
  )
  assert_true(!cleanup_observation_issuance(issued).unwrap())
  assert_true(release_invocation_binding(first))
  assert_true(!release_invocation_binding(first))
  assert_true(!cleanup_observation_issuance(issued).unwrap())
  assert_true(invocation_binding_output(second) is Some(_))
  assert_true(release_invocation_binding(second))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(observation_issuance_value(issued) is None)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 4)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "observation issuer refuses unproven captures and substituted owners" {
  let calls = Ref(0)
  let structural = failed_outcome_start(@model.Timeout, calls)
  invocation_fixture_compiled(structural) |> ignore
  assert_true(fixture_finish(structural) is Complete(_, ..))
  let unused = issuance_ledger(65664L)
  assert_true(
    start_observation_issuance(structural, unused, issuance_limits())
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(unused).attempts, 0)
  assert_true(cleanup(structural).unwrap())
  let active = failed_outcome_start(@model.Timeout, calls)
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let issued = start_observation_issuance(
    active,
    issuance_ledger(65664L),
    issuance_limits(),
  ).unwrap()
  let bound = active.run_binding.unwrap()
  assert_true(
    bind_issued_invocation(active, bound.compiled, bound.definition, issued)
    is Err(UnverifiedSlots),
  )
  issuance_finish(issued)
  let foreign = failed_outcome_start(@model.Timeout, calls)
  let (compiled, definition) = invocation_fixture_compiled(foreign)
  assert_true(
    bind_issued_invocation(active, compiled, definition, issued)
    is Err(UnverifiedSlots),
  )
  assert_true(
    bind_issued_invocation(foreign, bound.compiled, bound.definition, issued)
    is Err(UnverifiedSlots),
  )
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_true(cancel(foreign))
  assert_true(fixture_finish(foreign) is Stopped(_))
  assert_true(cleanup(foreign).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "observation issuance has exact workspace work and incremental cancellation" {
  for mode in ["workspace", "work", "cancel"] {
    let calls = Ref(0)
    let active = failed_outcome_start(@model.Timeout, calls)
    evidence_authorize(active)
    assert_true(fixture_finish(active) is Complete(_, ..))
    let ledger = issuance_ledger(
      if mode == "workspace" {
        65663L
      } else {
        65664L
      },
    )
    let started = start_observation_issuance(
      active,
      ledger,
      issuance_limits(work=if mode == "work" { 2 } else { 3 }),
    )
    if mode == "workspace" {
      assert_true(
        started is Err(Model(@model.Ledger(@resources.RetentionLimit))),
      )
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    } else {
      let issued = started.unwrap()
      assert_true(!advance_observation_issuance(issued, 1).unwrap().0)
      assert_true(observation_issuance_value(issued) is None)
      if mode == "cancel" {
        assert_true(cancel_observation_issuance(issued))
        assert_true(!cleanup_observation_issuance(issued).unwrap())
        assert_true(
          advance_observation_issuance(issued, 1)
          is Err(Model(@model.Cancelled)),
        )
        assert_eq(@resources.ledger_usage(ledger).planning_work, 1)
      } else {
        assert_true(!advance_observation_issuance(issued, 1).unwrap().0)
        assert_true(
          advance_observation_issuance(issued, 1)
          is Err(Model(@model.WorkLimit)),
        )
        assert_eq(@resources.ledger_usage(ledger).planning_work, 2)
      }
      assert_true(observation_issuance_value(issued) is None)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        65664L,
      )
      assert_true(cleanup_observation_issuance(issued).unwrap())
      assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    }
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 1)
  }
}

///|
test "zero-key common issuance preserves an explicit empty inventory" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls, rows="[]")
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let ledger = issuance_ledger(65536L)
  let issued = start_observation_issuance(
    active,
    ledger,
    issuance_limits(work=2),
  ).unwrap()
  issuance_finish(issued)
  let (observation, _) = observation_issuance_value(issued).unwrap()
  assert_eq(@publication.model_observation_slot_count(observation), Some(0))
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      "\"model_slot_capture_cids\":[]",
    ),
  )
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}

///|
test "zero-key saved replay validates its original observation and actual input" {
  let calls = Ref(0)
  let original = failed_outcome_start(@model.Timeout, calls, rows="[]")
  evidence_authorize(original)
  let bound = original.run_binding.unwrap()
  assert_true(fixture_finish(original) is Complete(_, ..))
  let issued = start_observation_issuance(
    original,
    issuance_ledger(65536L),
    issuance_limits(work=2),
  ).unwrap()
  issuance_finish(issued)
  let (observation, _) = observation_issuance_value(issued).unwrap()
  let artifact = @publication_host.client_infer_call_scope_artifact(
    original.call_scope.unwrap(),
  )
  let bundle_value = @publication.seal_run_evidence_value(
    "model_capture_bundle", "{\"version\":\"actql-model-capture-bundle/0.1\",\"captures\":[],\"barrier_receipts\":[]}",
    16384, 1024, 20,
  ).unwrap()
  let bundle = @publication.read_model_capture_bundle(
    @publication.run_evidence_value_json(bundle_value),
    @publication.run_evidence_value_identity(bundle_value),
    16384,
    1024,
    20,
  ).unwrap()
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(cleanup(original).unwrap())
  for changed in ["none", "input", "template", "policy"] {
    let selected = if changed == "none" {
      observation
    } else {
      let (old, replacement) = match changed {
        "input" =>
          (
            @publication.run_evidence_value_identity(artifact),
            "sha256:" + "b".repeat(64),
          )
        "template" =>
          (
            @publication_host.client_compiled_run_template(bound.compiled)
            |> @publication.run_evidence_value_identity,
            "sha256:" + "b".repeat(64),
          )
        _ =>
          (
            "\"data_policy_cid\":\"sha256:" + "a".repeat(64) + "\"",
            "\"data_policy_cid\":\"sha256:" + "b".repeat(64) + "\"",
          )
      }
      let body = @publication.run_evidence_value_json(observation)
        .replace(old~, new=replacement)
        .replace(
          old=",\"observation_set_cid\":\"" +
            @publication.run_evidence_value_identity(observation) +
            "\"",
          new="",
        )
      @publication.seal_run_evidence_value(
        "observation_set", body, 16384, 1024, 20,
      ).unwrap()
    }
    let read = @model.read_verified_model_slot_replay(
      selected,
      [],
      bundle,
      [],
      @publication_host.client_compiled_run_admission(bound.compiled),
      bound.definition,
      0,
      16384,
    ).unwrap()
    let replay = restored_slots_start(read, rows="[]")
    let (compiled, definition) = invocation_fixture_compiled(replay)
    assert_true(@model.release_model_slot_replay(read))
    let terminal = fixture_finish(replay)
    if changed == "none" {
      assert_true(terminal is Complete(_, ..))
      let reconstructed = start_observation_issuance(
        replay,
        issuance_ledger(65536L),
        issuance_limits(work=2),
      ).unwrap()
      issuance_finish(reconstructed)
      let (actual, _) = observation_issuance_value(reconstructed).unwrap()
      assert_eq(
        @publication.run_evidence_value_identity(actual),
        @publication.run_evidence_value_identity(observation),
      )
      let binding = bind_issued_invocation(
        replay, compiled, definition, reconstructed,
      ).unwrap()
      assert_eq(
        @relation.completed_row_count(
          invocation_binding_output(binding).unwrap(),
        ),
        0,
      )
      assert_true(release_invocation_binding(binding))
      assert_true(cleanup_observation_issuance(reconstructed).unwrap())
    } else {
      guard terminal
        is Failed(
          Model(
            @model.InvocationEvidence(
              @publication.RunEvidenceReferenceMismatch(field)
            )
          ),
          ..
        ) else {
        abort("the empty inventory must not bypass scope verification")
      }
      assert_eq(
        field,
        match changed {
          "input" => "observation.captured_input_artifact_cids"
          "template" => "observation.invocation_template_cid"
          _ => "observation.data_policy_cid"
        },
      )
      assert_true(acquire_output(replay) is None)
    }
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 0)
  }
  assert_true(@publication.release_model_capture_bundle_read(bundle))
}
