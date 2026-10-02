///|
fn publication_result_limits() -> @publication_host.PublicationOutputExportLimits {
  let wire : @relation.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 64,
  }
  {
    max_result_fields: 10,
    max_result_mapping_work: 10000,
    max_result_order_work: 10000,
    max_result_workspace_entries: 1000,
    max_rows: 10,
    values: {
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_depth: 64,
      max_work: 10000,
    },
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 64,
    },
    max_batch_bytes: 10000,
  }
}

///|
test "checked Infer Result exports keep independent Invocation and output custody" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  assert_eq(
    @publication_host.prepared_client_terminal_infer_step(active.prepared),
    Some(2),
  )
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let bound = active.run_binding.unwrap()
  let issued = start_observation_issuance(
    active,
    issuance_ledger(65664L),
    issuance_limits(),
  ).unwrap()
  issuance_finish(issued)
  let binding = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  let first = start_result_publication(binding, 0, publication_result_limits()).unwrap()
  let second = start_result_publication(binding, 0, publication_result_limits()).unwrap()
  assert_true(release_invocation_binding(binding))
  assert_true(!cleanup(active).unwrap())
  assert_true(!cleanup_observation_issuance(issued).unwrap())
  for publication in [first, second] {
    let selection = result_publication_selection(publication).unwrap()
    assert_eq(
      @publication_host.client_result_transformation_name(selection),
      "answer",
    )
    assert_eq(@publication_host.client_result_transformation_task(selection), 0)
    let expected = @publication.prepare_result_definition(
      @publication_host.prepared_client_identity(active.prepared).program_definition_cid,
      "answer",
    ).unwrap()
    assert_eq(
      @publication.publication_contract_identity(
        @publication_host.client_result_transformation_definition(selection),
      ),
      @publication.publication_contract_identity(
        @publication.result_definition_contract(expected),
      ),
    )
    let mut complete = false
    for _ in 0..<1000 {
      let (done, work) = advance_result_publication(publication, 1).unwrap()
      assert_true(work <= 1)
      if done {
        complete = true
        break
      }
    }
    assert_true(complete)
    let exported = finish_result_publication(publication).unwrap()
    assert_true(
      physical_equal(finish_result_publication(publication).unwrap(), exported),
    )
    let mut wire = ""
    while exported.next().unwrap() is Some(chunk) {
      wire += chunk
    }
    wire += exported.finish().unwrap()
    assert_eq(
      wire, "[{\"id\":\"a\",\"outcome\":\"failed:timeout\",\"value\":null}]",
    )
  }
  assert_true(release_result_publication(first))
  assert_true(!release_result_publication(first))
  assert_true(result_publication_selection(first) is None)
  assert_true(result_publication_selection(second) is Some(_))
  assert_true(!cleanup_observation_issuance(issued).unwrap())
  assert_true(!cleanup(active).unwrap())
  assert_true(release_result_publication(second))
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "Infer Result selection and cancellation do not invent a task or release another consumer" {
  let calls = Ref(0)
  let active = failed_outcome_start(@model.Timeout, calls)
  evidence_authorize(active)
  assert_true(fixture_finish(active) is Complete(_, ..))
  let bound = active.run_binding.unwrap()
  let issued = start_observation_issuance(
    active,
    issuance_ledger(65664L),
    issuance_limits(),
  ).unwrap()
  issuance_finish(issued)
  let binding = bind_issued_invocation(
    active,
    bound.compiled,
    bound.definition,
    issued,
  ).unwrap()
  let uses = issued.uses
  assert_true(
    start_result_publication(binding, 1, publication_result_limits())
    is Err(Transformation(@publication_host.MissingResult)),
  )
  assert_eq(issued.uses, uses)
  let limited = start_result_publication(binding, 0, {
    ..publication_result_limits(),
    max_result_mapping_work: 0,
  })
  if limited is Ok(publication) {
    assert_true(
      advance_result_publication(publication, 1) is Err(Transformation(_)),
    )
    assert_true(release_result_publication(publication))
  } else {
    assert_true(limited is Err(Transformation(_)))
  }
  assert_eq(issued.uses, uses)
  let pending = start_result_publication(
    binding,
    0,
    publication_result_limits(),
  ).unwrap()
  assert_true(!advance_result_publication(pending, 1).unwrap().0)
  assert_true(cancel_result_publication(pending))
  assert_true(finish_result_publication(pending) is Err(InvalidState))
  assert_true(advance_result_publication(pending, 1) is Err(InvalidState))
  assert_true(invocation_binding_output(binding) is Some(_))
  assert_true(!cleanup(active).unwrap())
  assert_true(release_result_publication(pending))
  assert_true(release_invocation_binding(binding))
  assert_true(
    start_result_publication(binding, 0, publication_result_limits())
    is Err(InvalidState),
  )
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}
