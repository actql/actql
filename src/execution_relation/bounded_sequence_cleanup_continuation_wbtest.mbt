///|
test "accepted Sequence output keeps ownership while finite private cleanup reports actual removals" {
  let (_, active, input) = bounded_sequence_fixture(extra_patterns=24)
  assert_eq(bounded_sequence_match_cleanup_continuation(active), -1L)
  let output = match finish_bounded_sequence(active) {
    BoundedSequenceMatchComplete(output, ..) => output
    _ => fail("bounded original Sequence did not complete")
  }
  // Its output still owns backing until the ordinary cleanup operation
  // detaches it. The progress observer cannot manufacture that transition.
  assert_eq(bounded_sequence_match_cleanup_continuation(active), -1L)
  assert_false(cleanup_bounded_sequence_match(active).unwrap())
  let mut prior = bounded_sequence_match_cleanup_continuation(active)
  assert_true(prior > 0L)
  let mut done = false
  for _ in 0..<1000 {
    if done {
      break
    }
    done = cleanup_bounded_sequence_match(active).unwrap()
    if !done {
      let next = bounded_sequence_match_cleanup_continuation(active)
      assert_true(next > prior)
      prior = next
      assert_true(bounded_sequence_match_cleanup_pending(active))
    }
    assert_true(completed_output_available(output))
    assert_true(producer_read_available(input))
  }
  assert_true(done)
  assert_eq(bounded_sequence_match_cleanup_continuation(active), -1L)
  assert_false(bounded_sequence_match_cleanup_pending(active))
  assert_bounded_sequence_scratch_reclaimed(active)
}
