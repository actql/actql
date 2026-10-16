///|
fn local_product_test_parent() -> @local_filesystem.Root {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_CLI_PARENT_ROOT").unwrap()
  @local_filesystem.open_root(path).unwrap()
}

///|
#borrow(root)
extern "C" fn local_product_test_fail_census_close(
  root : @local_filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_census_close"

///|
test "packaged Local parent closes after work without closing another same-path Root" {
  let parent = local_product_test_parent()
  let borrowed = local_product_test_parent()
  let reply = local_product_with_owned_parent(parent, () => {
    parent.bootstrap_parent_ownership().unwrap() |> ignore
    "original reply"
  })
  assert_eq(reply, "original reply")
  assert_true(parent.bootstrap_parent_ownership() is Err(_))
  borrowed.bootstrap_parent_ownership().unwrap() |> ignore
  borrowed.close().unwrap()
}

///|
test "packaged Local early refusal closes its parent and preserves the original reason" {
  let parent = local_product_test_parent()
  let reason = local_product_with_owned_parent(parent, () => {
    parent.bootstrap_parent_ownership().unwrap() |> ignore
    stop("ExplicitLocalAdoptionRequired")
  }) catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "ExplicitLocalAdoptionRequired")
  assert_true(parent.bootstrap_parent_ownership() is Err(_))
}

///|
test "packaged Local parent cleanup cannot turn pending original close into a reply" {
  let parent = local_product_test_parent()
  local_product_test_fail_census_close(parent, 1)
  assert_true(
    parent.check_directory_members([]) is Err(@local_filesystem.Cleanup(_)),
  )
  let reason = local_product_with_owned_parent(parent, () => "must not escape") catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "LocalProductCleanupPending")
  // This is the same pending original, never a replacement Root or a retry ACK.
  assert_true(parent.close() is Err(@local_filesystem.Cleanup(_)))
}

///|
test "packaged Local failed parent cleanup outranks the original work refusal" {
  let parent = local_product_test_parent()
  local_product_test_fail_census_close(parent, 1)
  assert_true(
    parent.check_directory_members([]) is Err(@local_filesystem.Cleanup(_)),
  )
  let reason = local_product_with_owned_parent(parent, () => {
    stop("OriginalWorkRefused")
  }) catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "LocalProductCleanupPending")
  // The same failed original remains pending; no close ACK is fabricated.
  assert_true(parent.close() is Err(@local_filesystem.Cleanup(_)))
}
