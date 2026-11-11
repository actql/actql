///|
// Actual Native Request issuer and one Common Source read of its same frame.
// This exercises the existing nonmanaged child-read alternative, not a
// Request-to-managed-Run transfer or an installed reader funding certificate.
test "actual Native Request Source wrapper accepts only its original frame" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "source-frame-original",
  )
  let input = Ref(81)
  let live = match host.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("Source Request live pending")
  }
  let initial = host.prepare_request_admission(live, input).unwrap()
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let read = @client.begin_installed_source_read(frame).unwrap()
  assert_true(@client.begin_installed_source_read(frame) is Err(_))
  assert_true(
    @native_client.check_native_client_request_source_read(
      host, live, input, read,
    )
    is Err(_),
  )
  let foreign = { ..host, }
  host.enter_domain_read(domain).unwrap()
  @native_client.check_native_client_request_source_read(
    host, live, input, read,
  ).unwrap()
  assert_true(
    @native_client.check_native_client_request_source_read(
      foreign, live, input, read,
    )
    is Err(_),
  )
  assert_true(
    @native_client.check_native_client_request_source_read(
      host,
      live,
      Ref(81),
      read,
    )
    is Err(_),
  )
  let observation = @client.check_installed_source_read_frame(read, frame).unwrap()
  @client.retire_installed_source_read(read).unwrap()
  // The real physical frame can remain current after only Common read
  // retirement. Its subsequent callback-free finish must still refuse.
  let same = host.borrow_request_read_frame(live, input).unwrap()
  assert_true(physical_equal(same, frame))
  assert_true(
    @client.check_installed_source_read_frame_retained(observation, read, same)
    is Err(_),
  )
  assert_true(
    @native_client.check_native_client_request_source_read(
      host, live, input, read,
    )
    is Err(_),
  )
  host.leave_domain_read(domain).unwrap()
  host.close_request_preparation(live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  @client.retire_installed_source_read(read).unwrap()
  host.close_request_preparation(live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  initialization_physical_finish(host, domain, descriptor)
}

///|
test "actual Native Request Source wrapper refuses another live Request frame" {
  let (host, domain, descriptor) = initialization_physical_fixture(
    "source-frame-left",
  )
  let (other, other_domain, other_descriptor) = initialization_physical_fixture(
    "source-frame-right",
  )
  let input = Ref(91)
  let other_input = Ref(92)
  let live = match host.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("left Source Request pending")
  }
  let other_live = match
    other.prepare_domain_request_child(other_domain, other_input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) => fail("right Source Request pending")
  }
  let initial = host.prepare_request_admission(live, input).unwrap()
  let other_initial = other
    .prepare_request_admission(other_live, other_input)
    .unwrap()
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let other_frame = @resources.backed_preparation_original_frame(
    other_initial, other_input,
  ).unwrap()
  let read = @client.begin_installed_source_read(frame).unwrap()
  let other_read = @client.begin_installed_source_read(other_frame).unwrap()
  host.enter_domain_read(domain).unwrap()
  @native_client.check_native_client_request_source_read(
    host, live, input, read,
  ).unwrap()
  assert_true(
    @native_client.check_native_client_request_source_read(
      host, live, input, other_read,
    )
    is Err(_),
  )
  host.leave_domain_read(domain).unwrap()
  @client.retire_installed_source_read(read).unwrap()
  @client.retire_installed_source_read(other_read).unwrap()
  host.close_request_preparation(live).unwrap()
  other.close_request_preparation(other_live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  @resources.cleanup_backed_preparation_admission(other_initial).unwrap()
  initialization_physical_finish(host, domain, descriptor)
  initialization_physical_finish(other, other_domain, other_descriptor)
}
