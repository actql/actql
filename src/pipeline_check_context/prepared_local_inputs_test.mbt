///|
test "prepared Local input integration retains the wiring's Environment registrations" {
  let (_, wiring, integrated) = prepared_identity_fixture(third_stage=true)
  let wired = reconciled_wiring(integrated)
  let snapshots = @stage_results.wiring_local_environment(wiring).unwrap()
  assert_true(physical_equal(reconciled_snapshots(integrated), snapshots))
  let locals = []
  for i in 0..<3 {
    let original = @stage_results.wiring_reconciled_input_at(wiring, i).unwrap()
    assert_true(
      physical_equal(reconciled_local_at(integrated, i).unwrap(), original),
    )
    locals.push(original)
  }
  let used = reconciled_usage(integrated)
  let manual = attach_reconciled_inputs(
    wired,
    snapshots,
    locals,
    max_work=used.work,
    max_text_bytes=used.text_bytes,
    max_local_input_nodes=used.local_input_nodes,
  ).unwrap()
  assert_eq(used.work, reconciled_usage(manual).work + 3)
  assert_true(
    attach_prepared_local_inputs(
      wired,
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
      attach_prepared_local_inputs(
        wired,
        max_work=work,
        max_text_bytes=text,
        max_local_input_nodes=nodes,
      )
      is Err(_),
    )
  }
  assert_true(
    attach_prepared_local_inputs(
      wired,
      max_work=-1,
      max_text_bytes=used.text_bytes,
      max_local_input_nodes=used.local_input_nodes,
    )
    is Err(InvalidLimits),
  )
}

///|
test "source-only wiring cannot substitute for prepared Environment registrations" {
  let (stages, wiring, _, _, _, _) = prepared_local_context_fixture()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  assert_true(
    attach_prepared_local_inputs(
      wired,
      max_work=10000000,
      max_text_bytes=10000000,
      max_local_input_nodes=1000000,
    )
    is Err(MissingEnvironment),
  )
}
