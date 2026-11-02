///|
test "platform VM demand grows only its original claim and preserves sibling/input overlap" {
  let (root, capacity, vm, _, _) = platform_vm_capacity_fixture()
  let input = allocate_shared_capacity(capacity, 2L).unwrap()
  let before = ledger_usage(root)
  let work = reserve_platform_vm_working_capacity(vm, 1L, 1L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 4L)
  let borrow = borrow_platform_vm_working_capacity(work).unwrap()
  grow_platform_vm_working_capacity(work, 2L, 4L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 8L)
  assert_eq(work.allocation.bytes, 6L)
  // The already held input and working peak both remain. Refusal neither
  // moves the old claim nor creates a second reservation or replacement Root.
  assert_true(
    grow_platform_vm_working_capacity(work, 3L, 4L)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(
    (work.retained, work.execution, work.allocation.bytes),
    (2L, 4L, 6L),
  )
  assert_eq(shared_capacity_usage(capacity).allocated, 8L)
  grow_platform_vm_working_capacity(work, 1L, 1L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 8L)
  assert_eq(ledger_usage(root), before)
  assert_true(
    close_platform_vm_working_capacity_after_cleanup(work)
    is Err(Resource(InvalidCharge)),
  )
  assert_true(
    grow_platform_vm_working_capacity(work, 2L, 4L) is Err(Unavailable),
  )
  return_shared_capacity(borrow).unwrap()
  close_platform_vm_working_capacity_after_cleanup(work).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 2L)
  assert_eq(ledger_usage(root).reserved_execution_bytes, 8L)
  retire_shared_capacity(input).unwrap()
  release_shared_capacity(input).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
}

///|
test "platform VM demand rejects copied original and stale callback before mutating claim" {
  let (_, capacity, vm, state, _) = platform_vm_capacity_fixture()
  let work = reserve_platform_vm_working_capacity(vm, 1L, 1L).unwrap()
  assert_true(
    grow_platform_vm_working_capacity({ ..work, }, 2L, 2L)
    is Err(ForeignOriginal),
  )
  state.val = -41L
  assert_true(grow_platform_vm_working_capacity(work, 2L, 2L) is Err(Unknown))
  state.val = 0L
  assert_true(borrow_platform_vm_working_capacity(work) is Err(Unknown))
  assert_eq(shared_capacity_usage(capacity).allocated, 2L)
  // Resource cleanup returns this exact inactive suballocation only. A lost
  // current observation is not turned into VM destruction or an execution grant.
  close_platform_vm_working_capacity_after_cleanup(work).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
}

///|
test "platform VM demand rechecks same claim after original current callback closes it" {
  let (root, capacity, vm, _, _) = platform_vm_capacity_fixture()
  let work = reserve_platform_vm_working_capacity(vm, 1L, 1L).unwrap()
  let selected = Ref(Some(work))
  let observe = vm.observe
  // Private WB port is an explicit callback/reentry stand-in, not an actual
  // fixed Python observation. The same state fence must still reject it.
  let replacement : PlatformVMCapacity = {
    ..vm,
    observe: (nonce, ordinal) => {
      if ordinal == 0 && selected.val is Some(original) {
        selected.val = None
        close_platform_vm_working_capacity_after_cleanup(original).unwrap()
      }
      observe(nonce, ordinal)
    },
  }
  replacement.original = Some(replacement)
  let second = reserve_platform_vm_working_capacity(replacement, 1L, 1L).unwrap()
  selected.val = Some(second)
  assert_true(
    grow_platform_vm_working_capacity(second, 2L, 2L) is Err(Unavailable),
  )
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
  assert_eq(ledger_usage(root).reserved_execution_bytes, 8L)
}
