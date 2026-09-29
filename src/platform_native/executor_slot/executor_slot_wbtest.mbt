///|
fn slot_test_root() -> String? {
  @env.get_env_var("ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT")
}

///|
/// Wait (bounded) until a fresh opener can take the slot.
fn slot_becomes_free(path : String) -> Bool {
  for _attempt in 0..<100 {
    let probe = open_native_executor_slot(path).unwrap()
    let free = probe.try_acquire().unwrap()
    ignore(probe.close())
    if free {
      return true
    }
    let child = open_native_executor_slot(path).unwrap()
    ignore(child.close())
    // Sleep 50 ms in a separate short-lived process without holding the slot.
    let waiter = open_native_executor_slot(path + ".wait").unwrap()
    ignore(waiter.try_acquire().unwrap())
    let sleeper = waiter.spawn_holder("/bin/sh", ["-c", "sleep 0.05"]).unwrap()
    ignore(sleeper.wait(true).unwrap())
  }
  false
}

///|
test "executor slot passes from parent to holder without a gap" {
  guard slot_test_root() is Some(root) else { return }
  let path = root + "/handover.lock"
  let first = open_native_executor_slot(path).unwrap()
  let second = open_native_executor_slot(path).unwrap()
  assert_true(first.try_acquire().unwrap())
  // Re-taking through the same description is not a second owner.
  assert_true(first.try_acquire().unwrap())
  // A second parent of the same Site cannot take the slot.
  assert_false(second.try_acquire().unwrap())
  let holder = first.spawn_holder("/bin/sh", ["-c", "sleep 1"]).unwrap()
  // The first parent closed its own copy; the holder keeps the slot.
  assert_true(first.try_acquire() is Err(Closed))
  assert_false(second.try_acquire().unwrap())
  assert_true(holder.wait(false).unwrap() is None)
  assert_eq(holder.wait(true).unwrap(), Some(Exited(0)))
  assert_true(second.try_acquire().unwrap())
  assert_true(second.close())
}

///|
test "executor slot stays held by descendants of the holder" {
  guard slot_test_root() is Some(root) else { return }
  let path = root + "/descendant.lock"
  let parent = open_native_executor_slot(path).unwrap()
  assert_true(parent.try_acquire().unwrap())
  // The holder starts a background descendant and exits at once.
  let holder = parent
    .spawn_holder("/bin/sh", ["-c", "sleep 1 & exit 0"])
    .unwrap()
  assert_eq(holder.wait(true).unwrap(), Some(Exited(0)))
  let restarted = open_native_executor_slot(path).unwrap()
  assert_false(restarted.try_acquire().unwrap())
  ignore(restarted.close())
  assert_true(slot_becomes_free(path))
}

///|
test "executor slot is kept by the caller when the holder cannot start" {
  guard slot_test_root() is Some(root) else { return }
  let path = root + "/spawn-failure.lock"
  let parent = open_native_executor_slot(path).unwrap()
  assert_true(parent.try_acquire().unwrap())
  assert_true(
    parent.spawn_holder(root + "/missing-executable", []) is Err(SpawnFailed),
  )
  let other = open_native_executor_slot(path).unwrap()
  assert_false(other.try_acquire().unwrap())
  assert_true(parent.close())
  assert_true(other.try_acquire().unwrap())
  ignore(other.close())
}

///|
test "executor slot refuses a holder when the slot is not held or replaced" {
  guard slot_test_root() is Some(root) else { return }
  let path = root + "/refusal.lock"
  let owner = open_native_executor_slot(path).unwrap()
  let other = open_native_executor_slot(path).unwrap()
  assert_true(owner.try_acquire().unwrap())
  // A parent that did not win the slot cannot hand it to a holder.
  assert_true(other.spawn_holder("/bin/sh", ["-c", "exit 0"]) is Err(Busy))
  // This test process did not inherit the slot descriptor.
  assert_true(inherited_native_executor_slot(path) is Err(_))
  assert_true(owner.close())
  ignore(other.close())
  let replaced = open_native_executor_slot(root + "/replaced.lock").unwrap()
  assert_true(replaced.try_acquire().unwrap())
  let renamed = open_native_executor_slot(root + "/replaced-other.lock").unwrap()
  ignore(renamed.close())
  // Only the named file counts: a descriptor for another file is replaced.
  let mismatched : NativeExecutorSlot = {
    path: root + "/replaced-other.lock",
    descriptor: replaced.descriptor,
  }
  assert_true(
    mismatched.spawn_holder("/bin/sh", ["-c", "exit 0"]) is Err(Replaced),
  )
  ignore(replaced.close())
}
