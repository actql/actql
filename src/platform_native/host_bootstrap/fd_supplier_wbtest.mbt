///|
test "negative FD is refused without consuming the installed original" {
  let original = { identity: 10, }
  let supplier = test_supplier(original, 64L * test_page_bytes_ffi())
  assert_true(supplier.acquire_fd(original, -1) is Err(Unavailable))
  assert_false(supplier.consumed)
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("original fixture backing unavailable")
  }
  host.try_close(original).unwrap()
}

///|
test "foreign original FD acquisition cannot consume another supplier" {
  let original = { identity: 11, }
  let foreign = { identity: 11, }
  let supplier = test_supplier(original, 64L * test_page_bytes_ffi())
  assert_true(supplier.acquire_fd(foreign, 2147483647) is Err(ForeignOriginal))
  assert_false(supplier.consumed)
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("original fixture backing unavailable")
  }
  host.try_close(original).unwrap()
}

///|
test "failed borrowed FD keeps the original reserved partial carrier" {
  let original = { identity: 12, }
  let bytes = 64L * test_page_bytes_ffi()
  let supplier = test_supplier(original, bytes)
  let host = match supplier.acquire_fd(original, 2147483647).unwrap() {
    Pending(host, Physical(-1)) => host
    _ => abort("invalid physical FD must preserve the partial Host")
  }
  assert_true(supplier.consumed)
  assert_eq(host.usage().reserved_execution_bytes, bytes)
  assert_true(
    host.claim(original, supplier.source, supplier.recipe, 1L)
    is Err(Unavailable),
  )
  assert_true(supplier.acquire_fd(original, 2147483647) is Err(AlreadyConsumed))
  let foreign = { identity: 12, }
  assert_true(host.try_close(foreign) is Err(ForeignOriginal))
  assert_false(host.closed)
  assert_eq(host.usage().reserved_execution_bytes, bytes)
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_eq(host.usage().attempts, 0)
  host.try_close(original).unwrap()
  assert_eq(host.usage().attempts, 0)
}
