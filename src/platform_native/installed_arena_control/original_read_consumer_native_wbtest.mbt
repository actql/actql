///|
fn consumer_unacquired_original(
  host : InstalledArenaHost,
) -> InstalledArenaOriginalRead {
  let domain = original_read_reply_domain(host)
  let read = original_read_unacquired_carrier(domain)
  domain.original_read = Some(read)
  read
}

///|
fn consumer_unacquired_finish(
  host : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
) -> Unit raise {
  host.close_domain_original_read(read).unwrap()
  assert_false(read.physical_retired.val)
  host.close_domain_after_owner_ack(read.domain).unwrap()
  host.try_close().unwrap()
}

///|
test "read consumer cannot manufacture a funded view from an unacquired carrier" {
  let host = domain_test_host()
  let read = consumer_unacquired_original(host)
  assert_true(
    host.prepare_domain_original_read_consumer(read, 1L, 1L) is Err(_),
  )
  assert_true(
    read.consumer is None && read.claim is None && read.workspace is None,
  )
  consumer_unacquired_finish(host, read)
}

///|
test "foreign read consumer target refuses before any original claim changes" {
  let host = domain_test_host()
  let other = domain_test_host()
  let read = consumer_unacquired_original(host)
  assert_true(
    other.prepare_domain_original_read_consumer(read, 1L, 1L)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(read.consumer is None && read.claim is None && !read.closed)
  consumer_unacquired_finish(host, read)
  other.try_close().unwrap()
}

///|
test "copied original read cannot allocate a consumer under retained registration" {
  let host = domain_test_host()
  let read = consumer_unacquired_original(host)
  assert_true(
    host.prepare_domain_original_read_consumer({ ..read, }, 1L, 1L)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(read.consumer is None && read.claim is None)
  consumer_unacquired_finish(host, read)
}

///|
test "closed original read never becomes fresh consumer eligibility" {
  let host = domain_test_host()
  let read = consumer_unacquired_original(host)
  host.close_domain_original_read(read).unwrap()
  assert_true(
    host.prepare_domain_original_read_consumer(read, 1L, 1L) is Err(_),
  )
  assert_true(read.consumer is None && read.claim is None && read.closed)
  host.close_domain_after_owner_ack(read.domain).unwrap()
  host.try_close().unwrap()
}
