///|
test "Native Result service rejects unsupported frame limits before admission or delivery" {
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_root(root_path).unwrap()
  let name = "sink-invalid-limits-" + @env.now().to_string()
  parent.create_directory(name).unwrap() |> ignore
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let store = @store.open_store(
    library,
    root_path + "/" + name,
    native_access_cid(name),
    256L,
    8L,
    65536L,
  ).unwrap()
  let calls = Ref(0)
  let authority = install_native_result_access_authority(
    _ => {
      calls.val += 1
      true
    },
    _ => {
      calls.val += 1
      None
    },
    _ => {
      calls.val += 1
      true
    },
  )
  let now = () => {
    calls.val += 1
    "2026-09-20T01:00:00.000Z"
  }
  for
    limits in [
      (0, 128, 3),
      (65, 128, 3),
      (32, 16777217, 3),
      (32, 128, 16777217),
    ] {
    let (depth, row_bytes, chunk_bytes) = limits
    assert_true(
      install_native_result_access_service(
        store, authority, now, 65536, 4096, depth, row_bytes, chunk_bytes,
      )
      is Err(InvalidRequest),
    )
  }
  assert_true(
    install_native_result_access_service(
      store, authority, now, 65536, 4096, 64, 128, 3,
    )
    is Ok(_),
  )
  assert_eq(calls.val, 0)
  assert_true(store.close().unwrap())
}

///|
fn sink_access_case(
  case : String,
) -> (@store.Store, NativeResultAccessSession, Ref[Bool]) {
  let root_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let parent = @filesystem.open_root(root_path).unwrap()
  let name = "sink-" + case + "-" + @env.now().to_string()
  parent.create_directory(name).unwrap() |> ignore
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let authority = native_access_cid(name + "-store")
  let store = @store.open_store(
    library,
    root_path + "/" + name,
    authority,
    256L,
    8L,
    65536L,
  ).unwrap()
  let fixture = native_access_fixture(store, authority, name)
  commit_access_fixture(store, fixture)
  let receipt_allowed = Ref(true)
  let policy = install_native_result_access_authority(
    request => request.principal_id == "principal",
    _ => {
      Some({
        authorization_context_cid: native_access_cid(name + "-auth"),
        data_ceiling_cid: native_access_cid(name + "-ceiling"),
        egress_admission_cid: native_access_cid(name + "-egress"),
        expires_at: "2026-09-21T00:00:00.000Z",
        max_bytes: 64,
        max_uses: 1,
      })
    },
    facts => facts.stage != "receipt" || receipt_allowed.val,
  )
  let service = install_native_result_access_service(
    store,
    policy,
    () => "2026-09-20T01:00:00.000Z",
    65536,
    4096,
    32,
    65536,
    3,
  ).unwrap()
  let session = open_native_result_access(service, {
    namespace_id: "namespace_id",
    authority_scope_cid: fixture.authority_scope_cid,
    run_definition_cid: @publication.publication_contract_identity(
      fixture.run_definition,
    ),
    principal_id: "principal",
    purpose: "download",
    result_name: "answer",
    format: "jsonl",
    attempt_id: name + "-original-attempt",
  }).unwrap()
  (store, session, receipt_allowed)
}

///|
test "Native sink completes exact bounded output only after durable receipt and never rewrites on replay" {
  let (store, session, _) = sink_access_case("complete")
  let output : Array[Byte] = []
  let finish_calls = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    12,
    bytes => {
      for byte in bytes {
        output.push(byte)
      }
      SinkChunkConfirmed
    },
    () => {
      finish_calls.val += 1
      true
    },
  ).unwrap()
  let mut receipt = None
  for _ in 0..<40 {
    match sink.poll().unwrap() {
      SinkComplete(value) => {
        receipt = Some(value)
        break
      }
      SinkProgress => ()
      SinkFailed(_, _) => abort("normal sink must complete")
    }
  }
  assert_eq(@utf8.decode(Bytes::from_array(output)), "{\"value\":7}\n")
  assert_eq(finish_calls.val, 1)
  guard receipt is Some(receipt) else { fail("finite sink did not complete") }
  assert_eq(receipt.confirmed_bytes, 12L)
  assert_true(sink.poll() is Ok(SinkComplete(_)))
  assert_eq(output.length(), 12)
  assert_eq(finish_calls.val, 1)
  sink.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native sink exact failed prefix and unconfirmed exposure stay failed without another write" {
  let (store, session, _) = sink_access_case("failed-prefix")
  let writes = Ref(0)
  let finishes = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    64,
    _ => {
      writes.val += 1
      SinkChunkFailed(2, 1)
    },
    () => {
      finishes.val += 1
      true
    },
  ).unwrap()
  assert_true(sink.poll() is Ok(SinkProgress))
  guard sink.poll() is Ok(SinkFailed(SinkWriteFailed, record)) else {
    fail("failed prefix not retained")
  }
  assert_eq(record.confirmed_bytes, 2L)
  assert_eq(record.state, "failed")
  assert_true(sink.poll() is Ok(SinkFailed(SinkWriteFailed, _)))
  assert_eq(writes.val, 1)
  assert_eq(finishes.val, 0)
  sink.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native sink receipt denial retains the original session and retries no physical output" {
  let (store, session, allowed) = sink_access_case("receipt-denied")
  allowed.val = false
  let written = Ref(0)
  let finishes = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    64,
    bytes => {
      written.val += bytes.length()
      SinkChunkConfirmed
    },
    () => {
      finishes.val += 1
      true
    },
  ).unwrap()
  let mut blocked = false
  for _ in 0..<40 {
    match sink.poll() {
      Err(Access(AccessDenied)) => {
        blocked = true
        break
      }
      Ok(SinkProgress) => ()
      _ => fail("unconfirmed receipt cannot be completion")
    }
  }
  assert_true(blocked)
  assert_eq(written.val, 12)
  assert_eq(finishes.val, 1)
  allowed.val = true
  guard sink.poll() is Ok(SinkComplete(receipt)) else {
    fail("original receipt retry failed")
  }
  assert_eq(receipt.delivery_attempt_cid, session.attempt_cid())
  assert_eq(written.val, 12)
  assert_eq(finishes.val, 1)
  sink.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native sink output limit does not expose the private probe byte or finish a partial read" {
  let (store, session, _) = sink_access_case("output-limit")
  let written = Ref(0)
  let finishes = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    5,
    bytes => {
      written.val += bytes.length()
      SinkChunkConfirmed
    },
    () => {
      finishes.val += 1
      true
    },
  ).unwrap()
  let mut stopped = false
  for _ in 0..<40 {
    match sink.poll().unwrap() {
      SinkFailed(SinkOutputLimit, record) => {
        assert_eq(record.confirmed_bytes, 5L)
        stopped = true
        break
      }
      SinkProgress => ()
      _ => fail("bounded prefix cannot be success")
    }
  }
  assert_true(stopped)
  assert_eq(written.val, 5)
  assert_eq(finishes.val, 0)
  sink.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native sink finish failure cannot certify complete output" {
  let (store, session, _) = sink_access_case("finish-failed")
  let written = Ref(0)
  let finishes = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    64,
    bytes => {
      written.val += bytes.length()
      SinkChunkConfirmed
    },
    () => {
      finishes.val += 1
      false
    },
  ).unwrap()
  let mut failed = false
  for _ in 0..<40 {
    match sink.poll().unwrap() {
      SinkFailed(SinkFinishFailed, record) => {
        assert_eq(record.confirmed_bytes, 12L)
        assert_eq(record.state, "failed")
        failed = true
        break
      }
      SinkProgress => ()
      _ => fail("failed sink finish cannot be completion")
    }
  }
  assert_true(failed)
  assert_eq(written.val, 12)
  assert_eq(finishes.val, 1)
  assert_true(sink.poll() is Ok(SinkFailed(SinkFinishFailed, _)))
  assert_eq(finishes.val, 1)
  sink.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native sink invalid prefix claim never enters receipt or another physical write" {
  let (store, session, _) = sink_access_case("invalid-prefix")
  let writes = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    64,
    bytes => {
      writes.val += 1
      SinkChunkFailed(bytes.length() + 1, 0)
    },
    () => true,
  ).unwrap()
  assert_true(sink.poll() is Ok(SinkProgress))
  guard sink.poll() is Ok(SinkFailed(InvalidSinkWrite, failure)) else {
    fail("invalid sink claim not refused")
  }
  assert_eq(failure.confirmed_bytes, 0L)
  assert_eq(writes.val, 1)
  sink.close().unwrap()
  assert_true(store.close().unwrap())
}

///|
test "Native sink early close does not imply completion or permit a later write" {
  let (store, session, _) = sink_access_case("early-close")
  let writes = Ref(0)
  let finishes = Ref(0)
  let sink = install_native_result_sink(
    session,
    3,
    64,
    _ => {
      writes.val += 1
      SinkChunkConfirmed
    },
    () => {
      finishes.val += 1
      true
    },
  ).unwrap()
  sink.close().unwrap()
  sink.close().unwrap()
  assert_true(sink.poll() is Err(Access(InvalidProgress)))
  assert_eq(writes.val, 0)
  assert_eq(finishes.val, 0)
  assert_true(store.close().unwrap())
}
