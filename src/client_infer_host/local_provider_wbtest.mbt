///|
test "Local selects the original whole INFER Unit and retains its Model owner" {
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
  let contracts = @relation.admit_relation_registry(
    @canonical.from_json(
      @json.parse(infer_fixture_registry),
      10000,
      100,
      100000,
    ),
    @canonical.from_json(@json.parse(infer_fixture_values), 10000, 100, 100000),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let generated = @relation.prepare_generated_sequence(
    contracts,
    @relation.generated_prepared_sequence(suffix),
    [],
    Array::makei(@relation.generated_retained_count(suffix), index => {
      @relation.generated_retained_at(suffix, index).unwrap()
    }),
    100000,
    10000,
  )
  let sequence = generated.unwrap()
  let calls = Ref(0)
  let starts = Ref(0)
  let owner : Ref[Execution?] = Ref(None)
  let capture_owner : Ref[OutputUse?] = Ref(None)
  let completions = Ref(0)
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
  let limits = standard_limits()
  let family = composed_local_provider(
    occurrence,
    limits,
    inputs => {
      starts.val += 1
      let active = start_composed(
        occurrence,
        call_identity_plan(prepared),
        prefix,
        inputs,
        provider,
        limits,
      ).unwrap()
      owner.val = Some(active)
      bind_compute_suffix(active, suffix).unwrap()
      Ok(active)
    },
    _ => @connector.ComputeUnsupported,
    retain_completed=active => {
      if !physical_equal(active, owner.val.unwrap()) {
        return false
      }
      completions.val += 1
      capture_owner.val = acquire_output(active)
      capture_owner.val is Some(_)
    },
  )
  assert_true(@local.managed_provider_accepts(family, sequence))
  assert_true(!@local.managed_provider_accepts(family, prefix))
  assert_true(!@local.managed_provider_accepts(family, suffix))
  assert_true(
    !@local.managed_provider_accepts(
      family,
      @relation.select_generated_sequence_step(sequence, 2).unwrap(),
    ),
  )
  let foreign_prepared = fixture_prepared(source~)
  let foreign_occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    foreign_prepared,
  ).unwrap()
  let foreign_suffix = @input.prepare_client_composed_infer_suffix(
    foreign_prepared, foreign_occurrence, infer_fixture_registry, infer_fixture_values,
  ).unwrap()
  let foreign = @relation.prepare_generated_sequence(
    contracts,
    @relation.generated_prepared_sequence(foreign_suffix),
    [],
    Array::makei(@relation.generated_retained_count(foreign_suffix), index => {
      @relation.generated_retained_at(foreign_suffix, index).unwrap()
    }),
    100000,
    10000,
  ).unwrap()
  assert_true(!@local.managed_provider_accepts(family, foreign))
  assert_true(@local.managed_provider_capacity(family, foreign) is None)
  assert_true(
    @local.start_managed_provider_with_inputs_and_execution(
      family,
      suffix,
      [],
      100,
      500000,
      limits.input,
    )
    is Err(_),
  )
  assert_eq(starts.val, 0)
  let capacity = @local.managed_provider_capacity(family, sequence).unwrap()
  let base = @relation.generated_sequence_capacity(
    sequence,
    limits.input,
    limits.measurement,
  ).unwrap()
  assert_true(
    @relation.execution_capacity_retained_bytes(capacity) >=
    @relation.execution_capacity_retained_bytes(base) +
    limits.model.ledger.retained_bytes,
  )
  for bytes in [-1L, 9223372036854775807L] {
    let impossible : Limits = {
      ..limits,
      model: {
        ..limits.model,
        ledger: { ..limits.model.ledger, retained_bytes: bytes, },
      },
    }
    assert_true(composed_local_capacity(sequence, impossible) is None)
  }
  let child = @local.start_managed_provider_with_inputs_and_execution(
    family,
    sequence,
    [],
    100,
    500000,
    limits.input,
  ).unwrap()
  assert_eq(starts.val, 1)
  assert_eq(calls.val, 0)
  assert_true(
    @local.start_managed_provider_with_inputs_and_execution(
      family,
      sequence,
      [],
      100,
      500000,
      limits.input,
    )
    is Err(_),
  )
  assert_eq(starts.val, 1)
  let mut output = None
  for _ in 0..<5000 {
    match @local.advance_managed_provider(child, 1).unwrap() {
      @local.Continue(work~, ..) => assert_true(work >= 0L && work <= 1L)
      @local.Complete(value, work~, ..) => {
        assert_true(work >= 0L && work <= 1L)
        output = Some(value)
        break
      }
      _ => abort("original Model component must finish the selected Local Unit")
    }
  }
  let output = output.unwrap()
  assert_eq(calls.val, 2)
  assert_eq(completions.val, 1)
  assert_eq(@relation.completed_row_count(output), 2)
  assert_eq(@relation.completed_column_count(output), 2)
  assert_eq(@relation.completed_column_name(output, 0), Some("id"))
  assert_eq(@relation.completed_column_name(output, 1), Some("outcome"))
  assert_true(
    @relation.completed_cell(output, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(output, 1, 0) is Some(@relation.Text("b")),
  )
  assert_true(
    @relation.completed_cell(output, 0, 1) is Some(@relation.Text("ok")),
  )
  let held = capture_owner.val.unwrap()
  assert_true(!@local.cleanup_managed_provider(child).unwrap())
  assert_true(release_output(held))
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_eq(calls.val, 2)
}
