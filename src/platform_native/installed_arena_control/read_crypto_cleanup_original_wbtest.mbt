///|
test "Read Crypto cleanup does not turn unclaimed closing or copied carriers into an entered original" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let component = register_crypto_component_original(read.domain)
  let pair = local_host_crypto_unacquired_pair(host, read, sqlite)
  assert_false(
    cleanup_installed_arena_read_crypto_original(host, pair, read, component),
  )
  // These are unacquired negative carriers. The flags do not supply an actual
  // consumer, backed use, context, entered frame or physical acknowledgement.
  host.local_host_resources = Some(pair)
  pair.closing = true
  pair.active = Some(HostRead)
  read.closing = true
  assert_false(
    cleanup_installed_arena_read_crypto_original(host, pair, read, component),
  )
  assert_false(
    cleanup_installed_arena_read_crypto_original(
      host,
      { ..pair, },
      read,
      component,
    ),
  )
  assert_false(
    cleanup_installed_arena_read_crypto_original(
      host,
      pair,
      { ..read, },
      component,
    ),
  )
  assert_false(
    cleanup_installed_arena_read_crypto_original(host, pair, read, {
      ..component,
    }),
  )
  assert_true(pair.closing && read.closing && !pair.closed && !read.closed)
  assert_false(component.closed || read.physical_retired.val)
  // Undo only the never-entered negative fixture's flags. Actual live/failed
  // cleanup remains monotonic and is exercised by the matching physical caller.
  pair.active = None
  host.local_host_resources = None
  read.closing = false
  host.close_crypto_component(component).unwrap()
  local_host_resources_finish_pending(host, read, sqlite)
}
