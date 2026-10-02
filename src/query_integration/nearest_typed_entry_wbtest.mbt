///|
// The retained Relation/Relation entry uses the same typed producer route as
// mixed Carrier nearest. It has no separate completion or lifecycle owner.
test "typed nearest Relation entry preserves values limits and exact custody" {
  let candidates = direct_nearest_relation_owner(
    "[{\"id\":1,\"embedding\":[1,0]}]",
  )
  let queries = direct_nearest_relation_owner(
    "[{\"id\":10,\"embedding\":[1,0]}]",
  )
  let owner = direct_nearest_owner(
    candidates,
    queries,
    candidate_relation=true,
    query_relation=true,
  )
  let candidate_output = direct_nearest_relation_output(candidates)
  let query_output = direct_nearest_relation_output(queries)
  let candidate_binding = @execution.bind_completed_input(
    owner, 0, candidates, candidate_output,
  ).unwrap()
  let query_binding = @execution.bind_completed_input(
    owner, 1, queries, query_output,
  ).unwrap()
  let candidate_read = @execution.prepare_producer_read(
    owner, candidate_binding, 10, 1000,
  ).unwrap()
  let query_read = @execution.prepare_producer_read(
    owner, query_binding, 10, 1000,
  ).unwrap()
  let foreign_query_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, queries, query_output).unwrap(),
    10,
    1000,
  ).unwrap()
  let generated = task_test_generated(owner)
  // One record on each side requires 28 control work and 23 workspace slots.
  // The public default also uses max_work for output capture; keep its separate
  // value budget at 1000, as in the existing bounded-control fixtures.
  let active = @local_veca.start_nearest_inputs_with_relations(
    @bounded.control(),
    @execution.generated_completion_preparation(generated),
    @execution.generated_prepared_sequence(generated),
    0,
    @local_veca.nearest_relation_producer(candidate_read),
    @local_veca.nearest_relation_producer(query_read),
    10,
    { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
    23,
    1000,
    1000,
    [candidate_read, query_read],
  ).unwrap()
  let mut terminal = false
  let mut charged = 0L
  for _ in 0..<32 {
    if !terminal {
      match @local_veca.advance_nearest(active, 1).unwrap() {
        @local_veca.NearestContinue(work~, ..) => {
          assert_eq(work - charged, 1L)
          charged = work
        }
        @local_veca.NearestComplete(output, work~, ..) => {
          assert_eq(work - charged, 1L)
          charged = work
          assert_eq(@execution.completed_row_count(output), 1)
          assert_eq(@execution.completed_column_count(output), 4)
          for
            column, (name, expected) in [
              ("candidate_id", 1.0),
              ("query_id", 10.0),
              ("rank", 1.0),
              ("score", 1.0),
            ] {
            assert_eq(
              @execution.completed_column_name(output, column),
              Some(name),
            )
            assert_true(
              @execution.completed_cell(output, 0, column)
              is Some(Number(actual)) &&
              actual == expected,
            )
          }
          assert_true(
            @execution.completed_output_matches_inputs(output, [
              candidate_read, query_read,
            ]),
          )
          assert_false(
            @execution.completed_output_matches_inputs(output, [
              candidate_read, foreign_query_read,
            ]),
          )
          terminal = true
        }
        _ => fail("typed Relation nearest stopped unexpectedly")
      }
    }
  }
  assert_true(terminal)
  assert_eq(charged, 28L)
  assert_true(@local_veca.nearest_stopped(active))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
  assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
  assert_false(@local_veca.nearest_cleanup_pending(active))
  assert_true(@execution.producer_read_available(candidate_read))
  assert_true(@execution.producer_read_available(query_read))
  assert_true(
    @local_veca.start_nearest_inputs_with_relations(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(candidate_read),
      @local_veca.nearest_relation_producer(query_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      22,
      1000,
      1000,
      [candidate_read, query_read],
    )
    is Err(@local_veca.NearestWorkspaceLimit),
  )
  // Roles remain exact even though both public inputs are Relations.
  assert_true(
    @local_veca.start_nearest_inputs_with_relations(
      @bounded.control(),
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(query_read),
      @local_veca.nearest_relation_producer(candidate_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      23,
      1000,
      1000,
      [candidate_read, query_read],
    )
    is Err(@local_veca.InvalidNearestKernel),
  )
  for prefix in [0, 1] {
    let control = @bounded.control()
    let active = @local_veca.start_nearest_inputs_with_relations(
      control,
      @execution.generated_completion_preparation(generated),
      @execution.generated_prepared_sequence(generated),
      0,
      @local_veca.nearest_relation_producer(candidate_read),
      @local_veca.nearest_relation_producer(query_read),
      10,
      { max_nodes: 100, max_text_bytes: 1000, max_depth: 10, max_work: 1000, },
      23,
      1000,
      1000,
      [candidate_read, query_read],
    ).unwrap()
    for _ in 0..<prefix {
      assert_true(
        @local_veca.advance_nearest(active, 1).unwrap()
        is @local_veca.NearestContinue(..),
      )
    }
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @local_veca.advance_nearest(active, 1).unwrap()
      is @local_veca.NearestStopped(_, work=charged, ..) &&
      charged == prefix.to_int64(),
    )
    assert_true(@local_veca.nearest_stopped(active))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(true))
    assert_eq(@local_veca.cleanup_nearest(active), Ok(false))
    assert_false(@local_veca.nearest_cleanup_pending(active))
    assert_true(@execution.producer_read_available(candidate_read))
    assert_true(@execution.producer_read_available(query_read))
  }
}
