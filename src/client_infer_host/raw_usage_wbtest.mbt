///|
// Ordinary Program, original Entry/call and Common codec. Physical bytes,
// installation and Store ACK are doubles, not public Store acceptance.
fn unknown_saved_raw_fixture(
  body : String,
  limits? : Limits = standard_limits(),
) -> (RawSaveFixture, @model.ModelPhysicalChatResponse) raise {
  let fixture = raw_save_fixture(limits~)
  let bytes = @utf8.encode(body)
  let save = @model.observe_model_raw_capture(
    fixture.call,
    fixture.registration,
    "sha256:" + @sha.hex(bytes),
    bytes.length(),
    200,
    true,
    "2026-10-02T00:00:00.000Z",
  ).unwrap()
  let receipt = @model.acknowledge_saved_model_raw_capture(save).unwrap()
  let raw = @model.model_saved_raw_chat_response(receipt, body, None).unwrap()
  fixture.ready.val = true
  assert_true(
    fixture_finish(fixture.active, initial_work=fixture.work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(
    @model.model_execution_attempt_evidence(fixture.active.model.unwrap(), 0)
    is Err(@model.OutputIdentity),
  )
  (fixture, raw)
}

///|
fn finish_raw_usage_fixture(
  fixture : RawSaveFixture,
  raw : @model.ModelPhysicalChatResponse,
  quantum : Int,
) -> Int64 raise {
  let mut previous = 0L
  for _ in 0..<8192 {
    let (done, work) = @model.advance_model_reconciled_raw_usage(
      fixture.call,
      raw,
      quantum,
    ).unwrap()
    assert_true(work >= previous && work - previous <= quantum.to_int64())
    previous = work
    if done {
      return work
    }
  }
  abort("independent finite original raw accounting read ceiling")
}

///|
test "reconciled raw usage preserves Unknown and settles actual quantities once at small quanta" {
  let body =
    #|{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2},"opaque":{"original":"é\r\n"}}
  let mut expected_work : Int64? = None
  for quantum in [1, 7] {
    let (fixture, raw) = unknown_saved_raw_fixture(body)
    let work = finish_raw_usage_fixture(fixture, raw, quantum)
    match expected_work {
      None => expected_work = Some(work)
      Some(expected) => assert_eq(work, expected)
    }
    let model = fixture.active.model.unwrap()
    assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
    assert_eq(
      @model.advance_model_reconciled_raw_usage(fixture.call, raw, 1),
      Ok((true, work)),
    )
    assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
    let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
    let accounting = @publication.run_evidence_value_json(
      @model.model_attempt_accounting(proof),
    )
    let outcome = @publication.run_evidence_value_json(
      @model.model_attempt_outcome(proof),
    )
    assert_true(accounting.contains("\"input_tokens\":3"))
    assert_true(accounting.contains("\"output_tokens\":2"))
    assert_true(outcome.contains("\"category\":\"result_unknown\""))
    assert_true(fixture.active.phase is Terminal)
    assert_true(acquire_output(fixture.active) is None)
    assert_true(acquire_capture(fixture.active) is None)
    assert_true(!cleanup(fixture.active).unwrap())
    assert_true(cleanup(fixture.active).unwrap())
    assert_eq(
      @publication.run_evidence_value_json(
        @model.model_attempt_accounting(proof),
      ),
      accounting,
    )
    assert_true(
      @model.advance_model_reconciled_raw_usage(fixture.call, raw, 1)
      is Err(@model.RequestIdentity),
    )
    assert_eq(fixture.calls.val, 1)
  }
}

///|
test "reconciled raw partial usage stays nullable after shape refusal and foreign raw is refused" {
  let body =
    #|{"usage":{"prompt_tokens":3},"choices":[],"opaque":"original"}
  let (fixture, raw) = unknown_saved_raw_fixture(body)
  let (foreign, foreign_raw) = unknown_saved_raw_fixture(body)
  assert_true(
    @model.advance_model_reconciled_raw_usage(fixture.call, foreign_raw, 1)
    is Err(@model.RequestIdentity),
  )
  let work = finish_raw_usage_fixture(fixture, raw, 1)
  assert_true(work > 0L)
  let model = fixture.active.model.unwrap()
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 0L)
  let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(proof),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":null"))
  finish_raw_usage_fixture(foreign, foreign_raw, 7) |> ignore
  for value in [fixture, foreign] {
    assert_true(!cleanup(value.active).unwrap())
    assert_true(cleanup(value.active).unwrap())
    assert_eq(value.calls.val, 1)
  }
}

///|
test "reconciled raw cancellation retains scanned quantities without freezing unread accounting" {
  let body =
    #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[],"opaque":"original"}
  let (fixture, raw) = unknown_saved_raw_fixture(body)
  let model = fixture.active.model.unwrap()
  let mut seen = false
  for _ in 0..<8192 {
    let (done, _) = @model.advance_model_reconciled_raw_usage(
      fixture.call,
      raw,
      1,
    ).unwrap()
    if @model.model_execution_quantity_usage(model).consumed.tokens == 5L {
      assert_false(done)
      seen = true
      break
    }
  }
  assert_true(seen)
  assert_true(
    @model.model_execution_attempt_evidence(model, 0)
    is Err(@model.OutputIdentity),
  )
  // The Run is already failed Unknown. Stop only the original Model cleanup
  // observation, not a fictitious successful cancel of that terminal Run.
  @model.request_model_cancel(model) |> ignore
  assert_true(
    @model.advance_model_reconciled_raw_usage(fixture.call, raw, 1)
    is Err(@model.Cancelled),
  )
  assert_true(
    @model.advance_model_reconciled_raw_usage(fixture.call, raw, 7)
    is Err(@model.Cancelled),
  )
  let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(proof),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  assert_true(!cleanup(fixture.active).unwrap())
  assert_true(cleanup(fixture.active).unwrap())
  assert_eq(fixture.calls.val, 1)
}

///|
test "reconciled raw one-short original work keeps known usage without restarting the child" {
  let body =
    #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[],"opaque":"original"}
  let (reference, reference_raw) = unknown_saved_raw_fixture(body)
  // Host account() retains the terminal Model work from Failed, whereas the
  // ModelExecution.work field retains the preceding Continue observation.
  let model_work = reference.active.child_work
  let child_work = finish_raw_usage_fixture(reference, reference_raw, 1)
  // A differential work boundary, not a physical capacity coefficient or a
  // replacement expected row. The same original Model budget must include its
  // already-consumed prefix; one less cannot complete the exact same child.
  let exact = (model_work + child_work).to_int()
  let original = standard_limits()
  for limit in [exact - 1, exact] {
    let (fixture, raw) = unknown_saved_raw_fixture(body, limits={
      ..original,
      model: { ..original.model, max_work: limit, },
    })
    let model = fixture.active.model.unwrap()
    let mut outcome : Result[(Bool, Int64), @model.ModelExecutionIssue] = Ok(
      (false, 0L),
    )
    for _ in 0..<8192 {
      outcome = @model.advance_model_reconciled_raw_usage(fixture.call, raw, 1)
      match outcome {
        Ok((false, _)) => ()
        _ => break
      }
    }
    if limit == exact {
      assert_eq(outcome, Ok((true, child_work)))
    } else {
      assert_true(outcome is Err(@model.WorkLimit))
      assert_true(
        @model.advance_model_reconciled_raw_usage(fixture.call, raw, 7)
        is Err(@model.WorkLimit),
      )
    }
    assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
    let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
    let wire = @publication.run_evidence_value_json(
      @model.model_attempt_accounting(proof),
    )
    assert_true(wire.contains("\"input_tokens\":3"))
    assert_true(wire.contains("\"output_tokens\":2"))
    assert_true(!cleanup(fixture.active).unwrap())
    assert_true(cleanup(fixture.active).unwrap())
    assert_eq(fixture.calls.val, 1)
  }
  assert_true(!cleanup(reference.active).unwrap())
  assert_true(cleanup(reference.active).unwrap())
}

///|
test "reconciled raw deadline keeps scanned usage and expired child cannot replenish fuel" {
  let body =
    #|{"usage":{"prompt_tokens":3,"completion_tokens":2},"choices":[],"opaque":"original"}
  let (fixture, raw) = unknown_saved_raw_fixture(body)
  let model = fixture.active.model.unwrap()
  for _ in 0..<8192 {
    let (done, _) = @model.advance_model_reconciled_raw_usage(
      fixture.call,
      raw,
      1,
    ).unwrap()
    if @model.model_execution_quantity_usage(model).consumed.tokens == 5L {
      assert_false(done)
      break
    }
  }
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  fixture.now.val = "2026-10-02T01:00:00.000Z"
  assert_true(
    @model.advance_model_reconciled_raw_usage(fixture.call, raw, 1)
    is Err(@model.Deadline),
  )
  fixture.now.val = "2026-10-02T00:00:00.000Z"
  assert_true(
    @model.advance_model_reconciled_raw_usage(fixture.call, raw, 7)
    is Err(@model.Deadline),
  )
  let proof = @model.model_execution_attempt_evidence(model, 0).unwrap()
  let wire = @publication.run_evidence_value_json(
    @model.model_attempt_accounting(proof),
  )
  assert_true(wire.contains("\"input_tokens\":3"))
  assert_true(wire.contains("\"output_tokens\":2"))
  assert_eq(@model.model_execution_quantity_usage(model).consumed.tokens, 5L)
  assert_true(!cleanup(fixture.active).unwrap())
  assert_true(cleanup(fixture.active).unwrap())
  assert_eq(fixture.calls.val, 1)
}
