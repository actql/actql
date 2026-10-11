///|
fn retry_export() -> PublicationOutputExport {
  let prepared = input_result_prepared(run_materials_document)
  let contracts = @execution.admit_relation_registry(
    parse_plan_identity_value(
      compiler_registered_body_wire(),
      1000000,
      100000,
      100,
    ).unwrap(),
    parse_plan_identity_value(
      compiler_registered_values_wire(),
      1000000,
      100000,
      100,
    ).unwrap(),
    { max_body_bytes: 1000000, max_body_nodes: 100000, max_body_depth: 100, },
  ).unwrap()
  let sequence = prepare_client_task_sequence(
    prepared,
    0,
    contracts,
    [],
    run_materials_limits().sequence,
    10000,
    10000,
  ).unwrap()
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let completed = @execution.execute_generated_sequence(sequence, [], {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let parent = prepare_publication_output_export(output, {
    max_result_fields: 10,
    max_result_mapping_work: 10000,
    max_result_order_work: 10000,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values,
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
    },
    max_batch_bytes: 10000,
  }).unwrap()
  let definition = client_result_transformation_definition(
    prepare_client_result_transformation(prepared, 0, 100000, 10000, 100).unwrap(),
  )
  { ..parent, definition: Some(definition), }
}

///|
test "publication retry counterexample preserves the parent after one work and cancel" {
  let parent = retry_export()
  while parent.next().unwrap() is Some(_) {

  }
  parent.finish().unwrap() |> ignore
  let cid = fn(ch : String) { "sha256:" + ch.repeat(64) }
  let issue = fn() {
    parent.issue_result_evidence(
      cid("1"),
      [cid("2")],
      cid("3"),
      cid("4"),
      cid("5"),
      100000,
      10000,
      100,
    )
  }
  issue().unwrap()
  let invocation = @publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"" +
    cid("6") +
    "\",\"observation_set_cid\":\"" +
    cid("7") +
    "\"}",
    100000,
    10000,
    100,
  ).unwrap()
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    cid("8") +
    "\",\"effective_data_policy_cid\":\"" +
    cid("4") +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    cid("9") +
    "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"" +
    cid("a") +
    "\"}",
    100000,
    10000,
    100,
  ).unwrap()
  let artifact = parent
    .issue_artifact(invocation, retention, 100000, 10000, 100)
    .unwrap()
  let receipt = parent.receipt.unwrap()
  let before = parent.content_identity().unwrap()
  let snapshot = parent.start_captured_snapshot(100000, 10000, 100).unwrap()
  assert_eq(snapshot.advance(1).unwrap(), (false, 1))
  snapshot.cancel()
  snapshot.cancel()
  assert_true(@execution.completed_relation_export_receipt_live(receipt))
  assert_true(physical_equal(parent.receipt.unwrap(), receipt))
  assert_true(physical_equal(parent.artifact.unwrap(), artifact))
  assert_eq(parent.content_identity().unwrap(), before)
  // The completed parent is live. Its already-issued evidence is one-shot:
  // a new adapter handle must borrow the issued projection, not issue again.
  let second_issue = issue()
  assert_true(second_issue is Err(InvalidState))
  assert_true(
    parent.issue_artifact(invocation, retention, 100000, 10000, 100)
    is Err(InvalidState),
  )
  println("publication retry: parent_live=true; repeated_evidence=InvalidState")
  let replay = parent.replay().unwrap()
  let mut bytes = ""
  while replay.next().unwrap() is Some(chunk) {
    bytes += chunk
  }
  bytes += replay.finish().unwrap()
  assert_eq(bytes, "[{\"id\":1},{\"id\":2}]")
  parent.cancel()
  assert_false(@execution.completed_relation_export_receipt_live(receipt))
}
