///|
fn row_bound_pipeline(rows : String) -> @pipeline.CheckedPipeline {
  @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"},{\"drop\":[]}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
test "automatic values count reserves independently measured complete artifacts" {
  let pipeline = row_bound_pipeline("[{\"id\":1},{\"id\":1},{\"id\":2}]")
  // Independent canonical JSON accounting: proof 7 nodes, complete witness
  // 15 nodes; their combined UTF-8 encoding is 606 bytes. Not a counter delta
  // from a previous product run. Duplicates remain three authored rows.
  let caps : @wire.Limits = { max_bytes: 606, max_nodes: 22, max_depth: 10, }
  let result = prepare_values_row_bound(pipeline, 0, caps).unwrap()
  assert_eq(result.metadata_bytes, 606)
  assert_eq(result.metadata_nodes, 22)
  assert_true(physical_equal(@program.checked_pipeline(result.bound), pipeline))
  assert_eq(@program.checked_step(result.bound), 0)
  let witness = @wire.program_proof_witness(
    @program.checked_proof(result.bound),
  )
  assert_eq(@wire.value(witness), 3L)
  assert_eq(
    @wire.cid(witness),
    "sha256:4eeab1520aae127f1de078042f0ec9a4dd9d9841e6b78cf3dbfd23ba7f727554",
  )
  for
    short in [
      { ..caps, max_bytes: 605, },
      { ..caps, max_nodes: 21, },
      { ..caps, max_depth: 0, },
      { ..caps, max_bytes: -1, },
    ] {
    assert_true(prepare_values_row_bound(pipeline, 0, short) is Err(_))
  }
  // Same wire identity is not an application owner. Each construction applies
  // the proof to its own checked operation and retains that exact owner.
  let other = row_bound_pipeline("[{\"id\":3},{\"id\":4},{\"id\":5}]")
  let again = prepare_values_row_bound(other, 0, caps).unwrap()
  assert_false(physical_equal(@program.checked_pipeline(again.bound), pipeline))
  assert_true(physical_equal(@program.checked_pipeline(again.bound), other))
  assert_eq(
    @wire.cid(@wire.program_proof_witness(@program.checked_proof(again.bound))),
    @wire.cid(witness),
  )
}

///|
test "automatic values count rejects unrelated steps and retains empty cardinality" {
  let pipeline = row_bound_pipeline("[]")
  let caps : @wire.Limits = { max_bytes: 606, max_nodes: 22, max_depth: 10, }
  let result = prepare_values_row_bound(pipeline, 0, caps).unwrap()
  assert_eq(
    @wire.value(
      @wire.program_proof_witness(@program.checked_proof(result.bound)),
    ),
    0L,
  )
  for step in [-1, 1, 2] {
    assert_true(
      prepare_values_row_bound(pipeline, step, caps) is Err(InvalidOwner),
    )
  }
}
