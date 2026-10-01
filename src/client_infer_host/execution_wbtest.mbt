///|
fn fixture_prepared() -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    infer_fixture_environment,
    infer_fixture_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @publication_host.prepare_effect_free_client_program(
    infer_fixture_program,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn fixture_start(
  prepared : @publication_host.PreparedClientProgram,
  on_invoke : () -> Unit,
) -> Execution {
  let provider = @model.install_model_provider("models/fixture", _request => {
    on_invoke()
    let value = @admitted.object_value([
      ("reason", @admitted.null_value()),
      ("risk", @admitted.text_value("high", 100).unwrap()),
    ]).unwrap()
    Ok({
      value,
      provider_model: "fixture-risk-model",
      provider_request_id: "request-1",
      input_tokens: 1L,
      output_tokens: 2L,
      observed_at: "2026-10-01T00:00:00.000Z",
    })
  }).unwrap()
  start(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    "sha256:" + "1".repeat(64),
    standard_limits(),
  ).unwrap()
}

///|
fn fixture_finish(active : Execution) -> Poll raise {
  let mut last = 0L
  for _ in 0..<2000 {
    let poll = advance(active, 1).unwrap()
    let work = match poll {
      Continue(work~)
      | Complete(_, work~)
      | Failed(_, work~)
      | Stopped(work~) => work
    }
    assert_true(work >= last && work - last <= 1L)
    last = work
    if !(poll is Continue(_)) {
      return poll
    }
  }
  abort("bounded fixture exceeded its independent finite poll ceiling")
}

///|
test "normal Program input dispatch and output share one bounded owner" {
  let calls = Ref(0)
  let prepared = fixture_prepared()
  let active = fixture_start(prepared, () => calls.val += 1)
  assert_eq(calls.val, 0)
  assert_true(matches(active, prepared))
  assert_true(!matches(active, fixture_prepared()))
  assert_true(!cleanup(active).unwrap())
  let poll = fixture_finish(active)
  guard poll is Complete(completed, ..) else { abort("successful fixture") }
  assert_eq(calls.val, 1)
  assert_eq(@relation.completed_row_count(completed), 1)
  assert_eq(@relation.completed_column_count(completed), 3)
  assert_eq(@relation.completed_column_name(completed, 0), Some("id"))
  assert_eq(@relation.completed_column_name(completed, 1), Some("outcome"))
  assert_eq(@relation.completed_column_name(completed, 2), Some("value"))
  assert_true(
    @relation.completed_cell(completed, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(completed, 0, 1) is Some(@relation.Text("ok")),
  )
  let a = acquire_output(active).unwrap()
  let b = acquire_output(active).unwrap()
  assert_true(!cleanup(active).unwrap())
  assert_true(release_output(a))
  assert_true(!release_output(a))
  assert_true(output(a) is None)
  assert_true(output(b) is Some(_))
  assert_true(!cleanup(active).unwrap())
  assert_true(release_output(b))
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "Infer cancellation at the last yield cannot hand out completed output" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  for _ in 0..<2000 {
    if handoff_pending(active) {
      break
    }
    assert_true(advance(active, 1).unwrap() is Continue(_))
  }
  assert_true(handoff_pending(active))
  assert_true(!cleanup(active).unwrap())
  assert_true(cancel(active))
  assert_true(advance(active, 1).unwrap() is Stopped(_))
  assert_true(acquire_output(active) is None)
  assert_true(capture(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "prefix cancellation makes no model call and retains cleanup custody" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  assert_true(advance(active, 1).unwrap() is Continue(_))
  assert_true(cancel(active))
  assert_true(!cleanup(active).unwrap())
  assert_true(fixture_finish(active) is Stopped(_))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}
