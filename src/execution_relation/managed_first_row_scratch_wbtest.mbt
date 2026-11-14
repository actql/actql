///|
test "first managed scratch row has no previous admission-owned row backing" {
  let growth = {
    ..working_growth_fixture(_ => Ok(())),
    live_ceiling: 1048576L,
    retained_outputs: Some(0L),
    reserve_retained: Some((_, retained) => {
      if retained > 5111L {
        Err(WorkspaceBudgetUnavailable)
      } else {
        Ok(())
      }
    }),
  }
  let original = funded_row_output(growth)
  let cell = funded_row_number(original, 1.0)
  append_admitted_output(original, [cell]).unwrap()
  let stream = metered_managed_scratch_stream(original, growth, 2)
  assert_eq(stream.buffer.rows.capacity(), 0)
  assert_eq(stream.buffer.presence_rows.capacity(), 0)
  assert_eq(stream.buffer.budget.row_scratch_start, Some((0, 0)))
  assert_eq(stream.buffer.budget.retention_funded, 0L)
  append_managed_output_values(stream, 1, _ => Some(cell)).unwrap()
  assert_eq(growth.retained_outputs, Some(4376L + 528L))
  assert_eq(stream.buffer.budget.retention_funded, 528L)
  assert_eq(original.buffer.rows.length(), 1)
  assert_eq(original.buffer.budget.retention_funded, 528L)
  // The next row can overlap the first row's retained Native array backing.
  // Its second row allowance is mandatory, and this exact quota refuses it.
  assert_true(
    append_managed_output_values(stream, 1, _ => Some(cell))
    is Err(Admission(CaptureLimit)),
  )
  assert_true(growth.failed)
  assert_true(finish_managed_output_values(stream) is Err(Closed))
  assert_eq(growth.retained_outputs, Some(4904L))
  request_managed_output_values_disposal(stream)
  while !advance_managed_output_values_reclamation(stream, 1) {

  }
  assert_true(managed_output_values_scratch_released(stream))
  assert_eq(growth.retained_outputs, Some(4904L))
  assert_eq(original.buffer.rows.length(), 1)
}

///|
test "first row scratch composes the observed import prefix on the unchanged one GiB reservation" {
  // Exact first-row scalar geometry from the fresh instrumented e6c run.
  // This tests the original reservation callback protocol, not heap/RSS or a
  // physical Resource allocator, and does not credit any imported payload.
  let imported = 672981712L
  let initial_task = 14972304L
  let requests : Array[(Int64, Int64)] = []
  let growth = {
    ..working_growth_fixture(_ => abort("retained callback required")),
    live_ceiling: 1073741824L,
    initial_slots: 10000,
    initial_live: 0L,
    slots: 1054,
    logical: 0L,
    text: 6480L,
    text_peak: 6480L,
    slot_peak: 1843,
    logical_peak: 128053L,
    funded: 169656320L,
    used: 169654760L,
    retained_funded: 135856128L,
    retained_outputs: Some(135842288L),
    reserve_retained: Some((execution, retained) => {
      requests.push((execution, retained))
      if execution + imported + initial_task > 1073741824L ||
        retained > 1073741824L {
        Err(WorkspaceBudgetUnavailable)
      } else {
        Ok(())
      }
    }),
  }
  let budget = value_budget({
    max_nodes: 271,
    max_text_bytes: 100000000,
    max_work: 100000000,
    max_depth: 100,
  }).unwrap()
  budget.retention = Some(growth)
  budget.nodes = 264
  budget.text = 16832942
  budget.work = 16833206
  budget.row_scratch_start = Some((0, 0))
  assert_true(fund_output_retention(budget, budget.nodes, budget.text))
  assert_eq(budget.retention_funded, 134731120L)
  assert_eq(growth.retained_outputs, Some(135842288L + 134731120L))
  assert_true(!growth.failed && !growth.busy)
  assert_eq(requests.length(), 1)
  assert_true(requests[0].0 + imported + initial_task <= 1073741824L)
  assert_eq((budget.nodes, budget.text, budget.work), (264, 16832942, 16833206))
}
