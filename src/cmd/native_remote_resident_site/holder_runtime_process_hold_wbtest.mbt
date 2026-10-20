///|
/// Caller progress model only. Physical Runtime Store/catalog and independent
/// process, Library and Slot close ACKs require the connected resident test.
test "same Runtime Store confirmed absence advances only its original release step" {
  let original = Ref(73)
  let position = Ref(6)
  let release : Ref[Result[Bool, @bundle.NativeRuntimeBundleStoreIssue]] = Ref(
    Err(@bundle.Closed),
  )
  let calls = Array::make(9, 0)
  let same_original = Ref(true)
  let close = (same, step) => {
    same_original.val = same_original.val && physical_equal(same, original)
    calls[step] += 1
    step != 6 || holder_runtime_process_hold_released(release.val)
  }
  assert_false(advance_holder_cleanup_pass(original, position, 9, close))
  assert_eq(position.val, 6)
  assert_eq(calls, [0, 0, 0, 0, 0, 0, 1, 0, 0])
  release.val = Ok(false)
  assert_true(advance_holder_cleanup_pass(original, position, 9, close))
  assert_eq(position.val, 9)
  assert_eq(calls, [0, 0, 0, 0, 0, 0, 2, 1, 1])
  assert_true(advance_holder_cleanup_pass(original, position, 9, close))
  assert_eq(calls, [0, 0, 0, 0, 0, 0, 2, 1, 1])
  assert_true(holder_runtime_process_hold_released(Ok(true)))
  assert_false(
    holder_runtime_process_hold_released(Err(@bundle.CleanupPending)),
  )
  assert_false(
    holder_runtime_process_hold_released(Err(@bundle.RecoveryRequired)),
  )
  assert_false(
    holder_runtime_process_hold_released(Err(@bundle.StateCollision)),
  )
  assert_true(same_original.val)
}
