///|
struct ProcessChannelTestFixture {
  value : ProcessRegionTestFixture
  holder : @executor.NativeScopedExecutorHolder
  borrowed : @executor.NativeScopedDuplexBorrow
  channel : NativeBackedLiveChannel[BootstrapTestOriginal, BootstrapTestOriginal]
  frame : @resources.ImportedChildLedger
}

///|
fn process_channel_fixture(label : String) -> ProcessChannelTestFixture raise {
  let value = process_fixture(label)
  let holder = process_fixture_holder(label)
  let transport = holder.prepare_duplex().unwrap()
  let borrowed = transport.borrow_transport(holder).unwrap()
  let (writer, reader) = borrowed.parent_descriptors(holder).unwrap()
  let channel = match value.host.prepare_backed_live_channel_before_spawn(
    value.original, value.domain, value.child, reader, writer, 1L,
  ).unwrap() {
    PreparedLiveChannel(channel) => channel
    _ => fail("same original channel preparation failed")
  }
  let frame = value.host.prepare_backed_original_channel_ledger(
    value.original, channel,
  ).unwrap()
  value.host.start_backed_channel_ledger(value.original, channel, frame).unwrap()
  value.host.reserve_backed_channel_bootstrap(
    value.original, channel, frame, 0L, 32L * test_page_bytes_ffi(),
  ).unwrap()
  { value, holder, borrowed, channel, frame, }
}

///|
fn process_channel_binding(
  fixture : ProcessChannelTestFixture,
  descriptor : Int,
) -> NativeBackedProcessRegion[BootstrapTestOriginal, BootstrapTestOriginal] raise {
  let value = fixture.value
  match value.host.bind_prepared_process_channel_region(
    value.original, fixture.channel, fixture.holder, fixture.borrowed, descriptor,
  ).unwrap() {
    ProcessRegionReady(record) => record
    _ => fail("same original process/channel capture failed")
  }
}

///|
fn process_channel_unbound_finish(
  fixture : ProcessChannelTestFixture,
) -> Unit raise {
  let value = fixture.value
  value.host.stop_backed_live_channel_transport_use(
    value.original, fixture.channel,
  ).unwrap()
  fixture.borrowed.return_transport(fixture.holder).unwrap()
  assert_true(fixture.holder.cleanup())
  value.host.retire_backed_channel_bootstrap_after_owner_ack(
    value.original, fixture.channel, fixture.frame,
  ).unwrap()
  value.host.retire_backed_live_channel_after_owner_ack(
    value.original, fixture.channel,
  ).unwrap()
  process_fixture_finish(value)
}

///|
test "process channel binding rejects foreign holder and endpoint identities before capture" {
  let fixture = process_channel_fixture("process-channel-foreign")
  let value = fixture.value
  let foreign = process_fixture_holder("process-channel-other")
  let foreign_transport = foreign.prepare_duplex().unwrap()
  let foreign_borrow = foreign_transport.borrow_transport(foreign).unwrap()
  assert_true(value.host.bind_prepared_process_channel_region(
    value.original, fixture.channel, foreign, fixture.borrowed, value.descriptor,
  ) is Err(Process(@executor.NotHeld)))
  assert_true(value.domain.process_region is None)
  assert_true(value.host.bind_prepared_process_channel_region(
    value.original, fixture.channel, foreign, foreign_borrow, value.descriptor,
  ) is Err(Domain(Bootstrap(Physical(-1)))))
  assert_true(value.domain.process_region is None)
  assert_true(fixture.borrowed.require_current(fixture.holder) is Ok(_))
  foreign_borrow.return_transport(foreign).unwrap()
  assert_true(foreign.cleanup())
  process_channel_unbound_finish(fixture)
}

///|
test "unstarted process channel keeps generic refusal and requires transport restriction before return" {
  let fixture = process_channel_fixture("process-channel-unstarted")
  let value = fixture.value
  let record = process_channel_binding(fixture, value.descriptor)
  assert_true(value.host.require_backed_domain_current(
    value.original, value.domain, value.child,
  ) is Err(_))
  value.host.require_backed_channel_ledger_current(
    value.original, fixture.channel, fixture.frame,
  ).unwrap()
  value.host.require_backed_channel_bootstrap_current(
    value.original, fixture.channel, fixture.frame,
  ).unwrap()
  assert_true(value.host.return_process_channel_transport(
    value.original, record,
  ) is Err(Domain(Bootstrap(ReadersPending))))
  assert_false(fixture.holder.cleanup())
  value.host.stop_backed_live_channel_transport_use(
    value.original, fixture.channel,
  ).unwrap()
  value.host.return_process_channel_transport(value.original, record).unwrap()
  assert_true(fixture.borrowed.parent_descriptors(fixture.holder) is Err(_))
  assert_false(record.retired)
  assert_false(value.loan.physical_returned)
  value.host.abandon_prepared_process_region(value.original, record).unwrap()
  value.host.abandon_prepared_process_region(value.original, record).unwrap()
  assert_true(record.retired && record.pin_closed)
  assert_true(record.channel is None && record.transport is None)
  assert_true(fixture.channel.retired && value.domain.live_channel is None)
  assert_true(value.domain.read_use is None && value.domain.process_region is None)
  assert_false(value.domain.closed)
  process_fixture_finish(value)
}

///|
test "same process child and scoped stop precede channel metadata and original region retirement" {
  let fixture = process_channel_fixture("process-channel-started")
  let value = fixture.value
  let record = process_channel_binding(fixture, value.descriptor)
  assert_true(value.host.bind_process_channel_child(
    value.original, record,
  ) is Err(Process(@executor.InvalidConfiguration)))
  assert_false(fixture.channel.child_binding_attempted)
  fixture.holder.spawn_duplex("/usr/bin/true", []).unwrap()
  value.host.bind_process_channel_child(value.original, record).unwrap()
  assert_true(fixture.holder.poll_stop() is Err(@executor.Busy))
  assert_true(value.host.bind_process_channel_child(value.original, record) is Err(_))
  assert_false(record.physical_retired || record.retired)
  value.host.stop_backed_live_channel_transport_use(
    value.original, fixture.channel,
  ).unwrap()
  value.host.return_process_channel_transport(value.original, record).unwrap()
  let stop = process_fixture_stop(fixture.holder)
  assert_false(value.loan.physical_returned)
  value.host.retire_stopped_process_region(value.original, record, stop).unwrap()
  value.host.retire_stopped_process_region(value.original, record, stop).unwrap()
  assert_true(record.physical_retired && record.pin_closed && record.retired)
  assert_true(record.channel is None && record.transport is None)
  assert_true(value.domain.closed && value.domain.view.closed)
  assert_true(value.domain.view.domain is None && value.domain.process_region is None)
  assert_true(fixture.channel.retired && value.domain.live_channel is None)
  assert_true(value.domain.read_use is None)
  assert_false(value.loan.physical_returned)
  process_fixture_finish(value)
}

///|
test "failed same-channel descriptor capture retains original unstarted carrier and cleanup" {
  let fixture = process_channel_fixture("process-channel-pending")
  let value = fixture.value
  let record = match value.host.bind_prepared_process_channel_region(
    value.original, fixture.channel, fixture.holder, fixture.borrowed, -1,
  ).unwrap() {
    ProcessRegionPending(record, Domain(Bootstrap(Physical(-1)))) => record
    _ => fail("bad original capture did not retain its partial carrier")
  }
  assert_true(value.domain.process_region is Some(original) && physical_equal(original, record))
  assert_false(record.retired || record.pin_closed)
  value.host.stop_backed_live_channel_transport_use(
    value.original, fixture.channel,
  ).unwrap()
  value.host.return_process_channel_transport(value.original, record).unwrap()
  value.host.abandon_prepared_process_region(value.original, record).unwrap()
  assert_true(record.retired && fixture.channel.retired)
  assert_true(record.channel is None && record.transport is None)
  assert_true(value.domain.read_use is None && value.domain.process_region is None)
  process_fixture_finish(value)
}

///|
test "process channel excludes a parent read-context attempt without replacing its original frame" {
  let fixture = process_channel_fixture("process-channel-read-context")
  let value = fixture.value
  // Negative Owner-state fault: no C read context is allocated by this case.
  // The actual worker branch may never inherit a parent Root/Reader context.
  value.domain.read_attempted = true
  assert_true(value.host.bind_prepared_process_channel_region(
    value.original, fixture.channel, fixture.holder, fixture.borrowed, value.descriptor,
  ) is Err(Domain(Bootstrap(ReadersPending))))
  assert_true(value.domain.process_region is None)
  assert_true(fixture.channel.ledger_frame is Some(original) && physical_equal(original, fixture.frame))
  value.domain.read_attempted = false
  process_channel_unbound_finish(fixture)
}
