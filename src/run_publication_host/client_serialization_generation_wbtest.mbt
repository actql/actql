///|
fn serialization_generation_test_run(
  owner : PreparedClientProgram,
  rows : Int,
  bytes : Int,
) -> ClientCompiledRun {
  let component = issue_prepared_client_serialization_plan_graph(
    owner,
    0,
    1,
    serialization_plan_test_policy(),
    rows,
    bytes,
    3,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = issue_prepared_client_serialization_compilation(
    owner,
    component,
    run_materials_manifests(),
    1000,
    1000,
    100000,
    10000,
    100,
  ).unwrap()
  issue_client_task_compiled_run(
    owner,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
}

///|
fn serialization_generation_test_binding(
  policy : String,
) -> @publication.GeneratedContentBinding {
  {
    content_store_id: "fixture",
    content_store_cid: "sha256:" + "1".repeat(64),
    workspace_scope_cid: "sha256:" + "2".repeat(64),
    storage_scope: "workspace",
    retention_class: "fixture",
    expires_at: None,
    availability_evidence_cid: "sha256:" + "3".repeat(64),
    effective_data_policy_cid: policy,
    data_classification: "unknown",
    issuer_contract_cid: "sha256:" + "5".repeat(64),
    capture_authority_cid: "sha256:" + "6".repeat(64),
  }
}

///|
fn serialization_generation_test_definition(
  run : ClientCompiledRun,
  name? : String = "content-generation",
) -> @publication.PublicationContract {
  issue_client_compiled_run_definition(
    run, "local", name, "2026-10-09T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
}

///|
fn serialization_generation_test_input_evidence(
  run : ClientCompiledRun,
  input : ClientSerializationInput,
  codec? : (Int, Int, Int) = (16384, 256, 16),
) -> ClientSerializationInputEvidence raise {
  let wire : @execution.RowWireLimits = {
    max_columns: 100,
    max_order_work: 1000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let scan = start_client_serialization_input_identity(
    input,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 100, max_work: 10000, },
    wire,
    wire,
    { max_fields: 100, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    10000,
    10000,
  ).unwrap()
  let mut ready = false
  for _ in 0..<10000 {
    if @execution.advance_completed_relation_identity_scan(scan, 7).unwrap().0 {
      ready = true
      break
    }
  }
  assert_true(ready)
  let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
  let evidence = bind_client_serialization_input_identity(
    run,
    input,
    receipt,
    codec.0,
    codec.1,
    codec.2,
  ).unwrap()
  @execution.cancel_completed_relation_export_receipt(receipt)
  evidence
}

///|
test "Serialize generation closes exact compiled component policy ceilings and live custody" {
  let owner = serialization_preparation_test_program()
  let run = serialization_generation_test_run(owner, 2, 18)
  let definition = serialization_generation_test_definition(run)
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let (active, source) = serialization_completed_test_input(barrier)
  let encoder = start_client_serialization_encoder(
    barrier,
    max_rows=2,
    max_bytes=18,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  let input = bind_client_serialization_completed_input(
    barrier, source, encoder,
  ).unwrap()
  let input_evidence = serialization_generation_test_input_evidence(run, input)
  let reference_limits : @values.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let policy = @publication.captured_effect_dependency_body_cid(
    serialization_plan_test_policy(),
  )
  let binding = serialization_generation_test_binding(policy)
  assert_true(
    @publication.prepare_generated_content_reference(
      encoder, binding, reference_limits,
    )
    is Err(GenerationIncomplete),
  )
  assert_eq(serialization_test_drain(encoder), "")
  for row in 0..<2 {
    start_client_serialization_input_row(input, row).unwrap()
    assert_eq(
      serialization_test_drain(encoder),
      if row == 0 {
        "{\"id\":2}\n"
      } else {
        "{\"id\":1}\n"
      },
    )
  }
  let completion = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq(
    completion.content_cid,
    "sha256:982974408fc3063d258439d976049c7f4863d98bedfe933132af17b3636ffd60",
  )
  let candidate = @publication.prepare_generated_content_reference(
    encoder, binding, reference_limits,
  ).unwrap()
  let live = Ref(true)
  let issuer = @values.bind_reference_issuer(
    (_, wire) => {
      live.val &&
      wire == @publication.generated_content_reference_wire(candidate)
    },
    _ => live.val,
  )
  let content = @publication.issue_generated_content_reference(
    candidate, issuer, reference_limits,
  ).unwrap()
  let limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 10000,
  }
  for (rows, bytes) in [(1, 18), (2, 17)] {
    let limited = serialization_generation_test_run(owner, rows, bytes)
    assert_true(
      complete_client_serialization_generation(
        limited,
        serialization_generation_test_definition(limited),
        input,
        input_evidence,
        candidate,
        content,
        () => live.val,
        limits,
        1000,
      )
      is Err(QuantityMismatch),
    )
  }
  let foreign = serialization_generation_test_run(
    serialization_preparation_test_program(),
    2,
    18,
  )
  assert_true(
    complete_client_serialization_generation(
      foreign,
      serialization_generation_test_definition(foreign),
      input,
      input_evidence,
      candidate,
      content,
      () => live.val,
      limits,
      1000,
    )
    is Err(ForeignInput),
  )
  let wrong_policy = @publication.prepare_generated_content_reference(
    encoder,
    { ..binding, effective_data_policy_cid: "sha256:" + "4".repeat(64), },
    reference_limits,
  ).unwrap()
  assert_true(
    complete_client_serialization_generation(
      run,
      definition,
      input,
      input_evidence,
      wrong_policy,
      content,
      () => live.val,
      limits,
      1000,
    )
    is Err(PolicyMismatch),
  )
  let generation = complete_client_serialization_generation(
    run,
    definition,
    input,
    input_evidence,
    candidate,
    content,
    () => live.val,
    limits,
    1000,
  ).unwrap()
  assert_true(
    client_serialization_generation_capture_for(generation, run, definition)
    is Some(_),
  )
  assert_true(
    client_serialization_generation_capture_for(
      generation,
      foreign,
      serialization_generation_test_definition(foreign),
    )
    is None,
  )
  assert_true(
    client_serialization_generation_capture_for(
      generation,
      run,
      serialization_generation_test_definition(run, name="another-run"),
    )
    is None,
  )
  assert_true(
    client_serialization_generation_output_for(generation, run) is Some(_),
  )
  assert_true(
    client_serialization_generation_output_for(
      generation,
      serialization_generation_test_run(owner, 2, 18),
    )
    is None,
  )
  assert_true(@execution.completed_output_available(source))
  assert_true(@execution.cleanup_bounded_values(active).unwrap())
  assert_true(!@execution.bounded_values_cleanup_pending(active))
  // Finished bytes retain their own custody after source-row cleanup.
  assert_true(
    client_serialization_generation_output_for(generation, run) is Some(_),
  )
  assert_eq(
    client_serialization_generation_reference_for(generation, run),
    Some(@publication.generated_content_reference_identity(candidate)),
  )
  let saved = client_serialization_generation_recovery_bindings(
    generation,
    run,
    "sha256:" + "1".repeat(64),
  ).unwrap()
  assert_eq(saved.length(), 3)
  assert_eq(saved.map(item => item.0), [
    "content_input_artifact", "content_evidence", "content_generation",
  ])
  assert_eq(
    saved[0].1,
    @publication.run_evidence_value_identity(input_evidence.artifact),
  )
  assert_eq(
    saved[0].2,
    @publication.run_evidence_value_json(input_evidence.artifact),
  )
  // Saved metadata is admitted independently, under the original compiled
  // component and current Ref, after the original Source rows are gone.
  let stored = @publication.prepare_stored_generated_content_reference(
    @publication.generated_content_reference_wire(candidate),
    binding,
    reference_limits,
  ).unwrap()
  let restored_content = @publication.issue_stored_generated_content_reference(
    stored, issuer, reference_limits,
  ).unwrap()
  let restored = readmit_client_serialization_generation_evidence(
    run,
    definition,
    saved[2].1,
    @publication.admit_run_evidence_value(
      saved[0].0,
      saved[0].2,
      16384,
      256,
      16,
    ).unwrap(),
    @publication.admit_run_evidence_value(
      saved[1].0,
      saved[1].2,
      16384,
      256,
      16,
    ).unwrap(),
    @publication.admit_run_evidence_value(
      saved[2].0,
      saved[2].2,
      16384,
      256,
      16,
    ).unwrap(),
    stored,
    restored_content,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      @publication.bound_content_generation_value(restored).unwrap(),
    ),
    saved[2].2,
  )
  assert_true(
    readmit_client_serialization_generation_evidence(
      foreign,
      serialization_generation_test_definition(foreign, name="another-run"),
      saved[2].1,
      input_evidence.artifact,
      @publication.bound_content_generation_derivation(generation.evidence).unwrap(),
      @publication.bound_content_generation_value(generation.evidence).unwrap(),
      stored,
      restored_content,
    )
    is Err(_),
  )
  assert_true(
    client_serialization_generation_recovery_bindings(
      generation,
      foreign,
      "sha256:" + "1".repeat(64),
    )
    is None,
  )
  assert_true(
    client_serialization_generation_recovery_bindings(
      generation,
      run,
      "sha256:" + "9".repeat(64),
    )
    is None,
  )
  let evidence = client_serialization_generation_evidence_for(generation, run).unwrap()
  let body = parse_plan_identity_value(
    @publication.run_evidence_value_json(evidence),
    16384,
    256,
    16,
  ).unwrap()
  let derivation = client_serialization_generation_derivation_for(
    generation, run,
  ).unwrap()
  let derivation_body = parse_plan_identity_value(
    @publication.run_evidence_value_json(derivation),
    16384,
    256,
    16,
  ).unwrap()
  assert_true(
    @canonical.object_field(derivation_body, "content_cid")
    is Some(
      @canonical.String(
        "sha256:982974408fc3063d258439d976049c7f4863d98bedfe933132af17b3636ffd60"
      )
    ),
  )
  assert_true(
    @canonical.object_field(derivation_body, "barrier_input_artifact_cid")
    is Some(@canonical.String(cid)) &&
    cid == @publication.run_evidence_value_identity(input_evidence.artifact),
  )
  assert_true(
    @canonical.object_field(body, "content_evidence_cid")
    is Some(@canonical.String(cid)) &&
    cid == @publication.run_evidence_value_identity(derivation),
  )
  assert_true(
    @canonical.object_field(body, "run_definition_cid")
    is Some(@canonical.String(cid)) &&
    cid == @publication.publication_contract_identity(definition),
  )
  let (observation, invocation) = issue_client_serialization_invocation(
    run, definition, generation, 100000, 10000, 100,
  ).unwrap()
  let wrong_availability_wire = @publication.run_evidence_value_json(
    observation,
  ).replace(old="sha256:" + "3".repeat(64), new="sha256:" + "4".repeat(64))
  let wrong_availability = @publication.seal_run_evidence_value(
    "observation_set",
    @canonical.stringify_value(
      @canonical.object_without_field(
        parse_plan_identity_value(wrong_availability_wire, 100000, 10000, 100).unwrap(),
        "observation_set_cid",
      ).unwrap(),
      100000,
      10000,
      100,
    ),
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    @publication.issue_content_run_invocation(
      run.template,
      wrong_availability,
      [generation.evidence],
      100000,
      10000,
      100,
    )
    is Err(
      @publication.RunEvidenceReferenceMismatch(
        "content_generation.availability"
      )
    ),
  )
  assert_true(
    @publication.issue_run_invocation(
      run.template,
      observation,
      100000,
      10000,
      100,
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_generation_cids")),
  )
  assert_true(
    @publication.issue_content_run_invocation(
      run.template,
      observation,
      [],
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  assert_true(
    issue_client_serialization_invocation(
      run,
      serialization_generation_test_definition(run, name="another-run"),
      generation,
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  assert_true(
    @publication.publication_contract_identity(invocation).has_prefix("sha256:"),
  )
  live.val = false
  assert_true(
    client_serialization_generation_output_for(generation, run) is None,
  )
  assert_true(
    complete_client_serialization_generation(
      run,
      definition,
      input,
      input_evidence,
      candidate,
      content,
      () => live.val,
      limits,
      1000,
    )
    is Err(Evidence(_)),
  )
  assert_true(
    issue_client_serialization_invocation(
      run, definition, generation, 100000, 10000, 100,
    )
    is Err(_),
  )
}

///|
test "Content input Artifact stays inside the same closed evidence codec under a larger generic caller ceiling" {
  assert_eq(client_serialization_evidence_codec_bounds(), (16384, 256, 16))
  let owner = serialization_preparation_test_program()
  let run = serialization_generation_test_run(owner, 2, 18)
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let (active, source) = serialization_completed_test_input(barrier)
  let encoder = start_client_serialization_encoder(
    barrier,
    max_rows=2,
    max_bytes=18,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  let input = bind_client_serialization_completed_input(
    barrier, source, encoder,
  ).unwrap()
  let original = serialization_generation_test_input_evidence(
    run,
    input,
    codec=(1000000, 100000, 64),
  )
  assert_true(physical_equal(original.run, run))
  assert_true(physical_equal(original.input, input))
  let wire = @publication.run_evidence_value_json(original.artifact)
  // This closed emitter contains ASCII CIDs and Int fields, no input rows or
  // original Program/schema body. UTF-16 length equals UTF-8 length here.
  assert_true(wire.length() < 16384)
  assert_true(wire.contains("\"program_definition_cid\""))
  assert_true(wire.contains("\"relation_schema_cid\""))
  assert_false(wire.contains("\"rows\":"))
  assert_true(@execution.cleanup_bounded_values(active).unwrap())
}
