// Real Native acquisition to the complete checked producer dependency.
// Consumer dispatch, transferred dependency restoration and Effect apply are
// separate boundaries; none is simulated as a successful operation here.

///|
fn producer_dependency_observation(
  materials : @host.ClientEffectRunMaterials,
  source : @host.ClientEffectAcquiredEvidence,
) -> (@publication.RunEvidenceValue, @publication.PublicationContract) {
  let template = @host.client_effect_compilation_template(materials.compilation)
  let observed = @host.client_effect_acquired_observation(source)
  let observation = @publication.seal_run_evidence_value(
    "observation_set",
    "{\"version\":\"actql-observation-set/0.1\",\"invocation_template_cid\":\"" +
    @publication.run_evidence_value_identity(template) +
    "\",\"source_evidence_cids\":[\"" +
    @publication.run_evidence_value_identity(observed) +
    "\"],\"captured_input_artifact_cids\":[],\"consistency\":\"single_snapshot\",\"capture_started_at\":\"2026-10-09T01:00:00.000Z\",\"capture_completed_at\":\"2026-10-09T01:00:01.000Z\",\"replayability\":{\"materialized\":false,\"availability_evidence_cids\":[]},\"data_policy_cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\"}",
    65536,
    4096,
    64,
  ).unwrap()
  (
    observation,
    @publication.issue_run_invocation(template, observation, 65536, 4096, 64).unwrap(),
  )
}

///|
test "Native Effect producer dependency is issued before consumer execution" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let name = "effect-producer-dependency-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  resident_compute_database(library, path)
  let (materials, _) = retained_compute_effect_materials()
  let bound = @host.bind_client_effect_compiled_run(
    materials.prepared,
    materials.allowed,
    materials.run_definition,
  ).unwrap()
  let acquisitions = Ref(0)
  let consumers = Ref(0)
  let owner = @resident.open_resident_effect_source_compute(
    bound,
    resident_compute_configuration(library, path),
    name,
    observe=event => {
      match event {
        @resident.AcquisitionEntered => acquisitions.val += 1
        @resident.ConsumerEntered(_) => consumers.val += 1
        _ => ()
      }
      true
    },
  ).unwrap()
  let run = owner.effect_run().unwrap()
  // The final Effect inventory still refuses the not-yet-completed consumer.
  assert_true(@strategy.pin_captured_effect_sources(run, 4) is Err(_))
  assert_true(
    @strategy.pin_captured_effect_acquired_unit_results(run, 1, 4)
    is Err(ForeignCandidate),
  )
  assert_true(
    @strategy.pin_captured_effect_acquired_unit_results(run, 0, 0)
    is Err(PreviewWorkLimit),
  )
  let inputs = @strategy.pin_captured_effect_acquired_unit_results(run, 0, 4).unwrap()
  assert_eq(@strategy.captured_effect_local_unit_result_count(inputs), 1)
  let other_inputs = @strategy.pin_captured_effect_acquired_unit_results(
    run, 0, 4,
  ).unwrap()
  resident_compute_reclaim(root, name)
  let (source, _) = retained_compute_acquired_evidence(owner).unwrap()
  let (observation, invocation) = producer_dependency_observation(
    materials, source,
  )
  let limits = resident_compute_limits()
  let exported = @strategy.start_captured_effect_local_unit_result_export(
    inputs,
    0,
    {
      max_fields: limits.max_result_fields,
      max_mapping_work: limits.max_result_mapping_work,
      max_order_work: limits.max_result_order_work,
      max_workspace_entries: limits.max_result_workspace_entries,
    },
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  while !@execution.advance_completed_result_relation_export(preparation, 16).unwrap().0 {
    continue
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let rows = StringBuilder()
  while @execution.next_completed_output_export(stream).unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  rows.write_string(tail)
  assert_eq(rows.to_string(), "[{\"id\":1},{\"id\":2},{\"id\":3}]")
  let definition = @host.issue_client_effect_local_result_definition(
    materials.prepared,
    0,
    "r",
    65536,
    4096,
    64,
  ).unwrap()
  let issue = (pins, result_definition, run_definition, export_receipt) => {
    @host.issue_acquired_client_effect_unit_result_artifact(
      materials.prepared,
      pins,
      exported,
      source,
      result_definition,
      export_receipt,
      @host.client_effect_allowed_run_admission(materials.allowed),
      run_definition,
      invocation,
      observation,
      65536,
      4096,
      64,
    )
  }
  let artifact = issue(inputs, definition, materials.run_definition, receipt).unwrap()
  let manifest = @host.issue_client_effect_local_manifest(
    materials.prepared,
    @host.client_effect_acquired_invocation(source),
    [artifact],
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    @host.client_effect_local_manifest_json(manifest).contains(
      "\"r\":\"" +
      @host.client_effect_local_result_artifact_cid(artifact) +
      "\"",
    ),
  )
  assert_eq(
    @host.client_effect_local_result_payload_binding(
      artifact,
      materials.run_definition,
    ).unwrap().1,
    @execution.output_stream_identity(
      @execution.completed_relation_export_content(receipt),
    ).1,
  )
  assert_true(
    @host.issue_client_effect_local_manifest(
      materials.prepared,
      @host.client_effect_acquired_invocation(source),
      [],
      65536,
      4096,
      64,
    )
    is Err(IncompleteResults),
  )
  assert_true(
    issue(other_inputs, definition, materials.run_definition, receipt)
    is Err(ForeignOwner),
  )
  let consumer_definition = @host.issue_client_effect_local_result_definition(
    materials.prepared,
    1,
    "r",
    65536,
    4096,
    64,
  ).unwrap()
  assert_true(
    issue(inputs, consumer_definition, materials.run_definition, receipt)
    is Err(ForeignDefinition),
  )
  let another_run = @host.issue_client_effect_run_definition(
    materials.allowed,
    "retained-effect",
    "different-original-run",
    "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    issue(inputs, definition, another_run, receipt) is Err(ForeignRun),
  )
  let another_export = owner.prepare_source_export(limits).unwrap()
  while @execution.next_completed_output_export(another_export).unwrap()
        is Some(_) {

  }
  let (foreign_receipt, _) = @execution.finish_completed_relation_export(
    another_export,
  ).unwrap()
  assert_true(
    issue(inputs, definition, materials.run_definition, foreign_receipt)
    is Err(ForeignExport),
  )
  assert_eq(acquisitions.val, 1)
  assert_eq(consumers.val, 0)
  assert_true(owner.usage().held_bytes > 0L)
  // Physical stop does not return the retained reservation while producer
  // dependency borrows are outstanding. Repeating close cannot double-return.
  assert_false(owner.close())
  assert_false(owner.close())
  assert_true(owner.usage().held_bytes > 0L)
  assert_true(@strategy.release_captured_effect_local_unit_inputs(other_inputs))
  assert_true(@strategy.release_captured_effect_local_unit_inputs(inputs))
  assert_false(@strategy.release_captured_effect_local_unit_inputs(inputs))
  assert_true(
    @host.client_effect_local_result_payload_binding(
      artifact,
      materials.run_definition,
    )
    is Err(ForeignRun),
  )
  assert_true(
    @host.issue_client_effect_local_manifest(
      materials.prepared,
      @host.client_effect_acquired_invocation(source),
      [artifact],
      65536,
      4096,
      64,
    )
    is Err(ForeignArtifact),
  )
  assert_true(owner.close())
  assert_true(owner.close())
  assert_eq(owner.usage().held_bytes, 0L)
  assert_eq(owner.usage().reserved_retention_bytes, 0L)
  assert_eq(owner.usage().reserved_execution_bytes, 0L)
  assert_eq(acquisitions.val, 1)
  assert_eq(consumers.val, 0)
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_relation_export_receipt(foreign_receipt)
  @execution.cancel_completed_result_relation_export_preparation(preparation)
  assert_eq(root.inspect_generation(name).unwrap(), None)
  root.close()
}
