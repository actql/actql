///|
fn failed_outcome_start(
  failure : @model.ModelProviderFailure,
  calls : Ref[Int],
  strict? : Bool = false,
  rows? : String = "[{\"id\":\"a\",\"text\":\"hello\"}]",
  mixed? : Bool = false,
  success_first? : Bool = false,
  cancel_after_failure? : Bool = false,
  limits? : Limits = standard_limits(),
  defer_dispatch? : Bool = false,
  enter_call? : ((@model.ModelCallEntry) -> Bool)? = None,
) -> Execution {
  let source = infer_fixture_program.replace(
    old="[{\"id\":\"a\",\"text\":\"hello\"}]",
    new=rows,
  )
  let source = if strict {
    source.replace(
      old="\"key\":\"id\",",
      new="\"key\":\"id\",\"on_non_success\":\"fail\",",
    )
  } else {
    source
  }
  let prepared = fixture_prepared(source~)
  let plan = call_identity_plan(prepared)
  let reference : Ref[Execution?] = Ref(None)
  let provider = @model.install_model_provider("models/fixture", request => {
    calls.val += 1
    if mixed && request.slot == (if success_first { 0 } else { 1 }) {
      Ok({
        value: @admitted.object_value([
          ("reason", @admitted.null_value()),
          ("risk", @admitted.text_value("high", 100).unwrap()),
        ]).unwrap(),
        provider_model: "fixture-risk-model",
        provider_request_id: "response-b",
        input_tokens: 1L,
        output_tokens: 2L,
        observed_at: "2026-10-01T00:00:00.000Z",
      })
    } else {
      if cancel_after_failure {
        cancel(reference.val.unwrap()) |> ignore
      }
      Err(failure)
    }
  }).unwrap()
  let active = start(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    @publication_host.client_infer_plan_graph_request_cid(plan),
    limits,
    plan=Some(plan),
    defer_dispatch~,
    enter_call~,
  ).unwrap()
  reference.val = Some(active)
  active
}

///|
test "all classified no-response failures emit keyed NULL-valued outcomes" {
  for
    (failure, expected) in [
      (@model.RateLimit, "failed:rate_limit"),
      (@model.Timeout, "failed:timeout"),
      (@model.ProviderError, "failed:provider_error"),
      (@model.Refusal, "failed:refusal"),
      (@model.SchemaInvalid, "failed:schema_invalid"),
      (@model.SafetyRejected, "failed:safety_rejected"),
      (@model.Truncated, "failed:truncated"),
    ] {
    let calls = Ref(0)
    let active = failed_outcome_start(failure, calls)
    assert_true(acquire_outcomes(active) is None)
    guard fixture_finish(active) is Complete(completed, ..) else {
      abort("a classified outcome must not fail the barrier")
    }
    assert_eq(@relation.completed_row_count(completed), 1)
    assert_true(
      @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
    )
    guard @relation.completed_cell(completed, 0, 1)
      is Some(@relation.Text(actual)) else {
      abort("missing outcome")
    }
    assert_eq(actual, expected)
    assert_true(
      @relation.completed_cell(completed, 0, 2) is Some(@relation.Null),
    )
    let saved = acquire_capture(active).unwrap()
    assert_eq(@model.verified_model_capture_call_count(saved), Some(1))
    assert_eq(@model.verified_model_capture_outcome(saved, 0), Some(expected))
    assert_true(@model.verified_model_capture_call_at(saved, 0) is Some(_))
    assert_true(invocation_evidence(active, 0) is None)
    // A failure is a slot observation, not a fabricated success record.
    assert_eq(capture(active).unwrap().captures.length(), 0)
    let model = active.model.unwrap()
    assert_eq(
      @model.model_execution_resource_usage(model).uncertain_transfer_bytes,
      66536L,
    )
    assert_true(!cleanup(active).unwrap())
    assert_true(@model.release_verified_model_capture(saved))
    assert_true(cleanup(active).unwrap())
    let after = @model.model_execution_resource_usage(model)
    assert_eq(after.uncertain_transfer_bytes, 66536L)
    assert_eq(after.reserved_transfer_bytes, 0L)
    assert_eq(after.reserved_retention_bytes, 0L)
    assert_eq(calls.val, 1)
  }
}

///|
test "mixed outcome replay preserves all keys without another model call" {
  let rows = "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
  let calls = Ref(0)
  let original = failed_outcome_start(@model.Timeout, calls, rows~, mixed=true)
  guard fixture_finish(original) is Complete(completed, ..) else {
    abort("mixed outcomes failed")
  }
  assert_eq(@relation.completed_row_count(completed), 2)
  assert_true(
    @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(completed, 0, 1)
    is Some(@relation.Text("failed:timeout")),
  )
  assert_true(@relation.completed_cell(completed, 0, 2) is Some(@relation.Null))
  assert_true(
    @relation.completed_cell(completed, 1, 0) is Some(@relation.Text("b")),
  )
  assert_true(
    @relation.completed_cell(completed, 1, 1) is Some(@relation.Text("ok")),
  )
  assert_eq(calls.val, 2)
  assert_true(invocation_evidence(original, 0) is None)
  let evidence = invocation_evidence(original, 1).unwrap()
  let saved = acquire_capture(original).unwrap()
  assert_eq(@model.verified_model_capture_call_count(saved), Some(2))
  assert_eq(
    @model.verified_model_capture_outcome(saved, 0),
    Some("failed:timeout"),
  )
  assert_eq(@model.verified_model_capture_outcome(saved, 1), Some("ok"))
  let source = infer_fixture_program.replace(
    old="[{\"id\":\"a\",\"text\":\"hello\"}]",
    new=rows,
  )
  let prepared = fixture_prepared(source~)
  let replay = start_replay(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    saved,
    standard_limits(),
    call_identity_plan(prepared),
  ).unwrap()
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(!cleanup(original).unwrap())
  guard fixture_finish(replay) is Complete(replayed, ..) else {
    abort("mixed replay failed")
  }
  assert_true(
    @relation.completed_cell(replayed, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(replayed, 0, 1)
    is Some(@relation.Text("failed:timeout")),
  )
  assert_true(@relation.completed_cell(replayed, 0, 2) is Some(@relation.Null))
  assert_true(
    @relation.completed_cell(replayed, 1, 0) is Some(@relation.Text("b")),
  )
  assert_true(
    @relation.completed_cell(replayed, 1, 1) is Some(@relation.Text("ok")),
  )
  assert_true(invocation_evidence(replay, 0) is None)
  assert_eq(
    @publication.run_evidence_value_json(
      invocation_evidence(replay, 1).unwrap(),
    ),
    @publication.run_evidence_value_json(evidence),
  )
  let usage = @model.model_execution_resource_usage(replay.model.unwrap())
  assert_eq(usage.attempts, 0)
  assert_eq(usage.uncertain_transfer_bytes, 0L)
  assert_eq(calls.val, 2)
  assert_true(cleanup(replay).unwrap())
  assert_true(cleanup(original).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "failure slot binding rejects a substituted classification or fake response" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let saved = acquire_capture(active).unwrap()
  let call = @model.verified_model_capture_call_at(saved, 0).unwrap()
  guard @json.parse(@publication.run_evidence_value_json(call))
    is Object(fields) else {
    abort("invalid call fixture")
  }
  // Symbolic external roots test exact references only, not authority or
  // adoption evidence. They cannot authorize a public Invocation.
  let root = Json::string("sha256:" + "a".repeat(64))
  for mutation in 0..<3 {
    let body = Json::object({
      "version": Json::string("actql-model-slot-capture/0.1"),
      "slot_cid": fields["model_call_slot_cid"],
      "model_task_cid": fields["model_task_cid"],
      "fixed_request_cid": fields["fixed_request_cid"],
      "input_artifact_cid": fields["input_artifact_cid"],
      "input_key_cid": fields["input_key_cid"],
      "ordered_attempt_cids": Json::array([root]),
      "adopted_attempt_cid": root,
      "outcome": Json::string(
        if mutation == 1 {
          "failed:refusal"
        } else {
          "failed:timeout"
        },
      ),
      "typed_value_artifact_cid": Json::null(),
      "accounting_evidence_cid": root,
      "authority_evidence_cid": root,
      "policy_cid": root,
      "outcome_evidence_cid": root,
      "response_artifact_cid": if mutation == 2 {
        root
      } else {
        Json::null()
      },
      "response_issuer_evidence_cid": if mutation == 2 {
        root
      } else {
        Json::null()
      },
      "attachment_admission_cids": Json::array([]),
    })
    let result = @model.bind_verified_model_slot_capture(
      saved,
      0,
      slot_binding_seal(body),
    )
    if mutation == 0 {
      assert_true(result is Ok(_))
    } else {
      guard result
        is Err(
          @model.InvocationEvidence(
            @publication.RunEvidenceReferenceMismatch(cause)
          )
        ) else {
        abort("wrong failure capture rejection")
      }
      assert_eq(
        cause,
        if mutation == 1 {
          "model_slot_capture.outcome"
        } else {
          "model_slot_capture.response_artifact_cid"
        },
      )
    }
  }
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "two failed slots produce two rows rather than an empty success observation" {
  let rows = "[{\"id\":\"b\",\"text\":\"second\"},{\"id\":\"a\",\"text\":\"first\"}]"
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Refusal, calls, rows~)
  guard fixture_finish(active) is Complete(completed, ..) else {
    abort("failed outcomes rejected")
  }
  assert_eq(@relation.completed_row_count(completed), 2)
  for (row, key) in [(0, "a"), (1, "b")] {
    guard @relation.completed_cell(completed, row, 0)
      is Some(@relation.Text(actual)) else {
      abort("missing failure key")
    }
    assert_eq(actual, key)
    assert_true(
      @relation.completed_cell(completed, row, 1)
      is Some(@relation.Text("failed:refusal")),
    )
    assert_true(
      @relation.completed_cell(completed, row, 2) is Some(@relation.Null),
    )
  }
  let saved = acquire_capture(active).unwrap()
  assert_eq(@model.verified_model_capture_call_count(saved), Some(2))
  assert_eq(capture(active).unwrap().captures.length(), 0)
  assert_eq(calls.val, 2)
  assert_true(@model.release_verified_model_capture(saved))
  assert_true(cleanup(active).unwrap())
}

///|
test "strict failure retains a preceding successful observation privately" {
  let rows = "[{\"id\":\"a\",\"text\":\"first\"},{\"id\":\"b\",\"text\":\"second\"}]"
  let calls = Ref(0)
  let active = failed_outcome_start(
    @model.Timeout,
    calls,
    strict=true,
    rows~,
    mixed=true,
    success_first=true,
  )
  assert_true(
    fixture_finish(active) is Failed(Model(@model.Provider(@model.Timeout)), ..),
  )
  assert_eq(calls.val, 2)
  assert_true(acquire_output(active) is None)
  assert_true(acquire_capture(active) is None)
  let read = acquire_outcomes(active).unwrap()
  assert_eq(@model.model_outcomes_count(read), Some(2))
  assert_true(!@model.model_outcomes_accepted(read))
  assert_eq(@model.model_outcomes_outcome(read, 0), Some("ok"))
  assert_eq(@model.model_outcomes_outcome(read, 1), Some("failed:timeout"))
  assert_true(@model.model_outcomes_invocation_evidence(read, 0) is Some(_))
  assert_true(@model.model_outcomes_invocation_evidence(read, 1) is None)
  assert_true(!cleanup(active).unwrap())
  assert_true(@model.release_model_outcomes(read))
  assert_true(cleanup(active).unwrap())
  assert_true(@model.model_outcomes_outcome(read, 0) is None)
  assert_true(@model.model_outcomes_call_at(read, 0) is None)
  assert_eq(calls.val, 2)
}

///|
test "failed slot work and retention admit exact limits and reject one-short" {
  // One reservation, eight shared scoped-request transitions and one physical
  // attempt. The Host independently caps request + response at 1000 + 65536.
  for work in [10, 9] {
    let base = standard_limits()
    let limits = { ..base, model: { ..base.model, max_work: work, }, }
    let calls = Ref(0)
    let active = failed_outcome_start(@model.Timeout, calls, limits~)
    let terminal = fixture_finish(active)
    if work == 10 {
      assert_true(terminal is Complete(_, ..))
      assert_eq(calls.val, 1)
    } else {
      assert_true(terminal is Failed(Model(@model.WorkLimit), ..))
      assert_eq(calls.val, 0)
      assert_true(acquire_output(active) is None)
    }
    assert_true(cleanup(active).unwrap())
  }
  for bytes in [66536L, 66535L] {
    let base = standard_limits()
    let limits = {
      ..base,
      model: {
        ..base.model,
        ledger: { ..base.model.ledger, retained_bytes: bytes, },
      },
    }
    let calls = Ref(0)
    let active = failed_outcome_start(@model.Timeout, calls, limits~)
    let terminal = fixture_finish(active)
    if bytes == 66536L {
      assert_true(terminal is Complete(_, ..))
      assert_eq(calls.val, 1)
    } else {
      assert_true(
        terminal is Failed(Model(@model.Ledger(@resources.RetentionLimit)), ..),
      )
      assert_eq(calls.val, 0)
      assert_true(acquire_capture(active) is None)
    }
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "strict failure and cancellation never accept outcome output" {
  let rows = "[{\"id\":\"a\",\"text\":\"first\"},{\"id\":\"b\",\"text\":\"second\"}]"
  let calls = Ref(0)
  let strict = failed_outcome_start(@model.Timeout, calls, strict=true, rows~)
  assert_true(
    fixture_finish(strict) is Failed(Model(@model.Provider(@model.Timeout)), ..),
  )
  assert_eq(calls.val, 1)
  assert_true(acquire_output(strict) is None)
  assert_true(acquire_capture(strict) is None)
  let private_read = acquire_outcomes(strict).unwrap()
  assert_true(!@model.model_outcomes_accepted(private_read))
  assert_eq(@model.model_outcomes_count(private_read), Some(1))
  assert_eq(
    @model.model_outcomes_outcome(private_read, 0),
    Some("failed:timeout"),
  )
  assert_true(@model.model_outcomes_call_at(private_read, 0) is Some(_))
  assert_true(@model.model_outcomes_call_at(private_read, 1) is None)
  assert_true(
    @model.model_outcomes_invocation_evidence(private_read, 0) is None,
  )
  let retained = @model.retain_model_outcomes(private_read).unwrap()
  assert_true(!cleanup(strict).unwrap())
  assert_true(@model.release_model_outcomes(private_read))
  assert_true(!@model.release_model_outcomes(private_read))
  assert_true(@model.model_outcomes_count(private_read) is None)
  assert_true(!cleanup(strict).unwrap())
  assert_eq(@model.model_outcomes_count(retained), Some(1))
  assert_true(@model.release_model_outcomes(retained))
  assert_true(cleanup(strict).unwrap())
  assert_eq(calls.val, 1)
  for callback_cancel in [false, true] {
    let calls = Ref(0)
    let active = failed_outcome_start(
      if callback_cancel {
        @model.Timeout
      } else {
        @model.Cancelled
      },
      calls,
      cancel_after_failure=callback_cancel,
    )
    assert_true(fixture_finish(active) is Stopped(_))
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    let read = acquire_outcomes(active).unwrap()
    assert_eq(@model.model_outcomes_count(read), Some(0))
    assert_true(!@model.model_outcomes_accepted(read))
    assert_true(@model.model_outcomes_call_at(read, 0) is None)
    assert_true(@model.release_model_outcomes(read))
    let model = active.model.unwrap()
    assert_eq(
      @model.model_execution_resource_usage(model).uncertain_transfer_bytes,
      66536L,
    )
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 1)
    assert_eq(
      @model.model_execution_resource_usage(model).uncertain_transfer_bytes,
      66536L,
    )
  }
}
