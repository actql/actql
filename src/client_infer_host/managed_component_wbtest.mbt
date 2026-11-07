///|
test "Local component keeps composed INFER work deltas and output custody" {
  let source = infer_fixture_program
    .replace(
      old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
      new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"second\"}]",
    )
    .replace(
      old="\"as\":\"captured\"}],",
      new="\"as\":\"captured\"},{\"select\":[\"id\",\"outcome\"],\"as\":\"projected\"}],",
    )
    .replace(
      old="\"from\":\"captured\",\"fields\":[\"id\",\"outcome\",\"value\"]",
      new="\"from\":\"projected\",\"fields\":[\"id\",\"outcome\"]",
    )
  let prepared = fixture_prepared(source~)
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let prefix = @input.prepare_client_composed_infer_prefix(
    prepared,
    occurrence,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
  ).unwrap()
  let suffix = @input.prepare_client_composed_infer_suffix(
    prepared,
    occurrence,
    infer_fixture_installed_contracts(),
    infer_fixture_values,
  ).unwrap()
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Ok({
      value: @admitted.object_value([
        ("reason", @admitted.null_value()),
        ("risk", @admitted.text_value("high", 100).unwrap()),
      ]).unwrap(),
      provider_model: "fixture",
      provider_request_id: calls.val.to_string(),
      input_tokens: 1L,
      output_tokens: 2L,
      observed_at: "2026-10-03T00:00:00.000Z",
    })
  }).unwrap()
  let active = start_composed(
    occurrence,
    call_identity_plan(prepared),
    prefix,
    [],
    provider,
    standard_limits(),
  ).unwrap()
  bind_compute_suffix(active, suffix).unwrap()
  let issues : Ref[Issue?] = Ref(None)
  let project = issue => {
    issues.val = Some(issue)
    @connector.ComputeUnsupported
  }
  let child = local_component(active, project).unwrap()
  assert_eq(active.entry_work, 0L)
  assert_true(local_component(active, project) is Err(InvalidAdvance))
  assert_true(advance_root(active, 1) is Err(InvalidAdvance))
  assert_true(!@local.cleanup_managed_provider(child).unwrap())
  let mut output = None
  let mut charged = 0L
  for _ in 0..<5000 {
    let poll = @local.advance_managed_provider(child, 1).unwrap()
    match poll {
      @local.Continue(progress~, work~) => {
        assert_true(work >= 0L && work <= 1L)
        assert_eq(progress, work)
        charged += work
      }
      @local.Complete(value, progress~, work~) => {
        assert_true(work >= 0L && work <= 1L)
        assert_eq(progress, work)
        charged += work
        output = Some(value)
        break
      }
      _ =>
        abort(
          "composed INFER must complete through the existing Local component",
        )
    }
  }
  let result = output.unwrap()
  assert_eq(charged, active.work)
  assert_true(charged > 1L)
  assert_eq(calls.val, 2)
  assert_true(issues.val is None)
  assert_eq(@relation.completed_row_count(result), 2)
  assert_eq(@relation.completed_column_count(result), 2)
  assert_eq(@relation.completed_column_name(result, 0), Some("id"))
  assert_eq(@relation.completed_column_name(result, 1), Some("outcome"))
  assert_true(
    @relation.completed_cell(result, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(result, 1, 0) is Some(@relation.Text("b")),
  )
  assert_true(
    @relation.completed_cell(result, 0, 1) is Some(@relation.Text("ok")),
  )
  assert_true(
    @relation.completed_cell(result, 1, 1) is Some(@relation.Text("ok")),
  )
  let held = acquire_output(active).unwrap()
  assert_true(!@local.cleanup_managed_provider(child).unwrap())
  assert_true(@relation.completed_row_count(held.output) == 2)
  assert_true(release_output(held))
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_eq(calls.val, 2)
}

///|
test "Local component refuses an already advanced original instead of resetting its work history" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  assert_eq(active.entry_work, 0L)
  for _ in 0..<1000 {
    guard advance_root(active, 1).unwrap() is Continue(..) else {
      abort("the actual input must make progress before Model dispatch")
    }
    if active.work > active.entry_work {
      break
    }
  }
  assert_true(active.phase is Input)
  let before = active.work
  assert_true(before > 0L)
  assert_eq(calls.val, 0)
  assert_true(
    local_component(active, _ => @connector.ComputeUnsupported)
    is Err(InvalidAdvance),
  )
  assert_eq(active.work, before)
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  assert_true(fixture_finish(active, initial_work=active.work) is Stopped(..))
  assert_true(cleanup(active).unwrap())
  assert_eq(active.work, before)
  assert_eq(calls.val, 0)
}

///|
test "Local component cancellation before its first poll adds no work or Model call" {
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(), () => calls.val += 1)
  let child = local_component(active, _ => @connector.ComputeUnsupported).unwrap()
  let before = active.work
  assert_true(@local.cancel_managed_provider(child))
  guard @local.advance_managed_provider(child, 1).unwrap()
    is @local.Stopped(progress~, work~) else {
    abort("the original cancelled component must stop on its first poll")
  }
  assert_eq(progress, 0L)
  assert_eq(work, 0L)
  assert_eq(active.work, before)
  assert_eq(@local.managed_provider_cumulative_work(child).unwrap(), 0L)
  assert_eq(calls.val, 0)
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_eq(active.work, before)
  assert_eq(calls.val, 0)
}

///|
test "failed assertion component retains stopped evidence until Host cleanup" {
  let source = infer_fixture_program.replace(
    old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"a\",\"text\":\"second\"}]",
  )
  let calls = Ref(0)
  let active = fixture_start(fixture_prepared(source~), () => calls.val += 1)
  let issue : Ref[Issue?] = Ref(None)
  let released = Ref(false)
  let child = local_component(
    active,
    failure => {
      issue.val = Some(failure)
      @connector.ComputeUnsupported
    },
    allow_cleanup=_ => released.val,
  ).unwrap()
  for _ in 0..<5000 {
    match @local.advance_managed_provider(child, 1).unwrap() {
      @local.Continue(..) => ()
      @local.Failed(_, ..) => break
      _ => abort("duplicate assertion must fail before Model dispatch")
    }
  }
  assert_true(
    issue.val
    is Some(
      Input(
        @input.Local(
          @connector.Execution(
            @relation.SequenceRunIssue::Rows(
              _,
              @relation.AssertionDuplicate(0, 1)
            )
          )
        )
      )
    ),
  )
  assert_eq(calls.val, 0)
  assert_true(execution_stopped(active))
  assert_true(!@local.cleanup_managed_provider(child).unwrap())
  assert_eq(stopped_attempt_count(active), Some(0))
  assert_true(cleanup(active).unwrap())
  released.val = true
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_eq(calls.val, 0)
}
