///|
test "restored prepared input maps saved completion without restarting its prefix" {
  let calls = Ref(0)
  let old = failed_outcome_start(
    @model.Timeout,
    calls,
    defer_dispatch=true,
    enter_call=Some(_ => true),
  )
  invocation_fixture_compiled(old) |> ignore
  let mut waiting = false
  for _ in 0..<2000 {
    if advance(old, 1).unwrap() is Waiting(_) {
      waiting = true
      break
    }
  }
  assert_true(waiting)
  let original_set = prepared_model_call_set(old).unwrap()
  let input_wire = @publication.run_evidence_value_json(
    @model.prepared_model_call_set_input(original_set).unwrap(),
  )
  let slot_wire = @publication.run_evidence_value_json(
    @model.prepared_model_call_set_slot(original_set, 0).unwrap(),
  )
  let exporter = prepare_model_approval_input_export(old, 16384).unwrap()
  let rows = []
  while @relation.next_completed_output_export_canonical_row(
          exporter, 10000, 100, 16384,
        ).unwrap()
        is Some((_, batch, _)) {
    // The common exporter has checked the leading array delimiter. Retained
    // content/import readers consume one object, not the stream envelope.
    rows.push(batch[1:].to_owned())
  }
  assert_eq(rows, ["{\"id\":\"a\",\"text\":\"hello\"}"])
  let (receipt, _) = @relation.finish_completed_relation_export(exporter).unwrap()
  let original_live = Ref(true)
  let original_material = @relation.retained_output_material(
    @relation.retain_admitted_output_stream(
      @relation.completed_relation_export_content(receipt),
      (),
      () => original_live.val,
    ),
  )
  let retained = @relation.bind_completed_relation_export(
    receipt, original_material,
  ).unwrap()
  let evidence = @relation.retain_completion_evidence(retained, 1000, 100000).unwrap()
  let descriptor = @relation.retained_completion_descriptor(evidence)
  let prepared = old.prepared.unwrap()
  let plan = old.plan.unwrap()
  let limits = standard_limits()
  let prefix = @input.prepare_client_infer_prefix(
    prepared, 0, 2, infer_fixture_registry, infer_fixture_values,
  ).unwrap()
  let receiving = @relation.generated_completion_preparation(prefix)
  assert_true(cancel(old))
  for _ in 0..<2000 {
    if advance(old, 1).unwrap() is Stopped(_) {
      break
    }
  }
  assert_true(cleanup(old).unwrap())
  original_live.val = false
  assert_true(!@relation.completed_output_available(retained))
  let reader = @relation.prepare_retained_content_read(
    receiving,
    descriptor,
    limits.identity.rows,
    limits.input.rows.output_values,
    limits.identity.wire,
    16384,
  ).unwrap()
  let decode : @relation.RetainedRowDecodeLimits = {
    max_bytes: 16384,
    max_nodes: 10000,
    max_depth: 64,
    max_text_bytes: 16384,
  }
  for row in rows {
    @relation.append_retained_content_read(reader, row, decode).unwrap()
  }
  let read_receipt = @relation.finish_retained_content_read(reader).unwrap()
  let live = Ref(true)
  let material = @relation.retained_output_material(
    @relation.retain_admitted_output_stream(read_receipt, (), () => live.val),
  )
  // Store authentication is an explicit test port. Core still checks the
  // complete ordered bytes and exact receiving completion independently.
  let port = @relation.prepare_trusted_retained_readmission(
    receiving,
    descriptor,
    1000,
    100000,
    proof => {
      if live.val && physical_equal(proof, read_receipt) {
        Some(material)
      } else {
        None
      }
    },
  ).unwrap()
  let restored = @relation.readmit_trusted_retained_output(port, read_receipt).unwrap()
  let importing = @relation.prepare_completed_output_import(
    restored,
    limits.identity.rows,
    limits.input.rows.output_values,
    limits.identity.wire,
    16384,
  ).unwrap()
  for row in rows {
    @relation.append_completed_output_import_wire(importing, row, decode).unwrap()
  }
  let completed = @relation.finish_completed_output_import(importing).unwrap()
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.Timeout)
  }).unwrap()
  let active = start_restored_prepared_input(
    prepared,
    2,
    infer_fixture_registry,
    infer_fixture_values,
    provider,
    completed,
    limits,
    plan,
    _ => true,
  ).unwrap()
  invocation_fixture_compiled(active) |> ignore
  waiting = false
  for _ in 0..<2000 {
    if advance(active, 1).unwrap() is Waiting(_) {
      waiting = true
      break
    }
  }
  assert_true(waiting)
  let set = prepared_model_call_set(active).unwrap()
  assert_eq(@model.prepared_model_call_set_count(set), Some(1))
  assert_eq(
    @publication.run_evidence_value_json(
      @model.prepared_model_call_set_input(set).unwrap(),
    ),
    input_wire,
  )
  assert_eq(
    @publication.run_evidence_value_json(
      @model.prepared_model_call_set_slot(set, 0).unwrap(),
    ),
    slot_wire,
  )
  assert_eq(calls.val, 0)
  assert_true(cancel(active))
  for _ in 0..<2000 {
    if advance(active, 1).unwrap() is Stopped(_) {
      break
    }
  }
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
  assert_true(@relation.completed_output_available(completed))
  live.val = false
  assert_true(!@relation.completed_output_available(completed))
  assert_true(
    start_restored_prepared_input(
      prepared,
      2,
      infer_fixture_registry,
      infer_fixture_values,
      provider,
      completed,
      limits,
      plan,
      _ => true,
    )
    is Err(_),
  )
  assert_eq(calls.val, 0)
}
