///|
// Actual completed Core Model/issuer/binding and identity scan. Physical
// provider and metadata funding are explicit component fixture inputs.
test "installed invocation binding keeps original Model outcomes distinct from its Result suffix" {
  for restored_input in [false, true] {
    let calls = Ref(0)
    let current = Ref(true)
    let released = Ref(false)
    let reenter : Ref[() -> Unit] = Ref(() => ())
    let source = infer_fixture_program
      .replace(
        old="\"as\":\"captured\"}],",
        new="\"as\":\"captured\"},{\"select\":[\"id\",\"outcome\"],\"as\":\"projected\"}],",
      )
      .replace(
        old="\"from\":\"captured\",\"fields\":[\"id\",\"outcome\",\"value\"]",
        new="\"from\":\"projected\",\"fields\":[\"id\",\"outcome\"]",
      )
    let (active, ledger, _) = original_observation_test_start(
      source~,
      provider=original_funded_start_provider(calls),
      restored_input~,
      restored_custody=() => {
        (reenter.val)()
        current.val
      },
    )
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
    if restored_input {
      // Use the existing actual entry/Scope/Account and persistence controls,
      // rather than disabling the restored constructor's durable-call gate.
      let (same, prepared, admission, prefix_work) = entry_gate_fixture(
        calls,
        Ref(evidence_account(@authorization.Allow)),
        Ref("2026-10-12T00:00:00.000Z"),
        Ref(Some(egress_fixture_observation())),
        start_original=Some(() => active),
        slots=1,
      )
      assert_true(physical_equal(same, active))
      bind_model_entry_persistence(active, prepared, admission, entry => {
        @model.model_call_entry_persistence(entry, prepared, () => {
          @model.Saved(
            @model.acknowledge_saved_model_call_entry(entry, prepared).unwrap(),
          )
        })
      }).unwrap()
      let mut poll = fixture_finish(active, initial_work=prefix_work)
      for _ in 0..<4 {
        if poll is AwaitIo(work~) {
          poll = fixture_finish(active, initial_work=work)
        }
      }
      let work = match poll {
        Settling(_, work~) => work
        _ => abort("restored original must retain its actual settlement")
      }
      assert_true(
        @model.acknowledge_model_call_settlement(
          call_settlement(active).unwrap(),
        ),
      )
      assert_true(fixture_finish(active, initial_work=work) is Complete(_, ..))
    } else {
      assert_true(fixture_finish(active) is Complete(_, ..))
    }
    let original = active.run_binding.unwrap()
    let capacity = reserve_original_infer_publication_capacity(
      active, 65664L, 7L,
    ).unwrap()
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
    if restored_input {
      // The live-only entrance must not silently become a Saved decoder.
      assert_true(
        borrow_original_live_model_relations(
          binding.output_use,
          original.compiled,
          original.definition,
          active.plan.unwrap(),
        )
        is None,
      )
    }
    let start = invocation_binding_original_model_identity_start_capacity(
      binding,
    ).unwrap()
    let outcomes = invocation_binding_original_model_outcomes(binding).unwrap()
    let filtered = invocation_binding_output(binding).unwrap()
    assert_eq(@relation.completed_column_count(outcomes), 3)
    assert_eq(@relation.completed_column_count(filtered), 2)
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
      65664L +
      retained +
      @relation.execution_capacity_retained_bytes(projecting),
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
    if restored_input {
      current.val = false
      assert_true(invocation_binding_original_model_outcomes(binding) is None)
      assert_true(
        invocation_binding_original_model_identity_start_capacity(binding)
        is None,
      )
      assert_true(original_local_model_observation_body(projected) is None)
      current.val = true
      assert_true(original_local_model_observation_body(projected) is Some(_))
      reenter.val = () => {
        reenter.val = () => ()
        released.val = release_invocation_binding(binding)
      }
      assert_true(
        invocation_binding_original_model_identity_start_capacity(binding)
        is None,
      )
      assert_true(released.val)
      reenter.val = () => ()
    } else {
      assert_true(release_invocation_binding(binding))
    }
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
}

///|
test "installed invocation observation refuses a foreign Saved scope with equal input data" {
  let calls = Ref(0)
  let (active, _, _) = original_observation_test_start(
    provider=original_funded_start_provider(calls),
  )
  assert_true(fixture_finish(active) is Complete(_, ..))
  assert_eq(calls.val, 1)
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
  let foreign_prepared = fixture_prepared()
  let foreign_plan = call_identity_plan(foreign_prepared)
  let (foreign_compiled, foreign_definition) = original_input_capacity_run(
    foreign_prepared, foreign_plan,
  )
  let (foreign_occurrence, _) = original_composed_test_input(foreign_prepared)
  let (foreign_saved, _) = original_restored_composed_test_saved(
    foreign_prepared,
    foreign_compiled,
    foreign_definition,
    foreign_occurrence,
    foreign_plan,
    () => true,
  )
  assert_true(active.saved_call_scope is None)
  // Whitebox fault only: a genuinely issued scope from another checked Run
  // has equal authored input rows. Neither those values nor Some(Saved) can
  // replace this actual execution's original scope/occurrence/Plan.
  active.saved_call_scope = Some(foreign_saved)
  assert_true(invocation_binding_original_model_outcomes(binding) is None)
  assert_true(
    invocation_binding_original_model_identity_start_capacity(binding) is None,
  )
  active.saved_call_scope = None
  assert_true(invocation_binding_original_model_outcomes(binding) is Some(_))
  assert_true(
    invocation_binding_original_model_identity_start_capacity(binding)
    is Some(_),
  )
  assert_eq(calls.val, 1, msg="no Model re-execution or replacement output")
  assert_true(release_invocation_binding(binding))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}
