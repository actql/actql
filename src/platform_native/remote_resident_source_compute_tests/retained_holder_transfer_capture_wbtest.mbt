///|
/// Join separately admitted producer/consumer Runtime owners through the actual
/// receiver holding. Equal original materials are not shared object handles.
/// No provider Preview, approval, write or public Effect Result is simulated.
fn retained_holder_effect_transfer_capture(
  holder : @resident.ResidentRetainedConsumer,
  journal : @dispatch_journal.Journal,
  producer : @resident.ResidentEffectProducerExecuted,
  producer_journal : @dispatch_journal.Journal,
  input : @host.ClientRetainedTaskInput,
  site : @site.ExecutionSite,
) -> Unit raise {
  let source_owner = producer.source_for_capture(producer_journal).unwrap()
  let sender_materials = producer
    .materials_for_capture(producer_journal)
    .unwrap()
  let consumer = holder.effect_computation(journal).unwrap()
  let materials = consumer.effect_materials_for_capture().unwrap()
  assert_false(physical_equal(sender_materials.prepared, materials.prepared))
  assert_eq(
    @publication.publication_contract_identity(sender_materials.run_definition),
    @publication.publication_contract_identity(materials.run_definition),
  )
  let source_usage = source_owner.usage()
  let consumer_usage = consumer.usage()
  let source_record = producer_journal
    .observation(producer.executed.request)
    .unwrap()
  let original_observation = @dispatch_journal.recovered_site_dispatch_source_observation(
    source_record,
  ).unwrap()
  let original = @remote.remote_source_observation_projection(
    original_observation,
  )
  let (source, _) = producer
    .acquired_evidence_for_capture(
      producer_journal,
      retained_compute_effect_retention(),
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    .unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      @host.client_effect_acquired_observation(source),
    ),
    original.1,
  )
  let original_invocation = producer
    .invocation_for_capture(producer_journal, 65536, 4096, 64)
    .unwrap()
  let (original_observation_set, original_run_invocation) = original_invocation
  let original_observation_set_wire = @publication.run_evidence_value_json(
    original_observation_set,
  )
  assert_true(
    original_observation_set_wire.contains(
      "\"capture_started_at\":\"" + original.3 + "\"",
    ),
  )
  assert_true(
    original_observation_set_wire.contains(
      "\"capture_completed_at\":\"" + original.4 + "\"",
    ),
  )
  assert_true(
    original_observation_set_wire.contains(
      @publication.run_evidence_value_identity(
        @host.client_effect_acquired_observation(source),
      ),
    ),
  )
  assert_eq(
    producer.invocation_for_capture(producer_journal, 65536, 4096, 64).unwrap().1
    |> @publication.publication_contract_identity,
    @publication.publication_contract_identity(original_run_invocation),
  )
  assert_true(
    producer.invocation_for_capture(producer_journal, 1, 4096, 64)
    is Err(Invocation(_)),
  )
  // The production adapter joins actual original journal evidence to the
  // existing captured Result; no test issuer supplies its name or timestamps.
  assert_true(
    producer.prepare_dependency_capture(
      producer_journal,
      retained_compute_effect_retention(),
      resident_compute_limits(),
      4,
      1,
      65536,
      4096,
      64,
    )
    is Err({ issue: WorkLimit, pending: None, }),
  )
  assert_eq(source_owner.usage().held_bytes, source_usage.held_bytes)
  let dependency = producer
    .prepare_dependency_capture(
      producer_journal,
      retained_compute_effect_retention(),
      resident_compute_limits(),
      4,
      10000,
      65536,
      4096,
      64,
    )
    .unwrap()
  let sender = dependency.artifact
  let sender_manifest = dependency.manifest
  let token = dependency.token
  assert_eq(
    @publication.run_evidence_value_json(dependency.observation),
    original_observation_set_wire,
  )
  assert_eq(
    @publication.publication_contract_identity(dependency.invocation),
    @publication.publication_contract_identity(original_run_invocation),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      @host.client_effect_acquired_observation(dependency.acquired),
    ),
    original.1,
  )
  let inputs = @strategy.pin_captured_effect_sources(
    consumer.effect_run().unwrap(),
    4,
  ).unwrap()
  let mut root_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    let result = @strategy.captured_effect_local_result_at(inputs, index).unwrap()
    if @strategy.captured_effect_local_result_stage(result) == 0 &&
      @strategy.captured_effect_local_result_task(result) == 0 {
      root_index = index
    }
  }
  assert_true(root_index >= 0)
  let exported = consumer
    .prepare_effect_result_export(inputs, root_index, resident_compute_limits())
    .unwrap()
  let receipt = transferred_effect_result_receipt(exported)
  let captured = @strategy.capture_effect_result_import(inputs, 1, 0, 10000).unwrap()
  let bound = consumer.bind_effect_retained_result_artifact(
    materials, inputs, captured, exported, receipt, token,
  )
  assert_true(bound is Ok(_))
  let receiver = bound.unwrap()
  assert_eq(
    @host.client_effect_local_result_artifact_json(receiver),
    @host.client_effect_local_result_artifact_json(sender),
  )
  assert_eq(
    @host.client_effect_local_artifact_invocation_cid(receiver),
    @host.client_effect_local_artifact_invocation_cid(sender),
  )
  // The original sender context cannot stand in for the checked receiver's
  // imported evidence. The transfer supplies an exact receiver-owned context.
  assert_true(
    @host.issue_client_effect_local_manifest(
      materials.prepared,
      @host.client_effect_acquired_invocation(source),
      [receiver],
      65536,
      4096,
      64,
    )
    is Err(ForeignInvocation),
  )
  let receiver_invocation = @host.client_effect_local_artifact_invocation(
    receiver,
  )
  assert_true(
    @host.client_effect_local_invocation_matches(
      receiver_invocation,
      materials.prepared,
      0,
    ),
  )
  assert_false(
    @host.client_effect_local_invocation_matches(
      receiver_invocation,
      sender_materials.prepared,
      0,
    ),
  )
  let manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    receiver_invocation,
    [receiver],
    65536,
    4096,
    64,
  ).unwrap()
  assert_eq(
    @host.client_effect_local_manifest_json(manifest),
    @host.client_effect_local_manifest_json(sender_manifest),
  )
  let observation = @host.issue_client_effect_result_import_observation(
    materials.prepared,
    inputs,
    captured,
    manifest,
    receiver,
    65536,
    4096,
    64,
  ).unwrap()
  let imported = @host.issue_client_effect_imported_evidence(
    materials.prepared,
    inputs,
    1,
    [observation],
    65536,
    4096,
    64,
  ).unwrap()
  assert_eq(@host.client_effect_imported_relation_bodies(imported).length(), 1)
  let retry = consumer
    .bind_effect_retained_result_artifact(
      materials, inputs, captured, exported, receipt, token,
    )
    .unwrap()
  assert_eq(
    @host.client_effect_local_result_artifact_json(retry),
    @host.client_effect_local_result_artifact_json(receiver),
  )
  assert_eq(
    @host.client_effect_local_invocation_json(
      @host.client_effect_local_artifact_invocation(retry),
    ),
    @host.client_effect_local_invocation_json(receiver_invocation),
  )
  // A mismatching admission is refused even when its caller copies the correct
  // Run definition and uses the actually completed consumer's preparation.
  assert_true(
    consumer.bind_effect_retained_result_artifact(
      { ..materials, allowed: sender_materials.allowed, },
      inputs,
      captured,
      exported,
      receipt,
      token,
    )
    is Err(ForeignInput),
  )
  let current = @host.install_client_retained_input_current(
    () => site,
    () => @remote.dispatch_request_journal_key(producer.executed.request)[0],
    () => 1791504000000L,
    (_, _) => true,
  )
  let callbacks = Ref(0)
  let returned = Ref(false)
  assert_true(
    @host.bind_transferred_client_effect_local_result_artifact(
      materials,
      inputs,
      captured,
      exported,
      receipt,
      token,
      input,
      current,
      () => {
        callbacks.val += 1
        if callbacks.val == 2 {
          returned.val = dependency.pins.close()
        }
        true
      },
    )
    is Err(Unavailable),
  )
  assert_eq(callbacks.val, 2)
  assert_true(returned.val)
  assert_true(dependency.pins.close())
  assert_true(
    consumer.bind_effect_retained_result_artifact(
      materials, inputs, captured, exported, receipt, token,
    )
    is Err(Unavailable),
  )
  // Confirmed receiver evidence remains usable after its sender semantic borrow
  // is returned. The independent physical producer stays Runtime-owned.
  assert_true(
    @host.client_effect_local_result_payload_binding(
      receiver,
      materials.run_definition,
    )
    is Ok(_),
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(exported),
  )
  |> ignore
  let (run_observation, invocation) = original_invocation
  // Only normalization metadata is a fixture. The original Source observation,
  // transferred import and completed Native Result are actual Owner outputs.
  let normalization = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"version\":\"actql-normalization-journal/0.1\",\"rule_catalog_cid\":\"" +
    retained_compute_cid("d") +
    "\",\"entries\":[]}",
    65536,
    4096,
    64,
  ).unwrap()
  let result = consumer
    .capture_effect_result(
      materials,
      inputs,
      imported,
      invocation,
      run_observation,
      retained_compute_effect_retention(),
      normalization,
      [],
      [],
      [@host.client_effect_acquired_observation(source)],
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    .unwrap()
  assert_eq(
    result.output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_eq(result.output.row_count().unwrap(), 1)
  let read = result.output.replay().unwrap()
  let rows = StringBuilder()
  while read.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(read.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  @publication.validate_run_publication_chain(
    materials.run_definition,
    invocation,
    [result.definition],
    [result.artifact],
    result.manifest,
    65536,
    4096,
    64,
  ).unwrap()
  |> ignore
  result.output.cancel()
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_eq(source_owner.usage().held_bytes, source_usage.held_bytes)
  assert_eq(
    source_owner.usage().reserved_execution_bytes,
    source_usage.reserved_execution_bytes,
  )
  assert_eq(consumer.usage().held_bytes, consumer_usage.held_bytes)
  assert_eq(
    consumer.usage().reserved_execution_bytes,
    consumer_usage.reserved_execution_bytes,
  )
  assert_true(source_owner.effect_run() is Some(_))
  assert_true(consumer.effect_run() is Some(_))
  let (again, _) = producer
    .acquired_evidence_for_capture(
      producer_journal,
      retained_compute_effect_retention(),
      resident_compute_limits(),
      65536,
      4096,
      64,
    )
    .unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      @host.client_effect_acquired_observation(again),
    ),
    original.1,
  )
  assert_eq(
    @remote.remote_source_observation_json(
      @dispatch_journal.recovered_site_dispatch_source_observation(
        producer_journal.observation(producer.executed.request).unwrap(),
      ).unwrap(),
    ),
    @remote.remote_source_observation_json(original_observation),
  )
}
