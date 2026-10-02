///|
fn evidence_account(
  outcome : @authorization.ConfiguredOutcome,
) -> @authorization.AdmittedAccountConfiguration {
  @authorization.admit_account_configuration({
    account_id: "infer-fixture",
    entries: [
      {
        entry_id: "model-policy",
        outcome,
        scope: {
          principal: @authorization.All,
          connection: @authorization.All,
          resource: @authorization.All,
          operation: @authorization.AnyOf(["infer"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
}

///|
fn evidence_authorize(active : Execution) -> Unit {
  let (compiled, definition) = invocation_fixture_compiled(active)
  let configuration = evidence_account(@authorization.Allow)
  let permit = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-02T00:00:00.000Z")),
  ).unwrap()
  bind_dispatch_admission(active, permit).unwrap()
}

///|
test "common model owner issues mixed slot attempt accounting and authority proofs" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    rows="[{\"id\":\"a\",\"text\":\"first\"},{\"id\":\"b\",\"text\":\"second\"}]",
    mixed=true,
  )
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 2)
  let model = active.model.unwrap()
  let read = acquire_capture(active).unwrap()
  let failed = @model.model_execution_issued_slot_capture(model, 0).unwrap()
  let success = @model.model_execution_issued_slot_capture(model, 1).unwrap()
  assert_true(@model.bind_verified_model_slot_capture(read, 0, failed) is Ok(_))
  assert_true(
    @model.bind_verified_model_slot_capture(read, 1, success) is Ok(_),
  )
  assert_true(
    @model.bind_verified_model_slot_capture(read, 0, success) is Err(_),
  )
  let first = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let second = @model.model_execution_attempt_evidence(model, 1).unwrap()
  let a = @model.model_attempt_accounting(first)
  let b = @model.model_attempt_accounting(second)
  let wire_a = @publication.run_evidence_value_json(a)
  let wire_b = @publication.run_evidence_value_json(b)
  assert_true(wire_a.contains("\"input_tokens\":null"))
  assert_true(wire_a.contains("\"output_tokens\":null"))
  assert_true(wire_a.contains("\"uncertain_wire_bytes\":66536"))
  assert_true(wire_b.contains("\"input_tokens\":1"))
  assert_true(wire_b.contains("\"output_tokens\":2"))
  assert_true(wire_b.contains("\"cost_units\":null"))
  assert_true(wire_b.contains("\"duration_ms\":null"))
  for changed in 0..<3 {
    assert_true(
      @model.verify_model_execution_attempt_evidence(
        model,
        0,
        if changed == 0 {
          @model.model_attempt_identity(second)
        } else {
          @model.model_attempt_identity(first)
        },
        if changed == 1 {
          b
        } else {
          a
        },
        if changed == 2 {
          @model.model_attempt_outcome(second)
        } else {
          @model.model_attempt_outcome(first)
        },
        @model.model_attempt_authority(first),
      )
      is Err(@model.OutputIdentity),
    )
  }
  assert_true(
    @model.verify_model_execution_attempt_evidence(
      model,
      0,
      @model.model_attempt_identity(first),
      a,
      @model.model_attempt_outcome(first),
      @model.model_attempt_authority(first),
    )
    is Ok(_),
  )
  assert_true(@model.release_verified_model_capture(read))
  assert_true(cleanup(active).unwrap())
  assert_eq(
    @publication.run_evidence_value_identity(
      @model.model_attempt_accounting(
        @model.model_execution_attempt_evidence(model, 0).unwrap(),
      ),
    ),
    @publication.run_evidence_value_identity(a),
  )
  assert_eq(calls.val, 2)
}

///|
test "model dispatch evidence cannot override deny or adopt late execution" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  let (compiled, definition) = invocation_fixture_compiled(active)
  assert_true(
    @publication_host.issue_client_infer_dispatch_admission(
      compiled,
      definition,
      evidence_account(@authorization.Deny),
      "fixture-principal",
      "2026-10-02T00:00:00.000Z",
      observe_current=() => {
        Ok((evidence_account(@authorization.Deny), "2026-10-02T00:00:00.000Z"))
      },
    )
    is Err(@publication_host.Authorization(@authorization.Denied)),
  )
  assert_eq(calls.val, 0)
  let permit = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    evidence_account(@authorization.Allow),
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => {
      Ok((evidence_account(@authorization.Allow), "2026-10-02T00:00:00.000Z"))
    },
  ).unwrap()
  assert_true(advance(active, 1).unwrap() is Continue(_))
  assert_true(
    bind_dispatch_admission(active, permit) is Err(IncompleteExecution),
  )
  assert_true(cancel(active))
  assert_true(fixture_finish(active) is Stopped(_))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}

///|
test "model dispatch rechecks current account and lifetime after prefix progress" {
  for expired in [false, true] {
    let calls = Ref(0)
    let active = failed_outcome_start(@model.Timeout, calls)
    let (compiled, definition) = invocation_fixture_compiled(active)
    let configuration = evidence_account(@authorization.Allow)
    let current = Ref(configuration)
    let at = Ref("2026-10-02T00:00:00.000Z")
    let permit = @publication_host.issue_client_infer_dispatch_admission(
      compiled,
      definition,
      configuration,
      "fixture-principal",
      at.val,
      observe_current=() => Ok((current.val, at.val)),
    ).unwrap()
    bind_dispatch_admission(active, permit).unwrap()
    let prefix_work = match advance(active, 1).unwrap() {
      Continue(work~) => work
      _ => abort("expected bounded prefix progress")
    }
    if expired {
      at.val = "2100-01-01T00:00:00.000Z"
    } else {
      current.val = evidence_account(@authorization.Deny)
    }
    let terminal = fixture_finish(active, initial_work=prefix_work)
    if expired {
      assert_true(
        terminal
        is Failed(Model(@model.Authorization(@publication_host.Expired)), ..),
      )
    } else {
      assert_true(
        terminal
        is Failed(
          Model(
            @model.Authorization(
              @publication_host.Authorization(@authorization.ForeignDecision)
            )
          ),
          ..
        ),
      )
    }
    assert_eq(calls.val, 0)
    assert_true(acquire_capture(active) is None)
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 0)
  }
}

///|
test "cancelled dispatched attempt retains proof without adopting a slot" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    cancel_after_failure=true,
  )
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Stopped(_))
  assert_eq(calls.val, 1)
  let model = active.model.unwrap()
  let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
  assert_true(
    @publication.run_evidence_value_json(@model.model_attempt_outcome(proof)).contains(
      "\"category\":\"cancelled\"",
    ),
  )
  assert_true(
    @publication.run_evidence_value_json(@model.model_attempt_accounting(proof)).contains(
      "\"uncertain_wire_bytes\":66536",
    ),
  )
  assert_true(@model.model_execution_issued_slot_capture(model, 0) is Err(_))
  assert_true(acquire_capture(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_true(@model.model_execution_attempt_evidence(model, 0) is Ok(_))
  assert_eq(calls.val, 1)
}

///|
test "attempt evidence storage is reserved before physical dispatch" {
  // One request/response envelope plus five bounded evidence documents.
  let exact = 66536L + 5L * 16384L
  for retained in [exact, exact - 1L] {
    let calls = Ref(0)
    let base = standard_limits()
    let limits = {
      ..base,
      model: {
        ..base.model,
        ledger: { ..base.model.ledger, retained_bytes: retained, },
      },
    }
    let active = failed_outcome_start(@model.Timeout, calls, limits~)
    evidence_authorize(active)
    let terminal = fixture_finish(active)
    if retained == exact {
      assert_true(terminal is Complete(_, ..))
      assert_eq(calls.val, 1)
    } else {
      assert_true(
        terminal is Failed(Model(@model.Ledger(@resources.RetentionLimit)), ..),
      )
      assert_eq(calls.val, 0)
    }
    let model = active.model.unwrap()
    assert_true(cleanup(active).unwrap())
    assert_eq(
      @model.model_execution_resource_usage(model).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "cleanup cannot issue previously unencoded attempt evidence" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let model = active.model.unwrap()
  assert_true(cleanup(active).unwrap())
  assert_true(
    @model.model_execution_attempt_evidence(model, 0)
    is Err(@model.OutputIdentity),
  )
  assert_true(@model.model_execution_issued_slot_capture(model, 0) is Err(_))
  assert_eq(calls.val, 1)
}

///|
test "stored attempt leaves replay without a provider and reject proof substitution" {
  let calls = Ref(0)
  let original = failed_outcome_start(@model.Timeout, calls)
  let (compiled, definition) = invocation_fixture_compiled(original)
  let authorization = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    evidence_account(@authorization.Allow),
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => {
      Ok((evidence_account(@authorization.Allow), "2026-10-02T00:00:00.000Z"))
    },
  ).unwrap()
  bind_dispatch_admission(original, authorization).unwrap()
  assert_true(fixture_finish(original) is Complete(_, ..))
  let model = original.model.unwrap()
  let slot = @model.model_execution_issued_slot_capture(model, 0).unwrap()
  let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let round_trip = (value : @publication.RunEvidenceValue) => {
    @publication.admit_run_evidence_value(
      @publication.run_evidence_value_name(value),
      @publication.run_evidence_value_json(value),
      16384,
      1024,
      20,
    ).unwrap()
  }
  let slot = round_trip(slot)
  let records : @model.ModelAttemptRecords = {
    attempt: round_trip(@model.model_attempt_identity(proof)),
    accounting: round_trip(@model.model_attempt_accounting(proof)),
    outcome: round_trip(@model.model_attempt_outcome(proof)),
    authority: round_trip(@model.model_attempt_authority(proof)),
  }
  let observation = invocation_fixture_observation(original, compiled, [slot])
  // No successful response exists, hence the success-only bundle is empty.
  let bundle_body = @publication.seal_run_evidence_value(
    "model_capture_bundle", "{\"version\":\"actql-model-capture-bundle/0.1\",\"captures\":[],\"barrier_receipts\":[]}",
    16384, 1024, 20,
  ).unwrap()
  let bundle = @publication.read_model_capture_bundle(
    @publication.run_evidence_value_json(bundle_body),
    @publication.run_evidence_value_identity(bundle_body),
    16384,
    1024,
    20,
  ).unwrap()
  assert_true(cleanup(original).unwrap())
  for altered in [false, true] {
    let outcome = if altered {
      let unsigned = @publication.run_evidence_value_json(records.outcome)
        .replace(
          old="\"failure\":\"timeout\"",
          new="\"failure\":\"provider_error\"",
        )
        .replace(
          old=",\"self_cid\":\"" +
            @publication.run_evidence_value_identity(records.outcome) +
            "\"",
          new="",
        )
      @publication.seal_run_evidence_value(
        "model_attempt_outcome", unsigned, 16384, 1024, 20,
      ).unwrap()
    } else {
      records.outcome
    }
    let read = @model.read_verified_model_slot_replay(
      observation,
      [slot],
      bundle,
      [{ ..records, outcome, }],
      @publication_host.client_compiled_run_admission(compiled),
      definition,
      1,
      16384,
    ).unwrap()
    let replay = restored_slots_start(read)
    assert_true(@model.release_model_slot_replay(read))
    let terminal = fixture_finish(replay)
    if altered {
      assert_true(
        terminal
        is Failed(
          Model(
            @model.InvocationEvidence(
              @publication.RunEvidenceReferenceMismatch(
                "model_attempt_evidence"
              )
            )
          ),
          ..
        ),
      )
      assert_true(acquire_output(replay) is None)
    } else {
      guard terminal is Complete(result, ..) else {
        abort("verified saved replay failed")
      }
      assert_true(
        @relation.completed_cell(result, 0, 1)
        is Some(@relation.Text("failed:timeout")),
      )
      assert_true(
        @relation.completed_cell(result, 0, 2) is Some(@relation.Null),
      )
    }
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 1)
  }
  assert_true(@publication.release_model_capture_bundle_read(bundle))
}
