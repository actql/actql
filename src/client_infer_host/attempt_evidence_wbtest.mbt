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
fn evidence_allow_admission(
  active : Execution,
) -> @publication_host.ClientInferDispatchAdmission {
  let (compiled, definition) = invocation_fixture_compiled(active)
  let configuration = evidence_account(@authorization.Allow)
  @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-02T00:00:00.000Z")),
  ).unwrap()
}

///|
fn evidence_authorize(active : Execution) -> Unit {
  bind_dispatch_admission(active, evidence_allow_admission(active)).unwrap()
}

///|
test "deferred call inventory waits without dispatch and retains input until stop" {
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    defer_dispatch=true,
    enter_call=Some(_ => true),
  )
  invocation_fixture_compiled(active) |> ignore
  let mut waiting = false
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    if poll is Waiting(_) {
      waiting = true
      break
    }
    assert_true(poll is Continue(_))
  }
  assert_true(waiting)
  assert_eq(calls.val, 0)
  let set = prepared_model_call_set(active).unwrap()
  assert_eq(@model.prepared_model_call_set_count(set), Some(1))
  assert_eq(
    @model.prepared_model_call_set_binding(set),
    Some(
      (
        "models/fixture",
        @environment.model_task_identity(
          @environment.model_execution_task(
            @publication_host.client_infer_plan_graph_execution_contract(
              active.plan.unwrap(),
            ),
          ),
        ).2,
        @publication_host.client_infer_plan_graph_request_cid(
          active.plan.unwrap(),
        ),
      ),
    ),
  )
  assert_true(@model.prepared_model_call_set_input(set) is Some(_))
  let receipt = @model.prepared_model_call_set_input_receipt(set).unwrap()
  let completed = @input.client_infer_completed_input(active.input).unwrap()
  assert_true(
    @relation.completed_relation_export_matches_output(receipt, completed),
  )
  assert_true(@model.prepared_model_call_set_slot(set, 0) is Some(_))
  assert_true(acquire_output(active) is None)
  assert_true(!@input.cleanup_client_infer_input(active.input).unwrap())
  assert_true(cancel(active))
  let mut stopped = false
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    if poll is Stopped(_) {
      stopped = true
      break
    }
    assert_true(poll is Continue(_))
  }
  assert_true(stopped)
  assert_true(prepared_model_call_set(active) is None)
  assert_true(@model.prepared_model_call_set_binding(set) is None)
  assert_true(@model.prepared_model_call_set_input_receipt(set) is None)
  assert_true(
    @relation.completed_relation_export_matches_output(receipt, completed),
  )
  assert_true(cleanup(active).unwrap())
  assert_true(
    !@relation.completed_relation_export_matches_output(receipt, completed),
  )
  assert_eq(calls.val, 0)
}

///|
test "ordinary allow resumes complete Model input without reviewer approval" {
  let calls = Ref(0)
  let entries = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    defer_dispatch=true,
    enter_call=Some(_ => {
      entries.val += 1
      true
    }),
  )
  let (compiled, definition) = invocation_fixture_compiled(active)
  let mut waiting = false
  let mut waiting_work = 0L
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    if poll is Waiting(work~) {
      waiting = true
      waiting_work = work
      break
    }
    assert_true(poll is Continue(_))
  }
  assert_true(waiting)
  assert_eq(calls.val, 0)
  assert_eq(entries.val, 0)
  let configuration = evidence_account(@authorization.Allow)
  let changed = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => {
      Ok((evidence_account(@authorization.Deny), "2026-10-02T00:00:00.000Z"))
    },
  ).unwrap()
  assert_true(
    resume_immediate_model_call_set(active, changed, () => true)
    is Err(Model(@model.ApprovalUnavailable)),
  )
  assert_eq(calls.val, 0)
  let allow = @publication_host.issue_client_infer_dispatch_admission(
    compiled,
    definition,
    configuration,
    "fixture-principal",
    "2026-10-02T00:00:00.000Z",
    observe_current=() => Ok((configuration, "2026-10-02T00:00:00.000Z")),
  ).unwrap()
  resume_immediate_model_call_set(active, allow, () => true).unwrap()
  assert_true(
    fixture_finish(active, initial_work=waiting_work) is Complete(_, ..),
  )
  assert_eq(calls.val, 1)
  assert_eq(entries.val, 1)
  assert_true(cleanup(active).unwrap())
}

///|
test "durable entry refusal prevents physical Model invocation" {
  let calls = Ref(0)
  let entries = Ref(0)
  let slot = Ref(-1)
  let distinct = Ref(false)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    enter_call=Some(entry => {
      entries.val += 1
      slot.val = @model.model_call_entry_slot(entry)
      distinct.val = @publication.run_evidence_value_identity(
          @model.model_call_entry_attempt(entry),
        ) !=
        @publication.run_evidence_value_identity(
          @model.model_call_entry_call(entry),
        )
      false
    }),
  )
  evidence_authorize(active)
  assert_true(
    fixture_finish(active) is Failed(Model(@model.EntryUnavailable), ..),
  )
  assert_eq(entries.val, 1)
  assert_eq(slot.val, 0)
  assert_true(distinct.val)
  assert_eq(calls.val, 0)
  assert_true(acquire_output(active) is None)
  let model = active.model.unwrap()
  assert_eq(@model.stopped_model_attempt_count(model), Some(1))
  let uncertain = @model.model_execution_attempt_evidence(model, 0).unwrap()
  assert_true(
    @publication.run_evidence_value_json(
      @model.model_attempt_outcome(uncertain),
    ).contains("result_unknown"),
  )
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}

///|
test "durable entry observes reserved usage before recording an attempt" {
  let calls = Ref(0)
  let entries = Ref(0)
  let reference : Ref[Execution?] = Ref(None)
  let transfer_at_entry = Ref(-1L)
  let tokens_at_entry = Ref(-1L)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    enter_call=Some(_ => {
      entries.val += 1
      let model = reference.val.unwrap().model.unwrap()
      transfer_at_entry.val = @model.model_execution_resource_usage(model).uncertain_transfer_bytes
      tokens_at_entry.val = @model.model_execution_quantity_usage(model).uncertain.tokens
      false
    }),
  )
  reference.val = Some(active)
  bind_quantity_capacity(active, fixture_quantity_capacity(33L, 500L)).unwrap()
  evidence_authorize(active)
  assert_true(
    fixture_finish(active) is Failed(Model(@model.EntryUnavailable), ..),
  )
  assert_eq(entries.val, 1)
  assert_eq(transfer_at_entry.val, 66536L)
  assert_eq(tokens_at_entry.val, 33L)
  assert_eq(calls.val, 0)
  assert_true(cleanup(active).unwrap())
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
    assert_eq(stopped_attempt_count(active), Some(0))
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
  assert_eq(stopped_attempt_count(active), None)
  assert_true(fixture_finish(active) is Stopped(_))
  assert_eq(stopped_attempt_count(active), Some(1))
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
  assert_eq(stopped_attempt_count(active), None)
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
  for altered in ["none", "outcome", "policy"] {
    let outcome = if altered == "outcome" {
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
    let selected = if altered == "policy" {
      let policy = @environment.model_task_data_handling_cid(
        @environment.model_execution_task(
          @publication_host.client_infer_plan_graph_execution_contract(
            original.plan.unwrap(),
          ),
        ),
      )
      let unsigned = @publication.run_evidence_value_json(slot)
        .replace(
          old="\"policy_cid\":\"" + policy + "\"",
          new="\"policy_cid\":\"sha256:" + "b".repeat(64) + "\"",
        )
        .replace(
          old=",\"self_cid\":\"" +
            @publication.run_evidence_value_identity(slot) +
            "\"",
          new="",
        )
      @publication.seal_run_evidence_value(
        "model_slot_capture", unsigned, 16384, 1024, 20,
      ).unwrap()
    } else {
      slot
    }
    let selected_observation = if altered == "policy" {
      let unsigned = @publication.run_evidence_value_json(observation)
        .replace(
          old=@publication.run_evidence_value_identity(slot),
          new=@publication.run_evidence_value_identity(selected),
        )
        .replace(
          old=",\"observation_set_cid\":\"" +
            @publication.run_evidence_value_identity(observation) +
            "\"",
          new="",
        )
      @publication.seal_run_evidence_value(
        "observation_set", unsigned, 16384, 1024, 20,
      ).unwrap()
    } else {
      observation
    }
    let read = @model.read_verified_model_slot_replay(
      selected_observation,
      [selected],
      bundle,
      [{ ..records, outcome, }],
      @publication_host.client_compiled_run_admission(compiled),
      definition,
      1,
      16384,
    ).unwrap()
    let replay = restored_slots_start(read)
    let (replay_compiled, replay_definition) = invocation_fixture_compiled(
      replay,
    )
    assert_true(@model.release_model_slot_replay(read))
    let terminal = fixture_finish(replay)
    if altered != "none" {
      guard terminal
        is Failed(
          Model(
            @model.InvocationEvidence(
              @publication.RunEvidenceReferenceMismatch(field)
            )
          ),
          ..
        ) else {
        abort("substituted evidence did not fail with its exact cause")
      }
      assert_eq(
        field,
        if altered == "policy" {
          "model_slot_capture.policy_cid"
        } else {
          "model_attempt_evidence"
        },
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
      let ledger = issuance_ledger(65664L)
      let issued = start_observation_issuance(
        replay,
        ledger,
        issuance_limits(work=3),
      ).unwrap()
      issuance_finish(issued)
      let (issued_observation, _) = observation_issuance_value(issued).unwrap()
      assert_eq(
        @publication.model_observation_slot_at(issued_observation, 0),
        Some(@publication.run_evidence_value_identity(slot)),
      )
      let binding = bind_issued_invocation(
        replay, replay_compiled, replay_definition, issued,
      ).unwrap()
      assert_true(!cleanup_observation_issuance(issued).unwrap())
      assert_true(release_invocation_binding(binding))
      assert_true(cleanup_observation_issuance(issued).unwrap())
    }
    assert_true(cleanup(replay).unwrap())
    assert_eq(calls.val, 1)
  }
  assert_true(@publication.release_model_capture_bundle_read(bundle))
}
