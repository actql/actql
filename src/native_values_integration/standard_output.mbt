// Shared Native fixture assertions; this package is imported only by tests.

///|
pub fn assert_native_remote_standard_output(
  runtime : @native_remote_runtime.NativeRemoteRuntime,
  journal : @native_remote_journal.Journal,
  request : @remote.DispatchRequest,
  input_binding : @remote.RemoteInputBinding,
  expected : String,
  retry_release? : Bool = false,
) -> Unit raise {
  let operation = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_dispatch_json(request, input_binding).unwrap(),
  ).unwrap()
  let acknowledge_acceptance = fn(request) {
    let (_, record) = journal.accept(request).unwrap()
    Ok(record)
  }
  let acknowledge_status = fn(request) {
    let observed = journal.observation(request).unwrap()
    Ok(Some(@native_remote_journal.recovered_site_dispatch_record(observed)))
  }
  guard @native_remote_agent.advance_native_outbound_operation(
      runtime,
      Some(operation),
      acknowledge_acceptance,
      acknowledge_status,
    )
    is Ok(
      @native_remote_agent.DispatchObserved(
        observed_dispatch,
        observed_completion,
        _
      )
    ) else {
    fail("standard remote dispatch was not observed")
  }
  assert_eq(
    @remote.dispatch_request_identity(observed_dispatch),
    @remote.dispatch_request_identity(request),
  )
  assert_eq(
    observed_completion.dispatch_request_cid,
    @remote.dispatch_request_identity(request),
  )
  let observed = journal.observation(request).unwrap()
  let subject = @native_remote_journal.recovered_site_dispatch_subject(observed).unwrap()
  let material_generation = @remote.remote_managed_output_subject_projection(
      subject,
    )[1]
  let reader = runtime
    .open_output_reader(request, material_generation, 7)
    .unwrap()
  let bytes : Array[Byte] = []
  while true {
    let chunk = reader.next().unwrap()
    for byte in chunk.bytes {
      bytes.push(byte)
    }
    if chunk.eof {
      break
    }
  }
  assert_eq(@utf8.decode_lossy(Bytes::from_array(bytes)), expected)
  assert_true(reader.finish().unwrap())
  let release = @remote.admit_remote_poll_operation_json(
    @remote.remote_poll_release_json(request).unwrap(),
  ).unwrap()
  if retry_release {
    guard @native_remote_agent.advance_native_outbound_operation(
        runtime,
        Some(release),
        acknowledge_acceptance,
        acknowledge_status,
      )
      is Err(
        @native_remote_agent.RuntimeObserved(
          @native_remote_runtime.CleanupPending("output"),
          _
        )
      ) else {
      fail("standard remote output release did not retain cleanup ownership")
    }
  }
  guard @native_remote_agent.advance_native_outbound_operation(
      runtime,
      Some(release),
      acknowledge_acceptance,
      acknowledge_status,
    )
    is Ok(@native_remote_agent.ReleaseObserved(released_identity, _)) else {
    fail("standard remote output release was not observed")
  }
  assert_eq(released_identity, @remote.dispatch_request_identity(request))
}
