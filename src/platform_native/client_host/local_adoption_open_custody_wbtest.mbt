///|
#borrow(root)
extern "C" fn adoption_open_fail_census_close(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_census_close"

///|
fn adoption_open_refusal(
  result : Result[NativeLocalAdoptionSession, NativeLocalAdoptionOpenFailure],
) -> NativeLocalAdoptionOpenFailure raise {
  match result {
    Err(original) => original
    Ok(_) => {
      fail("existing-only acquisition unexpectedly succeeded")
      abort("unreachable")
    }
  }
}

///|
fn adoption_open_require_locked(parent : @filesystem.Root) -> Unit raise {
  match parent.acquire_lock_with_custody("local-adoption.lock") {
    Err(original) => {
      assert_true(original.issue() is @filesystem.Lock(_))
      original.retry_cleanup().unwrap()
    }
    Ok(lock) => {
      lock.close_checked().unwrap()
      fail("the original exclusive acquisition was released early")
    }
  }
}

///|
test "existing-only adoption rejects invalid input before acquiring an Adoption Root or Lock" {
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      "/absent",
      "..",
      "/absent",
      "account.json",
      "operator",
      epoch_test_crypto(),
    ),
  )
  assert_true(failed.issue() is InvalidInput)
  assert_true(
    failed.source_root is None &&
    failed.parent is None &&
    failed.root is None &&
    failed.managed is None &&
    failed.lock is None &&
    failed.root_acquisition is None &&
    failed.lock_acquisition is None,
  )
  failed.retry_cleanup().unwrap()
  failed.retry_cleanup().unwrap()
  assert_true(failed.issue() is InvalidInput)
}

///|
test "existing-only adoption retains the actual rejected private Root without admitting it" {
  let broad = @env.get_env_var("ACTQL_TEST_NATIVE_BROAD_ROOT").unwrap()
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      broad,
      "never-created",
      broad,
      "account.json",
      "operator",
      epoch_test_crypto(),
    ),
  )
  assert_true(failed.issue() is Filesystem(@filesystem.RootOpen(_)))
  assert_true(failed.root_acquisition is Some(_))
  assert_true(
    failed.source_root is None && failed.parent is None && failed.lock is None,
  )
  failed.retry_cleanup().unwrap()
  failed.retry_cleanup().unwrap()
  assert_true(failed.root_acquisition is None)
  assert_true(failed.issue() is Filesystem(@filesystem.RootOpen(_)))
}

///|
test "existing-only adoption preserves foreign account refusal and the same opened source" {
  let (path, name, borrowed, _) = local_selected_source("open-custody-foreign")
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      path,
      "open-custody-foreign.host",
      path,
      name,
      "other",
      epoch_test_crypto(),
    ),
  )
  let source = failed.source_root.unwrap()
  assert_false(physical_equal(source, borrowed))
  assert_true(failed.issue() is ForeignAccount)
  assert_true(
    failed.parent is None && failed.root is None && failed.lock is None,
  )
  failed.retry_cleanup().unwrap()
  assert_true(source.private_ownership() is Err(_))
  assert_true(failed.source_root is None && failed.issue() is ForeignAccount)
  assert_true(
    borrowed.inspect_directory("open-custody-foreign.host").unwrap() is None,
  )
  borrowed.private_ownership().unwrap() |> ignore
  borrowed.close().unwrap()
}

///|
test "existing-only missing Host retains source parent and exclusive lock without initialization" {
  let (path, name, borrowed, _) = local_selected_source("open-custody-missing")
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      path,
      "open-custody-missing.host",
      path,
      name,
      "operator",
      epoch_test_crypto(),
    ),
  )
  assert_true(failed.issue() is CustodyLost)
  assert_true(
    failed.source_root is Some(_) &&
    failed.parent is Some(_) &&
    failed.lock is Some(_),
  )
  assert_true(failed.root is None)
  adoption_open_require_locked(borrowed)
  assert_true(
    borrowed.inspect_directory("open-custody-missing.host").unwrap() is None,
  )
  failed.retry_cleanup().unwrap()
  assert_true(
    failed.source_root is None && failed.parent is None && failed.lock is None,
  )
  let next = borrowed.acquire_lock_with_custody("local-adoption.lock").unwrap()
  next.close_checked().unwrap()
  failed.retry_cleanup().unwrap()
  assert_true(failed.issue() is CustodyLost)
  assert_true(
    borrowed.inspect_directory("open-custody-missing.host").unwrap() is None,
  )
  borrowed.close().unwrap()
}

///|
test "existing-only missing intent retains its opened child and never repairs original bytes" {
  let (path, name, borrowed, _) = local_selected_source("open-custody-empty")
  borrowed.create_directory("open-custody-empty.host").unwrap() |> ignore
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      path,
      "open-custody-empty.host",
      path,
      name,
      "operator",
      epoch_test_crypto(),
    ),
  )
  let child = failed.root.unwrap()
  assert_true(failed.issue() is CustodyLost)
  assert_true(child.inspect_generation("initialization.json").unwrap() is None)
  assert_true(child.inspect_generation("account.json").unwrap() is None)
  adoption_open_require_locked(borrowed)
  failed.retry_cleanup().unwrap()
  assert_true(child.private_ownership() is Err(_))
  let observed = borrowed
    .open_child_with_custody("open-custody-empty.host")
    .unwrap()
  assert_true(
    observed.inspect_generation("initialization.json").unwrap() is None,
  )
  assert_true(observed.inspect_generation("account.json").unwrap() is None)
  observed.close().unwrap()
  borrowed.close().unwrap()
}

///|
test "existing-only competing acquisition cleanup never releases the original session lock" {
  let (path, name, borrowed, _) = local_selected_source(
    "open-custody-contended",
  )
  let crypto = epoch_test_crypto()
  let original = begin_native_local_host_adoption(
    path, "open-custody-contended.host", path, name, "operator", crypto,
  ).unwrap()
  let intent = original.intent_cid()
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      path, "open-custody-contended.host", path, name, "operator", crypto,
    ),
  )
  assert_true(failed.issue() is Filesystem(@filesystem.Lock(_)))
  assert_true(failed.lock_acquisition is Some(_) && failed.lock is None)
  failed.retry_cleanup().unwrap()
  original.check_original().unwrap()
  adoption_open_require_locked(borrowed)
  assert_true(original.close())
  original.root.close().unwrap()
  original.source_root.close().unwrap()
  original.parent.close().unwrap()
  let restored = begin_existing_native_local_host_adoption_with_custody(
    path, "open-custody-contended.host", path, name, "operator", crypto,
  ).unwrap()
  assert_eq(restored.intent_cid(), intent)
  assert_true(restored.existing_only)
  assert_false(restored.initial_signing_eligible.val)
  assert_true(restored.close())
  restored.root.close().unwrap()
  restored.source_root.close().unwrap()
  restored.parent.close().unwrap()
  borrowed.close().unwrap()
}

///|
test "existing-only managed Root cleanup preserves equal-path distinct originals and borrowed Root" {
  let (path, name, borrowed, _) = local_selected_source("open-custody-managed")
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      path,
      "open-custody-managed.host",
      path,
      name,
      "operator",
      epoch_test_crypto(),
      managed_root_path=Some(path),
    ),
  )
  let managed = failed.managed.unwrap()
  let source = failed.source_root.unwrap()
  let parent = failed.parent.unwrap()
  assert_false(physical_equal(managed, source))
  assert_false(physical_equal(source, parent))
  assert_false(physical_equal(managed, borrowed))
  assert_eq(
    managed.private_ownership().unwrap(),
    borrowed.private_ownership().unwrap(),
  )
  failed.retry_cleanup().unwrap()
  assert_true(managed.private_ownership() is Err(_))
  assert_true(source.private_ownership() is Err(_))
  assert_true(parent.private_ownership() is Err(_))
  borrowed.private_ownership().unwrap() |> ignore
  borrowed.close().unwrap()
}

///|
test "existing-only original Root Unknown keeps the same source refusal and original exclusive lock" {
  let (path, name, borrowed, _) = local_selected_source("open-custody-unknown")
  let failed = adoption_open_refusal(
    begin_existing_native_local_host_adoption_with_custody(
      path,
      "open-custody-unknown.host",
      path,
      name,
      "operator",
      epoch_test_crypto(),
    ),
  )
  let source = failed.source_root.unwrap()
  adoption_open_fail_census_close(source, 1)
  assert_true(source.check_directory_members([]) is Err(@filesystem.Cleanup(_)))
  assert_true(failed.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_true(failed.issue() is CustodyLost)
  assert_true(physical_equal(failed.source_root.unwrap(), source))
  assert_true(failed.lock is Some(_))
  adoption_open_require_locked(borrowed)
  assert_true(failed.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))))
  assert_true(physical_equal(failed.source_root.unwrap(), source))
  adoption_open_require_locked(borrowed)
  // Explicit test-owned lock retirement is not the Unknown Root's ACK.
  failed.lock.unwrap().close_checked().unwrap()
  assert_true(failed.retry_cleanup() is Err(Filesystem(@filesystem.Cleanup(_))))
  borrowed.close().unwrap()
}
