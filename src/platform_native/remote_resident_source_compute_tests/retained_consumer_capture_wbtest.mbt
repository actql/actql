///|
/// Read the actually completed holder's Effect proposal through its existing
/// pin/export Owners. No Source, task, provider Preview or write is invoked.
fn retained_holder_effect_capture(
  owner : @resident.ResidentRetainedConsumer,
  journal : @dispatch_journal.Journal,
) -> Unit raise {
  let computation = owner.effect_computation(journal).unwrap()
  let usage = computation.usage()
  assert_true(usage.held_bytes > 0L)
  let inputs = @strategy.pin_captured_effect_sources(
    computation.effect_run().unwrap(),
    4,
  ).unwrap()
  let plan = @strategy.prepare_captured_effect_proposal_plan(
    inputs, 0, 16, 10000,
  ).unwrap()
  let mut member_result = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if @strategy.captured_effect_local_result_matches_member(inputs, index, 0) {
      member_result = index
    }
  }
  assert_true(member_result >= 0)
  let exported = computation
    .prepare_effect_result_export(
      inputs,
      member_result,
      resident_compute_limits(),
    )
    .unwrap()
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  while !@execution.advance_completed_result_relation_export(preparation, 16).unwrap().0 {
    continue
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  let mut rows = 0
  while @execution.next_completed_output_export_canonical_row(
          stream, 100, 20, 100,
        ).unwrap()
        is Some((index, wire, row)) {
    assert_eq(wire, "[{\"id\":3}")
    let (selector, changes) = @strategy.project_captured_effect_proposal_row(
      plan, row, index, 16, 10000, 4096, 100, 20,
    ).unwrap()
    assert_eq(selector, "3")
    assert_eq(changes, "{\"state\":\"present\",\"value\":{\"Name\":3}}")
    rows += 1
  }
  let (receipt, end) = @execution.finish_completed_relation_export(stream).unwrap()
  assert_eq(end, "]")
  assert_eq(rows, 1)
  assert_true(
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ),
  )
  @strategy.finish_captured_effect_proposal_plan(plan, rows).unwrap()
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_output_export(stream)
  @execution.cancel_completed_result_relation_export(preparation) |> ignore
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  assert_true(
    physical_equal(owner.effect_computation(journal).unwrap(), computation),
  )
  assert_eq(computation.usage().held_bytes, usage.held_bytes)
  assert_eq(
    computation.usage().reserved_execution_bytes,
    usage.reserved_execution_bytes,
  )
}
