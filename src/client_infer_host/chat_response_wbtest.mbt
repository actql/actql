///|
// Actual original Entry and nominal receipt, with doubled physical bytes/Store
// ACK. These are not real persistence or installed public profile acceptance.
fn install_saved_chat_response_fixture(
  fixture : RawSaveFixture,
  body : String,
  status? : Int = 200,
) -> Unit {
  let bytes = @utf8.encode(body)
  let save = @model.observe_model_raw_capture(
    fixture.call,
    fixture.registration,
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
    status,
    true,
    "2026-10-02T00:00:00.000Z",
  ).unwrap()
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  fixture.response.val = @model.PhysicalChatResponse(
    @model.model_saved_raw_chat_response(receipt, body, None).unwrap(),
  )
  fixture.ready.val = true
}

///|
test "raw Chat shape refusal retains independently observed usage and cleanup responsibility" {
  for
    body in [
      (
        #|{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2},"opaque":{"original":"é\r\n"}}
      ),
      (
        #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[{"index":0,"message":{"role":"assistant","content":"null","refusal":"refused"},"finish_reason":"stop"}]}
      ),
    ] {
    let release = Ref(false)
    let cleaned : Array[Bool] = []
    let fixture = raw_save_fixture(cleanup_calls=cleaned, release~)
    install_saved_chat_response_fixture(fixture, body)
    let active = fixture.active
    let prefix = fixture.work
    let calls = fixture.calls
    guard encoded_finish(active, 1, prefix) is Settling(0, work=settled) else {
      abort("classified refusal must retain the original private settlement")
    }
    let original = active.model.unwrap()
    let proof = @model.model_execution_attempt_evidence(original, 0).unwrap()
    let wire = @publication.run_evidence_value_json(
      @model.model_attempt_accounting(proof),
    )
    assert_true(wire.contains("\"input_tokens\":3"))
    assert_true(wire.contains("\"output_tokens\":2"))
    assert_eq(
      @model.model_execution_quantity_usage(original).consumed.tokens,
      5L,
    )
    assert_eq(calls.val, 1)
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    assert_true(cancel(active))
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_true(fixture_finish(active, initial_work=settled) is AwaitIo(..))
    assert_eq(cleaned, [true])
    assert_true(
      @model.model_execution_resource_usage(original).reserved_retention_bytes >
      0L,
    )
    release.val = true
    assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 1)
  }
}

///|
test "raw Chat cancellation after usage scan does not erase or recharge actuals" {
  let body =
    #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[{"index":0,"message":{"role":"assistant","content":"{\"reason\":null,\"risk\":\"high\"}"},"finish_reason":"stop"}]}
  let cleaned : Array[Bool] = []
  let fixture = raw_save_fixture(cleanup_calls=cleaned)
  install_saved_chat_response_fixture(fixture, body)
  let active = fixture.active
  let prefix = fixture.work
  let calls = fixture.calls
  let original = active.model.unwrap()
  let mut current_work = prefix
  let mut seen = false
  for _ in 0..<8192 {
    guard advance(active, 1).unwrap() is Continue(work~) else {
      abort("usage must be observed before shape/typed answer completion")
    }
    current_work = work
    if @model.model_execution_quantity_usage(original).consumed.tokens == 5L {
      seen = true
      break
    }
  }
  assert_true(seen)
  assert_true(cancel(active))
  guard fixture_finish(active, initial_work=current_work)
    is Settling(0, work=settled) else {
    abort("obtained response must settle before cancellation completes")
  }
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
  let proof = @model.model_execution_attempt_evidence(original, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(proof),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_eq(@model.model_execution_quantity_usage(original).consumed.tokens, 5L)
  assert_true(acquire_output(active) is None)
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(@model.model_execution_quantity_usage(original).consumed.tokens, 5L)
  assert_eq(calls.val, 1)
}

///|
test "raw Chat child refuses a foreign receipt even for the same descriptor CID" {
  let body =
    #|{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}
  let original = raw_save_fixture()
  let foreign = raw_save_fixture()
  // Both preparations have the same semantic identities and independently
  // entered attempt, but different physical original-call custody.
  install_saved_chat_response_fixture(foreign, body)
  original.response.val = foreign.response.val
  original.ready.val = true
  assert_true(
    fixture_finish(original.active, initial_work=original.work)
    is Failed(Model(@model.OutputIdentity), ..),
  )
  assert_eq(original.calls.val, 1)
  assert_true(acquire_output(original.active) is None)
  assert_true(!cleanup(original.active).unwrap())
  assert_true(cleanup(original.active).unwrap())
  foreign.response.val = @model.PhysicalUnknown({
    input_tokens: None,
    output_tokens: None,
  })
  raw_save_fixture_cleanup(foreign)
}

///|
test "raw Chat success transfers its original saved observation before child retirement" {
  let body =
    #|{"id":"original-request","model":"original-model","usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[{"index":0,"message":{"role":"assistant","content":"{\"reason\":null,\"risk\":\"high\"}"},"finish_reason":"stop"}]}
  let fixture = raw_save_fixture()
  install_saved_chat_response_fixture(fixture, body)
  let active = fixture.active
  guard fixture_finish(active, initial_work=fixture.work)
    is Settling(0, work=settled) else {
    abort("valid saved first-slot answer must settle exactly once")
  }
  let wire = async_settlement_wire(active)
  assert_true(wire.contains("\"response_complete\":true"))
  assert_true(wire.contains("\"provider_request_id\":\"original-request\""))
  assert_true(
    wire.contains("\"provider_reported_model_id\":\"original-model\""),
  )
  assert_true(wire.contains("\"finish_reason\":\"stop\""))
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_true(cancel(active))
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  assert_true(fixture_finish(active, initial_work=settled) is Stopped(..))
  assert_true(!cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(fixture.calls.val, 1)
}

///|
test "saved Chat HTTP errors retain typed status and original optional usage" {
  let empty_usage = "gateway did not return JSON"
  for
    (status, body, failure, input_tokens, output_tokens) in [
      (
        429,
        (
          #|{"usage":{"prompt_tokens":0,"completion_tokens":2}}
        ),
        "rate_limit",
        "0",
        "2",
      ),
      (429, empty_usage, "rate_limit", "null", "null"),
      (
        401,
        (
          #|{"usage":{"completion_tokens":0}}
        ),
        "provider_error",
        "null",
        "0",
      ),
      (503, empty_usage, "provider_error", "null", "null"),
    ] {
    let fixture = raw_save_fixture()
    install_saved_chat_response_fixture(fixture, body, status~)
    let active = fixture.active
    guard fixture_finish(active, initial_work=fixture.work)
      is Settling(0, work~) else {
      abort("complete original HTTP refusal must await settlement")
    }
    let original = active.model.unwrap()
    let proof = @model.model_execution_attempt_evidence(original, 0).unwrap()
    let outcome = @publication.run_evidence_value_json(
      @model.model_attempt_outcome(proof),
    )
    let accounting = @publication.run_evidence_value_json(
      @model.model_attempt_accounting(proof),
    )
    assert_true(
      outcome.contains("\"failure\":\"" + failure + "\""),
      msg=outcome,
    )
    assert_false(outcome.contains("\"reported_response\""))
    assert_true(accounting.contains("\"input_tokens\":" + input_tokens))
    assert_true(accounting.contains("\"output_tokens\":" + output_tokens))
    assert_true(acquire_output(active) is None)
    assert_true(acquire_capture(active) is None)
    assert_true(cancel(active))
    assert_true(
      @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
    )
    assert_true(fixture_finish(active, initial_work=work) is Stopped(..))
    assert_true(!cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(fixture.calls.val, 1)
  }
}

///|
test "saved Chat HTTP parser depth exhaustion stays a local limit" {
  let f = raw_save_fixture()
  let depth = @environment.model_response_profile_limits(
      async_response_profile(),
    ).parse_depth +
    1
  let body = "{\"opaque\":" + "[".repeat(depth) + "0" + "]".repeat(depth) + "}"
  install_saved_chat_response_fixture(f, body, status=429)
  assert_true(
    fixture_finish(f.active, initial_work=f.work)
    is Failed(Model(@model.WorkLimit), ..),
  )
  assert_true(call_settlement(f.active) is None)
  assert_true(acquire_output(f.active) is None)
  assert_false(cleanup(f.active).unwrap())
  assert_true(cleanup(f.active).unwrap())
  assert_eq(f.calls.val, 1)
}

///|
test "strict Model terminal diagnostic requires the exact retained HTTP Attempt and Raw" {
  for
    (status, body, code) in [
      (401, "gateway rejected", "ACTQL_E_MODEL_PROVIDER_ERROR"),
      (429, "gateway rejected", "ACTQL_E_MODEL_RATE_LIMIT"),
      (503, "gateway rejected", "ACTQL_E_MODEL_PROVIDER_ERROR"),
      (
        200,
        (
          #|{"id":"first","model":"actual","usage":{"prompt_tokens":0},"choices":[{"index":0,"message":{"role":"assistant","content":"{\"risk\":17,\"reason\":null}"},"finish_reason":"stop"}]}
        ),
        "ACTQL_E_MODEL_SCHEMA_INVALID",
      ),
      (
        200,
        (
          #|{"id":"first","model":"actual","usage":{"prompt_tokens":0},"choices":[{"index":0,"message":{"role":"assistant","content":null,"refusal":false},"finish_reason":"stop"}]}
        ),
        "ACTQL_E_MODEL_SCHEMA_INVALID",
      ),
      (
        200,
        (
          #|{"id":"first","model":"actual","usage":{"prompt_tokens":0},"choices":[{"index":0,"message":{"role":"assistant","content":null,"refusal":{}},"finish_reason":"stop"}]}
        ),
        "ACTQL_E_MODEL_SCHEMA_INVALID",
      ),
      (
        200,
        (
          #|{"id":"first","model":"actual","usage":{"prompt_tokens":0},"choices":[{"index":0,"message":{"role":"assistant","content":null,"refusal":"refused"},"finish_reason":"stop"}]}
        ),
        "ACTQL_E_MODEL_REFUSAL",
      ),
      (
        200,
        (
          #|{"id":"first","model":"actual","usage":{"prompt_tokens":0},"choices":[{"index":0,"message":{"role":"assistant","content":"{"},"finish_reason":"stop"}]}
        ),
        "ACTQL_E_MODEL_SCHEMA_INVALID",
      ),
      (
        200,
        (
          #|{"id":"first","model":"actual","usage":{"prompt_tokens":0},"choices":[{"index":0,"message":{"role":"assistant","content":"{"},"finish_reason":"length"}]}
        ),
        "ACTQL_E_MODEL_TRUNCATED",
      ),
    ] {
    let f = raw_save_fixture(strict=true)
    install_saved_chat_response_fixture(f, body, status~)
    let active = f.active
    assert_true(call_settlement(active) is None)
    let selected = fixture_finish(active, initial_work=f.work)
    assert_true(
      selected is Settling(0, ..),
      msg=status.to_string() +
        " " +
        code +
        " requires settlement; observed " +
        poll_kind(selected),
    )
    guard selected is Settling(0, work~) else {
      abort("binding requires the same pending settlement")
    }
    let model = active.run_binding.unwrap()
    let definition = model.definition
    let proof = attempt_evidence(active, 0).unwrap()
    let attempt = @model.model_attempt_identity(proof)
    let authority = @model.model_attempt_authority(proof)
    let capture = issued_slot_capture(active, 0).unwrap()
    let slot = @publication.bind_model_slot_capture(f.slot_original, capture).unwrap()
    let accounting = @model.model_attempt_accounting(proof)
    let outcome = @model.model_attempt_outcome(proof)
    let outcome_wire = @publication.run_evidence_value_json(outcome)
    let accounting_wire = @publication.run_evidence_value_json(accounting)
    if status == 200 {
      assert_true(outcome_wire.contains("\"reported_response\""))
      assert_true(outcome_wire.contains("\"response_complete\":false"))
      assert_true(accounting_wire.contains("\"input_tokens\":0"))
    } else {
      assert_false(outcome_wire.contains("\"reported_response\""))
      assert_true(accounting_wire.contains("\"input_tokens\":null"))
    }
    assert_true(accounting_wire.contains("\"output_tokens\":null"))
    let evidence = @publication.bind_model_slot_attempt_evidence(
      slot,
      attempt,
      accounting,
      outcome,
      authority,
      @publication_host.client_compiled_run_admission(model.compiled),
      definition,
    ).unwrap()
    let attempt_cid = @publication.run_evidence_value_identity(attempt)
    let settlement = call_settlement(active).unwrap()
    let raw = @model.model_call_settlement_failure_raw(settlement).unwrap()
    let raw_cid = @publication.run_evidence_value_identity(
      @publication.model_raw_response_value(raw),
    )
    let failure = @publication.bind_model_http_failure(
      evidence,
      f.scope,
      0,
      attempt_cid,
      raw_cid,
      raw,
    ).unwrap()
    let foreign = "sha256:" + "f".repeat(64)
    assert_true(
      @publication.bind_model_http_failure(
        evidence,
        f.scope,
        1,
        attempt_cid,
        raw_cid,
        raw,
      )
      is Err(_),
    )
    assert_true(
      @publication.bind_model_http_failure(
        evidence,
        f.scope,
        0,
        foreign,
        raw_cid,
        raw,
      )
      is Err(_),
    )
    assert_true(
      @publication.bind_model_http_failure(
        evidence,
        f.scope,
        0,
        attempt_cid,
        foreign,
        raw,
      )
      is Err(_),
    )
    let bytes = @utf8.encode(body)
    let policy = @publication_host.client_model_raw_capture_policy(
      f.registration,
    )
    let prefix = @publication.issue_model_raw_response(
      policy,
      f.scope,
      0,
      attempt,
      authority,
      "sha256:" + @sha.hex(bytes),
      bytes.length(),
      status,
      false,
      "2026-10-02T00:00:00.000Z",
    ).unwrap()
    assert_true(
      @publication.bind_model_http_failure(
        evidence,
        f.scope,
        0,
        attempt_cid,
        @publication.run_evidence_value_identity(prefix),
        @publication.bind_model_raw_response(
          policy,
          prefix,
          f.scope,
          0,
          attempt,
          authority,
        ).unwrap(),
      )
      is Err(_),
    )

    assert_true(@model.model_call_settlement_retains_strict_failure(settlement))
    assert_true(@model.acknowledge_model_call_settlement(settlement))
    assert_false(
      @model.model_call_settlement_retains_strict_failure(settlement),
    )
    assert_false(
      @model.model_call_settlement_strict_failure_retired(settlement),
    )
    assert_true(@model.model_call_settlement_failure_raw(settlement) is None)
    assert_true(
      fixture_finish(active, initial_work=work)
      is Failed(Model(@model.Provider(_)), ..),
    )
    assert_true(@model.model_call_settlement_strict_failure_retired(settlement))
    assert_eq(f.calls.val, 1)
    assert_true(acquire_output(active) is None)
    let wire = @publication.issue_bound_model_http_failed_run_state_wire(
      definition,
      failure,
      "2026-10-02T00:00:00.000Z",
      ["answer"],
      65536,
      8192,
      64,
    ).unwrap()
    let run_id = @publication.run_definition_run_id(definition).unwrap()
    let wire = @publication.prepare_run_state_observation(
        wire, run_id, 0L, 65536, 8192, 64,
      )
      .unwrap()
      .wire(0L)
      .unwrap()
    assert_true(wire.contains("\"code\":\"" + code + "\""))
    assert_true(wire.contains("\"status\":\"failed\""))
    assert_true(wire.contains("\"result_available\":false"))
    assert_true(
      @publication.validate_original_unpublished_run_state(
        definition,
        wire,
        65536,
        8192,
        64,
        model_failure=Some((attempt_cid, failure)),
      )
      is Ok(@publication.Failed),
    )
    let stored = @publication_host.prepare_client_unpublished_run_state_original(
      definition,
      wire,
      model_failure=Some(failure),
    ).unwrap()
    let saved = stored.wire()
    assert_true(
      saved.contains("\"model_failure_attempt_cid\":\"" + attempt_cid + "\""),
    )
    assert_true(saved.contains("\"model_failure_raw_cid\":\"" + raw_cid + "\""))
    assert_eq(stored.state_wire(), wire)
    let observation = @publication.prepare_run_state_observation(
      wire, run_id, 0L, 65536, 8192, 64,
    ).unwrap()
    let metadata = @publication_host.admit_client_retained_run_state_original(
      definition,
      saved,
      0L,
      observation.key(),
    ).unwrap()
    assert_true(metadata.resolve() is Err(@publication_host.CustodyLost))
    assert_true(
      @publication_host.admit_client_retained_run_state_original(
        definition,
        saved,
        1L,
        observation.key(),
      )
      is Err(@publication_host.CustodyLost),
    )
    assert_true(
      @publication_host.admit_client_retained_run_state_original(
        definition, saved, 0L, "foreign-key",
      )
      is Err(@publication_host.CustodyLost),
    )
    assert_true(
      @publication_host.restore_client_run_state_original(definition, saved)
      is Err(@publication_host.CustodyLost),
    )
    // Readmit each exact leaf from its canonical wire. Historical binding
    // uses the selected definition, scope and Store, with no live Call view.
    let read_original = value => {
      @publication.admit_run_evidence_value(
        @publication.run_evidence_value_name(value),
        @publication.run_evidence_value_json(value),
        16384,
        256,
        8,
      ).unwrap()
    }
    let cold_slot = @publication.bind_model_slot_capture(
      read_original(f.slot_original),
      read_original(capture),
    ).unwrap()
    let raw_original = read_original(@publication.model_raw_response_value(raw))
    let scope_cid = @publication.model_invocation_scope_cid(f.scope)
    let store = "sha256:" + "e".repeat(64)
    let retained = (selected_scope, selected_store) => {
      @publication.bind_retained_model_http_failure(
        definition,
        selected_scope,
        selected_store,
        (attempt_cid, raw_cid),
        cold_slot,
        read_original(attempt),
        read_original(accounting),
        read_original(outcome),
        read_original(authority),
        raw_original,
      )
    }
    assert_true(retained(foreign, store) is Err(_))
    assert_true(retained(scope_cid, foreign) is Err(_))
    let cold_failure = retained(scope_cid, store).unwrap()
    let inspected = Ref(0)
    let resolve = (candidate_attempt, candidate_raw) => {
      inspected.val += 1
      if candidate_attempt == attempt_cid && candidate_raw == raw_cid {
        Some(cold_failure)
      } else {
        None
      }
    }
    let restored = @publication_host.restore_client_run_state_original(
      definition,
      saved,
      resolve_model_failure=Some(resolve),
    ).unwrap()
    assert_eq(inspected.val, 1)
    assert_eq(restored.wire(), saved)
    assert_eq(restored.state_wire(), wire)
    let metadata_proof = metadata
      .resolve(
        resolve_model_failure=Some((attempt, raw) => {
          if (attempt, raw) == (attempt_cid, raw_cid) {
            Some(cold_failure)
          } else {
            None
          }
        }),
      )
      .unwrap()
    assert_eq(metadata_proof.wire(), saved)
    assert_eq(metadata_proof.state_wire(), wire)
    for
      changed in [
        saved.replace(
          old="\"model_failure_raw_cid\":\"" + raw_cid + "\",",
          new="",
        ),
        " " + saved,
      ] {
      assert_true(
        @publication_host.restore_client_run_state_original(
          definition,
          changed,
          resolve_model_failure=Some(resolve),
        )
        is Err(@publication_host.CustodyLost),
      )
    }
    assert_eq(inspected.val, 1)
    for
      changed in [
        saved.replace(old=attempt_cid, new=foreign),
        saved.replace(old=raw_cid, new=foreign),
      ] {
      assert_true(
        @publication_host.restore_client_run_state_original(
          definition,
          changed,
          resolve_model_failure=Some((_, _) => Some(failure)),
        )
        is Err(@publication_host.CustodyLost),
      )
    }
    assert_true(
      @publication_host.validate_client_historical_run_state_original(
        definition, saved,
      )
      is Err(@publication_host.CustodyLost),
    )
    assert_true(
      @publication.validate_original_unpublished_run_state(
        definition, wire, 65536, 8192, 64,
      )
      is Err(_),
    )
    assert_true(
      @publication.validate_original_unpublished_run_state(
        definition,
        wire,
        65536,
        8192,
        64,
        model_failure=Some((foreign, failure)),
      )
      is Err(_),
    )
    let substitution = if code == "ACTQL_E_MODEL_PROVIDER_ERROR" {
      "ACTQL_E_MODEL_RATE_LIMIT"
    } else {
      "ACTQL_E_MODEL_PROVIDER_ERROR"
    }
    let changed = wire.replace(old=code, new=substitution)
    assert_true(changed != wire)
    assert_true(
      @publication.validate_original_unpublished_run_state(
        definition,
        changed,
        65536,
        8192,
        64,
        model_failure=Some((attempt_cid, failure)),
      )
      is Err(_),
    )
    let (_, foreign_definition) = invocation_fixture_compiled(
      active,
      run_id="foreign-failure",
    )
    assert_true(
      @publication.issue_bound_model_http_failed_run_state_wire(
        foreign_definition,
        failure,
        "2026-10-02T00:00:00.000Z",
        ["answer"],
        65536,
        8192,
        64,
      )
      is Err(_),
    )
    assert_false(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
  }
}
