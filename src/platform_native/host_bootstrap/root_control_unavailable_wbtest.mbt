///|
// Explicit ordinary-provider diagnostic. This case selects neither the scoped
// review allocator nor a replacement heap. Unsupported control entry must stop
// before allocating a logical claim or consuming its one-shot physical slot.
test "ordinary Native provider refuses enclosing control before any claim" {
  let original = { identity: 907, }
  let host = test_host(original)
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let before = host.capacity_usage()
  let usage = host.usage()
  assert_eq(
    host.prepare_root_control(original, scope, {
      maximum_managed_request: managed_value_layout_ffi(0) + 33L,
      allocation_requests: 1L,
    }),
    Err(Unavailable),
  )
  assert_true(host.root_control is None)
  let after = host.capacity_usage()
  assert_eq(
    (after.capacity, after.allocated, after.closing),
    (before.capacity, before.allocated, before.closing),
  )
  assert_eq(host.usage(), usage)
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
}
