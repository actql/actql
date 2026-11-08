///|
// Actual completed Model/Read/issuer and bounded logical export. Allowances
// are explicit fixture grants, not installed Native or Store acceptance.
fn local_model_observation_test_export(
  output : @relation.CompletedOutput,
) -> @relation.CompletedRelationExportReceipt {
  let wire : @relation.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let scan = @relation.start_completed_relation_identity_scan(
    output,
    10,
    standard_limits().output_values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    100000,
    10000,
  ).unwrap()
  while !@relation.advance_completed_relation_identity_scan(scan, 1).unwrap().0 {
    ()
  }
  @relation.finish_completed_relation_identity_scan(scan).unwrap()
}

///|
test "local Model semantic projection preserves non-success outcomes across distinct Run audit identities" {
  let source = infer_fixture_program.replace(
    old="[{\"id\":\"a\",\"text\":\"hello\"}]",
    new="[{\"id\":\"a\",\"text\":\"hello\"},{\"id\":\"b\",\"text\":\"second\"}]",
  )
  let local_cids : Array[String] = []
  let audit_cids : Array[String] = []
  for run_id in ["first-local-model", "second-local-model"] {
    let calls = Ref(0)
    let provider = @model.install_model_provider("models/fixture", request => {
      calls.val += 1
      if request.slot == 0 {
        Err(@model.Refusal)
      } else {
        Ok({
          value: @admitted.object_value([
            ("reason", @admitted.null_value()),
            ("risk", @admitted.text_value("high", 100).unwrap()),
          ]).unwrap(),
          provider_model: "fixture",
          provider_request_id: run_id,
          input_tokens: 1L,
          output_tokens: 2L,
          observed_at: "2026-10-02T00:00:00.000Z",
        })
      }
    }).unwrap()
    let (active, _, _) = original_observation_test_start(
      source~,
      provider~,
      run_id~,
    )
    assert_true(fixture_finish(active) is Complete(_, ..))
    assert_eq(calls.val, 2)
    let held = acquire_output(active).unwrap()
    let binding = active.run_binding.unwrap()
    let (input, outcomes) = borrow_original_live_model_relations(
      held,
      binding.compiled,
      binding.definition,
      active.plan.unwrap(),
    ).unwrap()
    assert_eq(@relation.completed_row_count(outcomes), 2)
    assert_true(
      @relation.completed_cell(outcomes, 0, 1)
      is Some(@relation.Text("failed:refusal")),
    )
    assert_true(
      @relation.completed_cell(outcomes, 1, 1) is Some(@relation.Text("ok")),
    )
    let input_receipt = local_model_observation_test_export(input)
    let outcome_receipt = local_model_observation_test_export(outcomes)
    // This independent semantic case uses the existing explicit metadata
    // fixture grant. Two physical outcomes already consume the original test
    // Model's retention allowance. The separate test below exercises actual
    // same-parent publication borrowing; this is not its capacity evidence.
    let issued = start_observation_issuance(
      active,
      issuance_ledger(65792L),
      issuance_limits(),
    ).unwrap()
    issuance_finish(issued)
    let (audit, _) = observation_issuance_value(issued).unwrap()
    audit_cids.push(@publication.run_evidence_value_identity(audit))
    let projected = issue_original_local_model_observation(
      held, issued, input_receipt, outcome_receipt, 4096, 1024, 20,
    ).unwrap()
    local_cids.push(
      @publication.captured_effect_dependency_body_cid(
        original_local_model_observation_body(projected).unwrap(),
      ),
    )
    assert_eq(calls.val, 2)
    assert_true(release_output(held))
    assert_true(original_local_model_observation_body(projected) is None)
    @relation.cancel_completed_relation_export_receipt(input_receipt)
    @relation.cancel_completed_relation_export_receipt(outcome_receipt)
    assert_true(cleanup_observation_issuance(issued).unwrap())
    assert_true(cleanup(active).unwrap())
  }
  assert_eq(local_cids[0], local_cids[1])
  assert_not_eq(audit_cids[0], audit_cids[1])
}

///|
test "local Model observation binds original complete relations before Result suffix and retires with its issuer" {
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
  let held = acquire_output(active).unwrap()
  let binding = active.run_binding.unwrap()
  let (input, outcomes) = borrow_original_live_model_relations(
    held,
    binding.compiled,
    binding.definition,
    active.plan.unwrap(),
  ).unwrap()
  assert_eq(@relation.completed_column_count(output(held).unwrap()), 2)
  assert_eq(@relation.completed_column_count(outcomes), 3)
  let input_receipt = local_model_observation_test_export(input)
  let outcome_receipt = local_model_observation_test_export(outcomes)
  let filtered_receipt = local_model_observation_test_export(
    output(held).unwrap(),
  )
  let capacity = reserve_original_infer_publication_capacity(active, 65664L, 7L).unwrap()
  let issued = start_original_observation_issuance(
    active,
    capacity,
    issuance_limits(),
  ).unwrap()
  assert_true(
    issue_original_local_model_observation(
      held, issued, input_receipt, outcome_receipt, 4096, 1024, 20,
    )
    is None,
  )
  issuance_finish(issued)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    issue_original_local_model_observation(
      held, issued, input_receipt, filtered_receipt, 4096, 1024, 20,
    )
    is None,
  )
  assert_true(
    issue_original_local_model_observation(
      held, issued, outcome_receipt, input_receipt, 4096, 1024, 20,
    )
    is None,
  )
  let observation = issue_original_local_model_observation(
    held, issued, input_receipt, outcome_receipt, 4096, 1024, 20,
  ).unwrap()
  let body = original_local_model_observation_body(observation).unwrap()
  let reused = issue_original_local_model_observation_from_scope(
    held, issued, outcome_receipt, 4096, 1024, 20,
  ).unwrap()
  assert_eq(
    @publication.captured_effect_dependency_body_json(
      original_local_model_observation_body(reused).unwrap(),
    ),
    @publication.captured_effect_dependency_body_json(body),
  )
  assert_true(
    issue_original_local_model_observation_from_scope(
      held, issued, filtered_receipt, 4096, 1024, 20,
    )
    is None,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_kind(body),
    "local_model_observation",
  )
  assert_false(
    @publication.captured_effect_dependency_body_json(body).contains(
      "program_definition_cid",
    ),
  )
  assert_false(
    @publication.captured_effect_dependency_body_json(body).contains(
      "observation_set_cid",
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Same semantic bytes do not transfer the original output/issuer custody.
  let (foreign, _, _) = original_observation_test_start(source~)
  assert_true(fixture_finish(foreign) is Complete(_, ..))
  let foreign_use = acquire_output(foreign).unwrap()
  assert_true(
    issue_original_local_model_observation(
      foreign_use, issued, input_receipt, outcome_receipt, 4096, 1024, 20,
    )
    is None,
  )
  assert_true(release_output(foreign_use))
  assert_true(cleanup(foreign).unwrap())
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(original_local_model_observation_body(observation) is None)
  @relation.cancel_completed_relation_export_receipt(input_receipt)
  @relation.cancel_completed_relation_export_receipt(outcome_receipt)
  @relation.cancel_completed_relation_export_receipt(filtered_receipt)
  assert_true(release_output(held))
  assert_false(@relation.completed_output_available(input))
  assert_false(@relation.completed_output_available(outcomes))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}
