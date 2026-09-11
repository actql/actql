///|
test "all local stage inputs join Result wiring under exact shared owners and budgets" {
  let (stages, wiring, _, locals) = wired_fixture()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let joined = attach_local_inputs(
    wired,
    locals,
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=10000,
  ).unwrap()
  assert_true(physical_equal(input_wiring(joined), wired))
  assert_true(physical_equal(local_inputs_at(joined, 0).unwrap(), locals[0]))
  let used = input_usage(joined)
  let (prior_work, prior_text) = wired_usage(wired)
  let mut work = prior_work
  let mut text = prior_text
  let mut nodes = 0
  for attached in locals {
    let u = @local_inputs.usage(@local_inputs.attached_inputs(attached))
    work += 1 +
      @local_inputs.attached_work(attached) -
      @stages.collection_work(@local_inputs.attached_stage(attached))
    text += u.text_bytes
    nodes += u.nodes
  }
  assert_eq(used, { work, text_bytes: text, local_input_nodes: nodes, })
  assert_true(
    attach_local_inputs(
      wired,
      locals,
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Ok(_),
  )
  assert_true(
    attach_local_inputs(
      wired,
      locals,
      max_work=used.work - 1,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(BudgetExceeded(1)),
  )
  assert_true(
    attach_local_inputs(
      wired,
      locals,
      max_work=used.work,
      max_text_bytes=used.text_bytes - 1,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(BudgetExceeded(0)),
  )
  assert_true(
    attach_local_inputs(
      wired,
      locals,
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes - 1,
    )
    is Err(BudgetExceeded(0)),
  )
  assert_true(
    attach_local_inputs(
      wired,
      [locals[0]],
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(StageCount),
  )
  assert_true(
    attach_local_inputs(
      wired,
      [locals[1], locals[0]],
      max_work=used.work,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(ForeignStage(0)),
  )
  for
    (w, t, n) in [
      (-1, 1000000, 10000),
      (1000000, -1, 10000),
      (1000000, 1000000, -1),
    ] {
    assert_true(
      attach_local_inputs(
        wired,
        locals,
        max_work=w,
        max_text_bytes=t,
        max_local_input_nodes=n,
      )
      is Err(InvalidLimits),
    )
  }
  let (_, _, _, other) = wired_fixture()
  let second = @local_inputs.attached_stage(locals[1])
  let repeated_collection = @stages.collect(
    @stages.source(second),
    1,
    @parameter_slots.pipeline(@stages.collection(second)),
    {
      max_work: 10000,
      max_slots: 100,
      max_references: 100,
      max_pointer_units: 10000,
      max_direct_text_bytes: 10000,
    },
  ).unwrap()
  let repeated_attachment = @local_inputs.attach(
    @local_inputs.attached_inputs(locals[1]),
    repeated_collection,
    max_work=100000,
  ).unwrap()
  assert_true(
    attach_local_inputs(
      wired,
      [locals[0], repeated_attachment],
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=10000,
    )
    is Err(ForeignStage(1)),
  )
  assert_true(
    attach_local_inputs(
      wired,
      [locals[0], other[1]],
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=10000,
    )
    is Err(ForeignStage(1)),
  )
  let first = locals[0]
  locals.clear()
  assert_true(physical_equal(local_inputs_at(joined, 0).unwrap(), first))
  assert_true(local_inputs_at(joined, -1) is None)
  assert_true(local_inputs_at(joined, 2) is None)
}
