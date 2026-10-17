///|
#borrow(path)
extern "C" fn process_test_open(path : Bytes, flags : Int) -> Int = "open"

///|
extern "C" fn process_test_close(descriptor : Int) -> Int = "close"

///|
extern "C" fn process_test_dup(descriptor : Int) -> Int = "dup"

///|
extern "C" fn process_test_sleep(microseconds : Int) -> Int = "usleep"

///|
struct InstalledProcessFixture {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  descriptor : Int
  path : String
}

///|
fn installed_process_fixture(label : String) -> InstalledProcessFixture raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let descriptor = process_test_open(
    @utf8.encode(root + "/" + label + ".backing\u{0}"),
    2,
  )
  assert_true(descriptor >= 0)
  let host = prepared_host(64L * page_bytes_ffi())
  host.acquire_fd(descriptor).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = match
    host
    .prepare_domain(scope, descriptor, 32L * page_bytes_ffi(), {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 0L,
      execution_bytes: 32L * page_bytes_ffi(),
    })
    .unwrap() {
    PreparedDomain(domain) => domain
    PendingDomain(_, _) =>
      fail("fresh installed process domain preparation failed")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  { host, domain, descriptor, path: root + "/" + label + ".slot", }
}

///|
fn installed_process_prepare(
  fixture : InstalledProcessFixture,
  descriptor : Int,
  execution : Int64,
) -> InstalledArenaProcessReply {
  prepare_installed_arena_process_reply(
    fixture.host,
    fixture.domain,
    fixture.path,
    descriptor,
    1L,
    0L,
    execution,
  )
}

///|
fn installed_process_finish(fixture : InstalledProcessFixture) -> Unit raise {
  fixture.host.close_domain_after_owner_ack(fixture.domain).unwrap()
  assert_true(fixture.domain.process is None)
  fixture.host.try_close().unwrap()
  assert_true(fixture.host.closed)
  assert_eq(process_test_close(fixture.descriptor), 0)
}

///|
test "installed process registers same holder frame and retains generic-domain refusal until retirement" {
  let fixture = installed_process_fixture("installed-process-prepared")
  let reply = installed_process_prepare(
    fixture,
    fixture.descriptor,
    32L * page_bytes_ffi(),
  )
  assert_eq(reply.issue_family(), 0)
  let process = reply.original_process().unwrap()
  assert_true(physical_equal(reply.original_host(), fixture.host))
  assert_true(physical_equal(reply.original_domain(), fixture.domain))
  assert_true(process.region is Some(_) && process.frame is Some(_))
  assert_true(
    reply.original_channel() is Some(channel) &&
    physical_equal(channel, process.channel.unwrap()),
  )
  let copied = process
  fixture.host.require_process_current(fixture.domain, copied).unwrap()
  assert_true(fixture.host.require_domain_current(fixture.domain) is Err(_))
  let descriptors = operate_installed_arena_process_reply(
    fixture.host,
    fixture.domain,
    process,
    3,
  )
  assert_eq(descriptors.issue_family(), 0)
  assert_true(descriptors.descriptor(0) >= 0 && descriptors.descriptor(1) >= 0)
  assert_true(descriptors.descriptor(0) != descriptors.descriptor(1))
  assert_eq(reply.descriptor(0), -1)
  assert_true(
    fixture.host.close_domain_after_owner_ack(fixture.domain) is Err(_),
  )
  assert_true(
    fixture.host.prepare_process(
      fixture.domain,
      fixture.path,
      fixture.descriptor,
      1L,
      0L,
      32L * page_bytes_ffi(),
    )
    is Err(_),
  )
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  assert_true(process.closed && fixture.domain.live_channel is None)
  assert_true(
    fixture.domain.process is Some(_) && fixture.domain.loan is Some(_),
  )
  installed_process_finish(fixture)
  assert_true(
    fixture.host.require_process_current(fixture.domain, process) is Err(_),
  )
}

///|
test "installed process failed cleanup fences fresh work without inventing a stop or returning its loan" {
  let fixture = installed_process_fixture("installed-process-closing")
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  assert_true(
    fixture.host.close_prepared_process(fixture.domain, process) is Err(_),
  )
  assert_true(process.closing && !process.closed && process.stop is None)
  assert_true(
    fixture.host.process_descriptors(fixture.domain, process) is Err(_),
  )
  assert_true(fixture.domain.loan is Some(_))
  assert_true(
    fixture.host.retire_stopped_process(fixture.domain, process) is Err(_),
  )
  assert_true(process.stop is None)
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  assert_true(process.closed)
  installed_process_finish(fixture)
}

///|
test "installed process foreign target preserves immutable original custody and performs no new acquisition" {
  let fixture = installed_process_fixture("installed-process-foreign")
  let other = prepared_host(64L * page_bytes_ffi())
  let refused = prepare_installed_arena_process_reply(
    other,
    fixture.domain,
    fixture.path,
    fixture.descriptor,
    1L,
    0L,
    32L * page_bytes_ffi(),
  )
  assert_eq(refused.issue_family(), 2)
  assert_true(
    refused.original_process() is None && fixture.domain.process is None,
  )
  assert_true(physical_equal(refused.original_host(), fixture.host))
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  let copied = operate_installed_arena_process_reply(
    other,
    fixture.domain,
    process,
    7,
  )
  assert_eq(copied.issue_family(), 2)
  assert_true(physical_equal(copied.original_process().unwrap(), process))
  assert_false(process.closing || process.closed)
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  installed_process_finish(fixture)
  other.try_close().unwrap()
}

///|
test "installed process insufficient original envelope keeps frame and unstarted descriptor cleanup" {
  let fixture = installed_process_fixture("installed-process-small-envelope")
  let reply = installed_process_prepare(
    fixture,
    fixture.descriptor,
    page_bytes_ffi(),
  )
  assert_eq(reply.issue_family(), 11)
  let process = reply.original_process().unwrap()
  assert_true(process.frame is Some(_) && process.region is None)
  assert_true(process.holder is Some(_) && process.transport is Some(_))
  assert_true(
    fixture.host.close_domain_after_owner_ack(fixture.domain) is Err(_),
  )
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  assert_true(
    process.closed && process.holder_closed && process.channel_retired,
  )
  assert_eq(reply.issue_family(), 11)
  assert_true(fixture.domain.loan is Some(_))
  installed_process_finish(fixture)
}

///|
test "installed process bad region descriptor preserves original pending capture and one-shot retirement" {
  let fixture = installed_process_fixture("installed-process-capture-refusal")
  let reply = installed_process_prepare(fixture, -1, 32L * page_bytes_ffi())
  assert_eq(reply.issue_family(), 6)
  let process = reply.original_process().unwrap()
  assert_true(process.region is Some(_))
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  assert_eq(reply.issue_family(), 6)
  assert_true(
    fixture.domain.process is Some(original) &&
    physical_equal(original, process),
  )
  installed_process_finish(fixture)
}

///|
test "installed process known synchronous spawn refusal uses original unstarted cleanup without a stop" {
  let fixture = installed_process_fixture(
    "installed-process-known-spawn-refusal",
  )
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  assert_true(
    process.holder.unwrap().spawn_duplex(fixture.path + "/absent-worker", [])
    is Err(@executor.SpawnFailed),
  )
  assert_true(
    process.holder.unwrap().child() is Err(@executor.InvalidConfiguration),
  )
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  assert_eq(
    fixture.host.close_prepared_process(fixture.domain, process),
    Ok(()),
  )
  assert_true(process.closed && process.stop is None)
  assert_true(fixture.domain.loan is Some(_))
  assert_true(
    process.holder.unwrap().spawn_duplex("/usr/bin/true", []) is Err(_),
  )
  installed_process_finish(fixture)
}

///|
test "installed process borrows its captured descriptor after the input alias closes and refuses foreign or closing access" {
  let fixture = installed_process_fixture(
    "installed-process-captured-descriptor",
  )
  let input = process_test_dup(fixture.descriptor)
  assert_true(input >= 0)
  let process = installed_process_prepare(
      fixture,
      input,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  assert_eq(process_test_close(input), 0)
  let reply = operate_installed_arena_process_reply(
    fixture.host,
    fixture.domain,
    process,
    9,
  )
  assert_eq(reply.issue_family(), 0)
  let descriptor = reply.backing_descriptor()
  assert_true(
    descriptor >= 10 && descriptor != fixture.descriptor && descriptor != input,
  )
  assert_eq(
    fixture.host.process_backing_descriptor(fixture.domain, process),
    Ok(descriptor),
  )
  let other = prepared_host(64L * page_bytes_ffi())
  assert_true(
    other.process_backing_descriptor(fixture.domain, process) is Err(_),
  )
  assert_false(process.closing)
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  assert_true(
    fixture.host.process_backing_descriptor(fixture.domain, process) is Err(_),
  )
  assert_eq(reply.backing_descriptor(), descriptor)
  installed_process_finish(fixture)
  other.try_close().unwrap()
}

///|
test "installed process retains the original slot until typed child stop and physical region cleanup" {
  let fixture = installed_process_fixture("installed-process-stopped-child")
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  process.holder.unwrap().spawn_duplex("/usr/bin/true", []).unwrap()
  fixture.domain.backing
  .bind_process_channel_child(fixture.host, process.region.unwrap())
  .unwrap()
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  for index = 0; index < 200 && process.stop is None; index = index + 1 {
    fixture.host.poll_process_stop(fixture.domain, process).unwrap() |> ignore
    if process.stop is None {
      assert_eq(process_test_sleep(1000), 0)
    }
  }
  assert_true(process.stop is Some(_))
  // Successful spawn handed the original slot FD to its Holder. The retained
  // typed stop, not Slot.is_open(), proves that the original pin is current.
  assert_false(process.slot.unwrap().is_open())
  process.stop.unwrap().require_current(process.holder.unwrap()).unwrap()
  fixture.host.retire_stopped_process(fixture.domain, process).unwrap()
  assert_true(
    process.closed && process.holder_closed && process.channel_retired,
  )
  assert_false(process.slot.unwrap().is_open())
  fixture.host.retire_stopped_process(fixture.domain, process).unwrap()
  assert_true(process.stop is Some(_) && fixture.domain.loan is Some(_))
  installed_process_finish(fixture)
}
