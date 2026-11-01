///|
test "charged writer prefix remains observable after original typed refusal without output authority" {
  let out = hashing_writer(1, 10, 10)
  begin_array(out)
  let failed = try {
    null_value(out)
    false
  } catch {
    OutputLimit => true
    _ => false
  }
  assert_true(failed)
  assert_true(out.closed)
  assert_eq(observed_writer_usage(out), (1, 2, 1))
  let again = observed_writer_usage(out)
  assert_eq(again, (1, 2, 1))
  let finalized = try {
    let _ = finish_hash_usage(out)
    false
  } catch {
    _ => true
  }
  assert_true(finalized)
  assert_true(out.closed)
  assert_eq(observed_writer_usage(out), again)
}
