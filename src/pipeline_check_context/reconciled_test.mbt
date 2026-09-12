///|
test "schema-aware registrations connect all stages and actual Result imports" {
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(true)
  let snapshots = evidence.unwrap()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let result = attach_reconciled_inputs(
    wired,
    snapshots,
    locals,
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  assert_true(physical_equal(reconciled_wiring(result), wired))
  assert_true(physical_equal(reconciled_snapshots(result), snapshots))
  assert_true(reconciled_sourceviews(result) is None)
  assert_true(reconciled_sourceview_stage(result, 0) is None)
  for i in 0..<2 {
    assert_true(
      physical_equal(reconciled_local_at(result, i).unwrap(), locals[i]),
    )
  }
  let used = reconciled_usage(result)
  let source = @local_inputs.environment_program(snapshots)
  let second = @local_inputs.program_environment_stage(snapshots, 1).unwrap()
  let repeated = @local_inputs.reconcile_environment(
    @local_inputs.snapshot_inputs(@local_inputs.environment_assertions(second)),
    @refs.prepare(source, { max_work: 100000, max_text_bytes: 100000, }).unwrap(),
    @local_inputs.program_environment(snapshots),
    [],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  let alternative = @local_inputs.assemble_environment(
    source,
    @local_inputs.program_environment(snapshots),
    [@local_inputs.program_environment_stage(snapshots, 0).unwrap(), repeated],
    {
      max_work: 100000,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    },
  ).unwrap()
  assert_true(
    attach_reconciled_inputs(
      wired,
      alternative,
      locals,
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignEvidence(1)),
  )
  let evidence_cost = @local_inputs.program_environment_usage(snapshots)
  let (w, t) = wired_usage(wired)
  let mut additional = 2
  for i in 0..<2 {
    additional += @local_inputs.reconciled_work(locals[i]) -
      @stages.collection_work(@local_inputs.reconciled_stage(locals[i])) -
      @local_inputs.environment_usage(
        @local_inputs.reconciled_inputs(locals[i]),
      ).work
  }
  assert_eq(used, {
    work: w + evidence_cost.work + additional,
    text_bytes: t + evidence_cost.text_bytes,
    local_input_nodes: evidence_cost.nodes,
  })
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Ok(_),
  )
  for
    (work, text, nodes) in [
      (used.work - 1, used.text_bytes, used.local_input_nodes),
      (used.work, used.text_bytes - 1, used.local_input_nodes),
      (used.work, used.text_bytes, used.local_input_nodes - 1),
    ] {
    assert_true(
      attach_reconciled_inputs(
        wired,
        snapshots,
        locals,
        max_work=work,
        max_text_bytes=text,
        max_local_input_nodes=nodes,
      )
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      max_work=-1,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      [locals[0]],
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(StageCount),
  )
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      [locals[1], locals[0]],
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignStage(0)),
  )
  let (_, _, _, _, foreign, foreign_evidence) = wired_inputs_fixture(true)
  assert_true(
    attach_reconciled_inputs(
      wired,
      foreign_evidence.unwrap(),
      foreign,
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignProgram),
  )
  let first = locals[0]
  locals.clear()
  assert_true(physical_equal(reconciled_local_at(result, 0).unwrap(), first))
  assert_true(reconciled_local_at(result, -1) is None)
  assert_true(reconciled_local_at(result, 2) is None)
}
