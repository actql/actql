///|
fn local_host_crypto_unacquired_pair(
  host : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  sqlite : InstalledArenaSqliteLibrary,
) -> InstalledArenaLocalHostResources {
  {
    host,
    read,
    sqlite,
    active: None,
    sqlite_context_retired: false,
    closing: false,
    closed: false,
  }
}

///|
test "pair Crypto refuses an unregistered pair before retaining a component" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let pair = local_host_crypto_unacquired_pair(host, read, sqlite)
  assert_true(
    host.prepare_local_host_read_crypto(pair, read, "/unused", 524288L, 256)
    is Err(Resources(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))),
  )
  assert_true(read.domain.crypto_component is None && pair.active is None)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "pair Crypto cannot replace its original Read with an equal-metadata carrier" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let pair = local_host_crypto_unacquired_pair(host, read, sqlite)
  // Negative registration counter only: no successful pair, read or C scope.
  host.local_host_resources = Some(pair)
  assert_true(
    host.prepare_local_host_read_crypto(
      pair,
      { ..read, },
      "/unused",
      524288L,
      256,
    )
    is Err(Resources(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))),
  )
  assert_true(read.domain.crypto_component is None && read.consumer is None)
  host.local_host_resources = None
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "pair Crypto refuses an unclaimed Read despite a counterfeit active phase" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let pair = local_host_crypto_unacquired_pair(host, read, sqlite)
  host.local_host_resources = Some(pair)
  pair.active = Some(HostRead)
  assert_true(
    host.prepare_local_host_read_crypto(pair, read, "/unused", 524288L, 256)
    is Err(Resources(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))),
  )
  assert_true(read.domain.crypto_component is None && read.consumer is None)
  assert_true(pair.active == Some(HostRead) && !read.closing && !pair.closing)
  pair.active = None
  host.local_host_resources = None
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "pending same-domain Crypto refuses Read retirement before stopping its frame" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  // Explicitly unacquired partial carrier: no component, user or ACK is forged.
  let component = register_crypto_component_original(read.domain)
  component.failed = true
  assert_true(
    host.close_domain_original_read(read)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
  )
  assert_false(read.closing || read.closed || read.physical_retired.val)
  host.close_crypto_component(component).unwrap()
  assert_true(component.closed)
  local_host_resources_finish_pending(host, read, sqlite)
}

///|
test "failed component scope leave retains its original registration and parent fence" {
  let host = domain_test_host()
  let (read, sqlite) = local_host_resources_pending(host)
  let component = register_crypto_component_original(read.domain)
  // Unacquired carrier fault: no physical scope/ACK is manufactured.
  component.scope_open = true
  assert_true(host.close_crypto_component(component) is Err(_))
  assert_true(component.scope_open && component.failed && !component.closed)
  assert_true(
    read.domain.crypto_component is Some(original) &&
    physical_equal(original, component),
  )
  assert_true(host.close_domain_original_read(read) is Err(_))
  assert_false(read.closing || read.closed)
  // Restore only this negative fixture's never-entered flag, then clean its
  // empty carrier through the original owner. No physical leave is inferred.
  component.scope_open = false
  host.close_crypto_component(component).unwrap()
  local_host_resources_finish_pending(host, read, sqlite)
}
