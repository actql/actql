///|
// The Root/capacity/borrower are real Resource originals. Fixed Host port
// observations below are explicit nominal stand-ins, not a VM or permission.
fn platform_vm_capacity_fixture() -> (
  Ledger,
  SharedCapacity,
  PlatformVMCapacity,
  Ref[Int64],
  Ref[Int],
) {
  let root = create_ledger({
    planning_work: 64,
    attempts: 8,
    holdings: 8,
    transfer_bytes: 16L,
    retained_bytes: 16L,
    execution_bytes: 16L,
  }).unwrap()
  let capacity = reserve_shared_capacity(root, 8L).unwrap()
  let state = Ref(0L)
  let calls = Ref(0)
  let original = bind_platform_vm_capacity_original(1L, root, capacity, (
    _,
    ordinal,
  ) => {
    calls.val += 1
    if ordinal == 0 {
      state.val
    } else if ordinal == 1 {
      8L
    } else {
      -42L
    }
  }).unwrap()
  (root, capacity, original, state, calls)
}

///|
test "platform VM capacity binds exact original Root and reservation not equal DATA" {
  let (root, capacity, original, _, _) = platform_vm_capacity_fixture()
  let other = create_ledger(ledger_limits(root)).unwrap()
  let other_capacity = reserve_shared_capacity(other, 8L).unwrap()
  let before = ledger_usage(root)
  assert_true(require_platform_vm_capacity(original, root, capacity) is Ok(_))
  assert_true(
    require_platform_vm_capacity(original, other, capacity)
    is Err(ForeignOriginal),
  )
  assert_true(
    require_platform_vm_capacity(original, root, other_capacity)
    is Err(ForeignOriginal),
  )
  assert_true(
    require_platform_vm_capacity({ ..original, }, root, capacity)
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(root), before)
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
}

///|
test "platform VM current Unknown and closing are sticky without a replacement grant" {
  let (root, capacity, original, state, calls) = platform_vm_capacity_fixture()
  state.val = -41L
  assert_true(
    require_platform_vm_capacity(original, root, capacity) is Err(Unknown),
  )
  let before = calls.val
  state.val = 0L
  assert_true(
    require_platform_vm_capacity(original, root, capacity) is Err(Unknown),
  )
  assert_eq(calls.val, before)
  let (root, capacity, original, state, calls) = platform_vm_capacity_fixture()
  state.val = 1L
  assert_true(
    require_platform_vm_capacity(original, root, capacity) is Err(Unavailable),
  )
  let before = calls.val
  state.val = 0L
  assert_true(
    require_platform_vm_capacity(original, root, capacity) is Err(Unavailable),
  )
  assert_eq(calls.val, before)
}

///|
test "platform VM binding creates no capacity and existing borrowers still fence release" {
  let (root, capacity, original, _, _) = platform_vm_capacity_fixture()
  assert_true(
    bind_platform_vm_capacity_original(2L, root, capacity, (_, ordinal) => {
      if ordinal == 0 {
        0L
      } else {
        7L
      }
    })
    is Err(InvalidOriginal),
  )
  assert_true(
    bind_platform_vm_capacity_original(2L, root, capacity, (_, _) => -41L)
    is Err(Unknown),
  )
  require_platform_vm_capacity(original, root, capacity).unwrap()
  let allocation = allocate_shared_capacity(capacity, 8L).unwrap()
  let borrow = borrow_shared_capacity(capacity, allocation).unwrap()
  assert_true(allocate_shared_capacity(capacity, 1L) is Err(RetentionLimit))
  retire_shared_capacity(allocation).unwrap()
  assert_true(release_shared_capacity(allocation) is Err(InvalidCharge))
  return_shared_capacity(borrow).unwrap()
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(capacity).unwrap()
  assert_true(
    require_platform_vm_capacity(original, root, capacity) is Err(Unavailable),
  )
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(root).reserved_execution_bytes, 0L)
}
