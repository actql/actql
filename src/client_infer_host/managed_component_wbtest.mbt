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
    prepared, occurrence, infer_fixture_registry, infer_fixture_values,
  ).unwrap()
  let suffix = @input.prepare_client_composed_infer_suffix(
    prepared, occurrence, infer_fixture_registry, infer_fixture_values,
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
  assert_true(local_component(active, project) is Err(InvalidAdvance))
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
