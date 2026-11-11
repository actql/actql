///|
// Actual completed Core Model/issuer/binding and identity scan. Physical
// provider and metadata funding are explicit component fixture inputs.
test "installed invocation binding keeps original Model outcomes distinct from its Result suffix" {
  let source = infer_fixture_program
    .replace(
      old="\"as\":\"captured\"}],",
      new="\"as\":\"captured\"},{\"select\":[\"id\",\"outcome\"],\"as\":\"projected\"}],",
    )
    .replace(
      old="\"from\":\"captured\",\"fields\":[\"id\",\"outcome\",\"value\"]",
      new="\"from\":\"projected\",\"fields\":[\"id\",\"outcome\"]",
    )
  let (active, ledger, _) = original_observation_test_start(source~)
  let sequence = @input.prepare_client_local_sequences(
      active.occurrence.owner,
      infer_fixture_installed_contracts(),
      infer_fixture_values,
      None,
      None,
    ).unwrap()[0]
  let (_, _, step) = @publication_host.client_infer_occurrence_coordinates(
    active.occurrence,
  )
  let last = @publication_host.client_infer_occurrence_output_step(
    active.occurrence,
  ).unwrap()
  bind_compute_suffix(
    active,
    @relation.select_generated_sequence_range(sequence, step + 1, last).unwrap(),
  ).unwrap()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let original = active.run_binding.unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  issuance_finish(issued)
  let binding = bind_issued_invocation(
    active,
    original.compiled,
    original.definition,
    issued,
  ).unwrap()
  let outcomes = invocation_binding_original_model_outcomes(binding).unwrap()
  let filtered = invocation_binding_output(binding).unwrap()
  assert_eq(@relation.completed_column_count(outcomes), 3)
  assert_eq(@relation.completed_column_count(filtered), 2)
  let start = invocation_binding_original_model_identity_start_capacity(binding).unwrap()
  let mut retained = @relation.execution_capacity_retained_bytes(start)
  let mut workspace = @relation.execution_capacity_execution_bytes(start)
  grow_original_infer_publication_capacity(
    active,
    capacity,
    65664L + retained,
    7L + workspace,
  ).unwrap()
  let scan = start_invocation_binding_original_model_identity(binding).unwrap()
  let mut done = false
  for _ in 0..<100000 {
    let next = @relation.completed_relation_identity_scan_next_construction_capacity(
      scan,
    ).unwrap()
    let next_retained = @relation.execution_capacity_retained_bytes(next)
    let next_workspace = @relation.execution_capacity_execution_bytes(next)
    if next_retained > retained || next_workspace > workspace {
      retained = Int64::max(retained, next_retained)
      workspace = Int64::max(workspace, next_workspace)
      grow_original_infer_publication_capacity(
        active,
        capacity,
        65664L + retained,
        7L + workspace,
      ).unwrap()
    }
    if @relation.advance_completed_relation_identity_scan(
        scan,
        1,
        construction_capacity=Some(next),
      ).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let receipt = @relation.finish_completed_relation_identity_scan(scan).unwrap()
  assert_true(
    @relation.completed_relation_identity_scan_body(scan, receipt) is Some(_),
  )
  let projecting = invocation_binding_original_model_observation_capacity(
    binding, receipt, 4096,
  ).unwrap()
  grow_original_infer_publication_capacity(
    active,
    capacity,
    65664L + retained + @relation.execution_capacity_retained_bytes(projecting),
    7L + workspace + @relation.execution_capacity_execution_bytes(projecting),
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let filtered_receipt = local_model_observation_test_export(filtered)
  assert_true(
    issue_invocation_binding_original_model_observation(
      binding, filtered_receipt, 4096, 1024, 20,
    )
    is None,
  )
  let projected = issue_invocation_binding_original_model_observation(
    binding, receipt, 4096, 1024, 20,
  ).unwrap()
  let body = original_local_model_observation_body(projected).unwrap()
  assert_eq(
    @publication.captured_effect_dependency_body_kind(body),
    "local_model_observation",
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // The completed projection retains semantic metadata with this binding,
  // not a new row borrower. Retire the export cursor/receipt while preserving
  // the actual original output/issuer and its charged publication lifetime.
  @relation.cancel_completed_relation_export_receipt(receipt)
  @relation.cancel_completed_relation_identity_scan(scan) |> ignore
  assert_true(original_local_model_observation_body(projected) is Some(_))
  assert_true(release_invocation_binding(binding))
  assert_true(invocation_binding_original_model_outcomes(binding) is None)
  assert_true(original_local_model_observation_body(projected) is None)
  assert_true(
    issue_invocation_binding_original_model_observation(
      binding, receipt, 4096, 1024, 20,
    )
    is None,
  )
  @relation.cancel_completed_relation_export_receipt(filtered_receipt)
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}
