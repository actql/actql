///|
// Legacy Root acquisition is deliberate in these physical Lock diagnostics.
// It does not establish a selected command Read or ordinary installed check.
fn product_acquired_capture_for_close(
  name : String,
) -> NativeLocalProductConfigurationCapture raise {
  let path = product_test_parent(name)
  let crypto = epoch_test_crypto()
  let session = begin_native_local_product_configuration(
    path,
    "selected",
    [("config.json", b"{}")],
    crypto,
  ).unwrap()
  session.stage_configuration().unwrap()
  let original = new_local_adoption_open_failure()
  original.parent = Some(session.parent)
  original.root = Some(session.root)
  original.lock = Some(session.lock)
  {
    parent_path: path,
    directory_name: "selected",
    crypto,
    originals: None,
    root_opening: LegacyPrivateRoots,
    original,
    opening: ProductAcquired(session),
    operation_failed: false,
    closing: false,
    cleanup_acknowledged: false,
  }
}

///|
test "acquired Product capture acknowledges its same original Lock once after Roots" {
  let capture = product_acquired_capture_for_close(
    "product-capture-actual-close",
  )
  guard capture.opening is ProductAcquired(session) else {
    fail("missing Session")
    abort("unreachable")
  }
  assert_true(physical_equal(capture.original.lock.unwrap(), session.lock))
  capture.close().unwrap()
  assert_true(capture.descriptor_cleanup_acknowledged())
  assert_true(session.closed)
  assert_false(session.close_pending)
  assert_true(session.root.private_ownership() is Err(_))
  assert_true(session.parent.bootstrap_parent_ownership() is Err(_))
  session.lock.close_checked().unwrap()
  assert_false(session.lock.close())
  capture.close().unwrap()
  assert_true(session.close())
}

///|
test "acquired Product capture retains its exclusive Lock while original child Root is Unknown" {
  let capture = product_acquired_capture_for_close(
    "product-capture-root-unknown",
  )
  guard capture.opening is ProductAcquired(session) else {
    fail("missing Session")
    abort("unreachable")
  }
  let observer = @filesystem.open_private_root(capture.parent_path).unwrap()
  adoption_open_fail_census_close(session.root, 1)
  assert_true(
    session.root.check_directory_members([]) is Err(@filesystem.Cleanup(_)),
  )
  assert_true(capture.close() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_false(capture.descriptor_cleanup_acknowledged())
  assert_false(session.closed)
  assert_true(
    capture.original.lock is Some(lock) && physical_equal(lock, session.lock),
  )
  adoption_open_require_locked(observer)
  assert_true(capture.close() is Err(Filesystem(@filesystem.Cleanup(_))))
  adoption_open_require_locked(observer)
  // Test-owned lock retirement is deliberately separate from the unresolved
  // Root and capture; it cannot turn their original Unknown into an ACK.
  session.lock.close_checked().unwrap()
  assert_false(capture.descriptor_cleanup_acknowledged())
  observer.close().unwrap()
}

///|
#borrow(lock)
extern "C" fn product_mark_original_lock_unknown(
  lock : @filesystem.Lock,
) -> Bool = "actql_native_filesystem_test_lock_consumed_unknown"

///|
test "acquired Product capture cannot acknowledge consumed original Lock Unknown" {
  let capture = product_acquired_capture_for_close(
    "product-capture-lock-unknown",
  )
  guard capture.opening is ProductAcquired(session) else {
    fail("missing Session")
    abort("unreachable")
  }
  assert_true(product_mark_original_lock_unknown(session.lock))
  for _ in 0..<2 {
    assert_true(capture.close() is Err(Filesystem(@filesystem.Cleanup(_))))
    assert_false(capture.descriptor_cleanup_acknowledged())
    assert_false(session.closed)
    assert_true(capture.original.root is None)
    assert_true(capture.original.parent is None)
    assert_true(
      capture.original.lock is Some(lock) && physical_equal(lock, session.lock),
    )
  }
  assert_true(session.lock.close_checked() is Err(@filesystem.Cleanup(_)))
  assert_false(session.lock.close())
}
