///|
fn native_transfer_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn native_transfer_request_for(
  chunks : Array[Bytes],
  route : @transfer.RemoteTransferRoute,
  transfer_attempt : String,
) -> @transfer.RemoteTransferRequest {
  let mut referenced_bytes = 0L
  for chunk in chunks {
    referenced_bytes = referenced_bytes + chunk.length().to_int64()
  }
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    native_transfer_cid("1"),
    native_transfer_cid("2"),
    native_transfer_cid("3"),
    chunks.length(),
    chunks.map(chunk => "sha256:" + @sha.hex(chunk)),
    chunks.map(chunk => chunk.length().to_int64()),
    chunks.map(_ => 1),
    8,
    4096,
    referenced_bytes,
  ).unwrap()
  @transfer.prepare_request(
    "native-coordinator",
    transfer_attempt,
    route,
    "native-source",
    2,
    "native-destination",
    3,
    "native-source-material",
    manifest,
    referenced_bytes,
    4102444800000L,
    native_transfer_cid("4"),
    native_transfer_cid("5"),
    native_transfer_cid("6"),
  ).unwrap()
}

///|
fn native_transfer_request(
  chunks : Array[Bytes],
  route : @transfer.RemoteTransferRoute,
) -> @transfer.RemoteTransferRequest {
  native_transfer_request_for(chunks, route, "native-transfer-1")
}

///|
fn native_direct_request(
  chunks : Array[Bytes],
) -> @transfer.RemoteTransferRequest {
  native_transfer_request(chunks, @transfer.DirectStream)
}

///|
fn native_transfer_issue_name(
  issue : NativeRemoteTransferClientIssue,
) -> String {
  match issue {
    InvalidRequest => "invalid-request"
    SourceMismatch => "source-mismatch"
    Rejected(_) => "rejected"
    Physical(_) => "physical"
    Durable(_) => "durable"
    Destination(_) => "destination"
    Protocol(_) => "protocol"
    ReconciliationRequired => "reconciliation-required"
    Consumer(_) => "consumer"
  }
}

///|
test "native direct destination owns exact durable generations" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/direct-destination.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let root = @filesystem.open_root(store_root).unwrap()
  let chunks = [b"direct-destination-alpha", b"direct-destination-beta"]
  let request = native_direct_request(chunks)
  let admitted = admit_durable_direct_destination(journal, request, 1024L, 8L).unwrap()
  assert_eq(
    @transfer.direct_transfer_progress(admitted),
    @transfer.DirectTransferCopying,
  )
  assert_true(
    write_durable_direct_destination_chunk(
      journal, root, request, 0, b"altered",
    )
    is Err(_),
  )
  match
    write_durable_direct_destination_chunk(journal, root, request, 0, chunks[0]) {
    Ok(_) => ()
    Err(issue) =>
      fail(
        "exact first direct destination chunk was rejected: " +
        native_transfer_issue_name(issue),
      )
  }
  assert_true(
    commit_durable_direct_destination(journal, root, request) is Err(_),
  )
  guard write_durable_direct_destination_chunk(
      journal,
      root,
      request,
      1,
      chunks[1],
    )
    is Ok(_) else {
    fail("exact second direct destination chunk was rejected")
  }
  guard commit_durable_direct_destination(journal, root, request)
    is Ok(committed) else {
    fail("complete direct destination was not committed")
  }
  assert_true(@transfer.record_is_destination_committed(committed))
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  guard admit_durable_direct_destination(reopened, request, 1024L, 8L)
    is Ok(replayed) else {
    fail("committed direct destination admission was not idempotent")
  }
  assert_true(@transfer.record_is_destination_committed(replayed))
  guard commit_durable_direct_destination(reopened, root, request)
    is Ok(recommitted) else {
    fail("committed direct destination retry was not idempotent")
  }
  assert_true(@transfer.record_is_destination_committed(recommitted))
  let retained_usage = reopened.destination_capacity_usage().unwrap()
  let cancelled_request = native_transfer_request_for(
    [b"direct-cancel-alpha", b"direct-cancel-beta"],
    @transfer.DirectStream,
    "native-transfer-cancel",
  )
  admit_durable_direct_destination(reopened, cancelled_request, 1024L, 8L).unwrap()
  |> ignore
  write_durable_direct_destination_chunk(
    reopened, root, cancelled_request, 0, b"direct-cancel-alpha",
  ).unwrap()
  |> ignore
  let cancelled = cancel_durable_direct_destination(
    reopened, root, cancelled_request,
  ).unwrap()
  assert_true(@transfer.direct_transfer_cleanup_confirmed(cancelled))
  let usage = reopened.destination_capacity_usage().unwrap()
  assert_eq(usage.reserved_bytes, retained_usage.reserved_bytes)
  assert_eq(usage.reserved_objects, retained_usage.reserved_objects)
  assert_true(reopened.close())
}

///|
test "native Transfer Store owns a sealed object across restart" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/native-transfer-store-object.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let root = @filesystem.open_root(store_root).unwrap()
  let chunks = [b"store-object-alpha", b"store-object-beta"]
  let request = native_transfer_request(chunks, @transfer.TransferStore)
  let admitted = admit_durable_store_object(journal, request, 1024L, 8L).unwrap()
  assert_eq(
    @transfer.store_upload_progress(admitted),
    @transfer.StoreUploadCopying,
  )
  assert_eq(durable_store_object_next_chunk(journal, root, request).unwrap(), 0)
  assert_true(
    write_durable_store_object_chunk(journal, root, request, 0, b"altered")
    is Err(SourceMismatch),
  )
  write_durable_store_object_chunk(journal, root, request, 0, chunks[0])
  |> ignore
  assert_eq(durable_store_object_next_chunk(journal, root, request).unwrap(), 1)
  assert_true(seal_durable_store_object(journal, root, request) is Err(_))
  write_durable_store_object_chunk(journal, root, request, 1, chunks[1])
  |> ignore
  let sealed_record = seal_durable_store_object(journal, root, request).unwrap()
  assert_eq(
    @transfer.store_upload_progress(sealed_record),
    @transfer.StoreUploadSealed,
  )
  assert_eq(
    read_durable_store_object_chunk(journal, root, request, 0, 1024).unwrap(),
    chunks[0],
  )
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let restored = admit_durable_store_object(reopened, request, 1024L, 8L).unwrap()
  assert_eq(
    @transfer.store_upload_progress(restored),
    @transfer.StoreUploadSealed,
  )
  assert_eq(
    durable_store_object_next_chunk(reopened, root, request).unwrap(),
    2,
  )
  assert_eq(
    read_durable_store_object_chunk(reopened, root, request, 1, 1024).unwrap(),
    chunks[1],
  )
  assert_true(reopened.close())
}

///|
test "native direct client sends admitted chunks over mTLS" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/direct-transfer.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let chunks = [b"alpha", @utf8.encode("日本語")]
  let request = native_direct_request(chunks)
  let record = send_durable_direct_transfer(
    journal, client, origin, request, chunks,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(record))
  assert_eq(
    @transfer.record_request_identity(record),
    @transfer.request_cid(request),
  )
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let restored = send_durable_direct_transfer(
    reopened, client, origin, request, chunks,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(restored))
  assert_true(reopened.close())
  assert_true(client.close())
}

///|
test "native direct client rejects altered chunks before network use" {
  let request = native_direct_request([b"alpha"])
  guard admit_direct_source(request, [b"other"]) is Err(SourceMismatch) else {
    fail("altered source chunk was accepted")
  }
}

///|
test "streaming source verifies bounded manifest chunks in order" {
  let chunks = [b"alpha", b"beta"]
  let request = native_direct_request(chunks)
  let mut reads = 0
  let mut finished = false
  let source = prepare_transfer_chunk_source(
    @transfer.request_projection(request)[6],
    @transfer.request_projection(request)[7],
    index => {
      if index != reads {
        return Err("unexpected-read-order")
      }
      reads = reads + 1
      Ok(chunks[index])
    },
    () => {
      finished = true
      Ok(())
    },
    () => Ok(()),
  ).unwrap()
  admit_chunk_source(request, source, "direct").unwrap()
  assert_eq(source.read_chunk(request).unwrap(), b"alpha")
  assert_eq(source.read_chunk(request).unwrap(), b"beta")
  source.finish_source(request).unwrap()
  assert_eq(reads, 2)
  assert_true(finished)
  assert_true(source.stopped)
}

///|
test "streaming send failure retains only unconfirmed source cleanup" {
  let request = native_direct_request([b"alpha"])
  let mut close_attempts = 0
  let source = prepare_transfer_chunk_source(
    @transfer.request_projection(request)[6],
    @transfer.request_projection(request)[7],
    _ => Ok(b"alpha"),
    () => Ok(()),
    () => {
      close_attempts = close_attempts + 1
      if close_attempts == 1 {
        Err("stop-unconfirmed")
      } else {
        Ok(())
      }
    },
  ).unwrap()
  let failure = failed_stream_send(SourceMismatch, source)
  assert_true(transfer_send_failure_issue(failure) is SourceMismatch)
  assert_true(transfer_send_failure_cleanup_pending(failure))
  assert_true(retry_transfer_send_failure_cleanup(failure))
  assert_false(transfer_send_failure_cleanup_pending(failure))
  assert_false(retry_transfer_send_failure_cleanup(failure))
  assert_eq(close_attempts, 2)
}

///|
test "durable direct cleanup waits for source stop and retries persistence" {
  let request = native_direct_request([b"alpha"])
  let mut close_attempts = 0
  let mut durable_attempts = 0
  let source = prepare_transfer_chunk_source(
    @transfer.request_projection(request)[6],
    @transfer.request_projection(request)[7],
    _ => Ok(b"alpha"),
    () => Ok(()),
    () => {
      close_attempts = close_attempts + 1
      if close_attempts < 3 {
        Err("stop-unconfirmed")
      } else {
        Ok(())
      }
    },
  ).unwrap()
  let failure = failed_durable_direct_stream_send(SourceMismatch, source, () => {
    durable_attempts = durable_attempts + 1
    durable_attempts >= 2
  })
  assert_true(transfer_send_failure_cleanup_pending(failure))
  assert_false(retry_transfer_send_failure_cleanup(failure))
  assert_eq(close_attempts, 2)
  assert_eq(durable_attempts, 0)
  assert_false(retry_transfer_send_failure_cleanup(failure))
  assert_eq(close_attempts, 3)
  assert_eq(durable_attempts, 1)
  assert_true(transfer_send_failure_cleanup_pending(failure))
  assert_true(retry_transfer_send_failure_cleanup(failure))
  assert_eq(close_attempts, 3)
  assert_eq(durable_attempts, 2)
  assert_false(transfer_send_failure_cleanup_pending(failure))
  assert_false(retry_transfer_send_failure_cleanup(failure))
}

///|
test "native direct failure persists confirmed remote cleanup" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal = @journal.open_journal(
    sqlite,
    sqlite_root + "/direct-transfer-cancel.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let chunks = [b"cancel-source"]
  let request = native_direct_request(chunks)
  guard send_durable_direct_transfer(journal, client, origin, request, chunks)
    is Err(Rejected(400)) else {
    fail("native direct failure did not preserve the physical rejection")
  }
  let cancelled = journal.require(request).unwrap()
  assert_true(@transfer.direct_transfer_cleanup_confirmed(cancelled))
  let restored = cancel_durable_direct_transfer(
    journal, client, origin, request,
  ).unwrap()
  assert_true(@transfer.direct_transfer_cleanup_confirmed(restored))
  assert_true(journal.close())
  assert_true(client.close())
}

///|
test "native direct journal waits for the local source to stop" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/direct-transfer-source-stop.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let chunks = [b"cancel-source"]
  let request = native_direct_request(chunks)
  let mut close_attempts = 0
  let source = prepare_transfer_chunk_source(
    @transfer.request_projection(request)[6],
    @transfer.request_projection(request)[7],
    _ => Ok(chunks[0]),
    () => Ok(()),
    () => {
      close_attempts = close_attempts + 1
      if close_attempts < 3 {
        Err("source-still-running")
      } else {
        Ok(())
      }
    },
  ).unwrap()
  guard send_durable_direct_transfer_from_source(
      journal, client, origin, request, source,
    )
    is Err(failure) else {
    fail("native direct failure did not retain its cleanup owner")
  }
  assert_true(transfer_send_failure_cleanup_pending(failure))
  assert_false(
    @transfer.direct_transfer_cleanup_confirmed(
      journal.require(request).unwrap(),
    ),
  )
  assert_false(retry_transfer_send_failure_cleanup(failure))
  assert_eq(close_attempts, 2)
  assert_false(
    @transfer.direct_transfer_cleanup_confirmed(
      journal.require(request).unwrap(),
    ),
  )
  assert_true(retry_transfer_send_failure_cleanup(failure))
  assert_eq(close_attempts, 3)
  assert_true(
    @transfer.direct_transfer_cleanup_confirmed(
      journal.require(request).unwrap(),
    ),
  )
  assert_false(transfer_send_failure_cleanup_pending(failure))
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  assert_true(
    @transfer.direct_transfer_cleanup_confirmed(
      reopened.require(request).unwrap(),
    ),
  )
  assert_true(reopened.close())
  assert_true(client.close())
}

///|
test "native direct retry reconciles a lost commit reply" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal = @journal.open_journal(
    sqlite,
    sqlite_root + "/direct-transfer-commit-loss.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let chunks = [b"commit-loss"]
  let request = native_direct_request(chunks)
  assert_true(
    send_durable_direct_transfer(journal, client, origin, request, chunks)
    is Err(ReconciliationRequired),
  )
  let uncertain = journal.require(request).unwrap()
  assert_eq(
    @transfer.direct_transfer_progress(uncertain),
    @transfer.DirectTransferCopying,
  )
  assert_false(@transfer.direct_transfer_cleanup_confirmed(uncertain))
  let committed = send_durable_direct_transfer(
    journal,
    client,
    origin,
    request,
    [],
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(committed))
  assert_true(journal.close())
  assert_true(client.close())
}

///|
test "native Store upload waits for commit and restores without source upload" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  let library = @http.load_library(path).unwrap()
  let client = library.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/store-upload.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let chunks = [b"store-alpha", @utf8.encode("保存")]
  let request = native_transfer_request(chunks, @transfer.TransferStore)
  let record = match
    send_durable_store_upload(journal, client, origin, request, chunks) {
    Ok(value) => value
    Err(InvalidRequest) => fail("native Store upload: invalid request")
    Err(SourceMismatch) => fail("native Store upload: source mismatch")
    Err(Rejected(status)) =>
      fail("native Store upload: rejected " + status.to_string())
    Err(Physical(_)) => fail("native Store upload: HTTP failure")
    Err(Durable(_)) => fail("native Store upload: journal failure")
    Err(Destination(_)) => fail("native Store upload: destination failure")
    Err(Protocol(_)) => fail("native Store upload: protocol failure")
    Err(Consumer(_)) => fail("native Store upload: consumer failure")
    Err(ReconciliationRequired) =>
      fail("native Store upload: reconciliation required")
  }
  assert_eq(
    @transfer.store_upload_progress(record),
    @transfer.StoreUploadCommitted,
  )
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let restored = send_durable_store_upload(reopened, client, origin, request, []).unwrap()
  assert_eq(
    @transfer.store_upload_progress(restored),
    @transfer.StoreUploadCommitted,
  )
  assert_true(reopened.close())
  let destination_root = @filesystem.open_root(store_root).unwrap()
  let failed_path = sqlite_root + "/store-destination-failed.sqlite"
  let failed_destination = @journal.open_journal(
    sqlite, failed_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  match
    receive_durable_store_transfer(
      failed_destination, client, destination_root, origin, request, "native-store-cancel",
      1048576L, 8L,
    ) {
    Err(SourceMismatch) => ()
    Err(Rejected(status)) =>
      fail("native Store failure setup: rejected " + status.to_string())
    Err(InvalidRequest) => fail("native Store failure setup: invalid request")
    Err(Physical(_)) => ()
    Err(Durable(_)) => fail("native Store failure setup: journal failure")
    Err(Destination(_)) =>
      fail("native Store failure setup: destination failure")
    Err(Protocol(_)) => fail("native Store failure setup: protocol failure")
    Err(Consumer(_)) => fail("native Store failure setup: consumer failure")
    Err(ReconciliationRequired) =>
      fail("native Store failure setup: reconciliation required")
    Ok(_) => fail("native Store failure setup unexpectedly succeeded")
  }
  let cancelled = cancel_durable_store_transfer(
    failed_destination, client, destination_root, origin, request, "native-store-cancel",
  ).unwrap()
  assert_eq(@transfer.record_projection(cancelled)[1], 4)
  assert_eq(@transfer.record_projection(cancelled)[4], 1)
  assert_eq(
    failed_destination.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  assert_true(failed_destination.close())
  let destination_path = sqlite_root + "/store-destination.sqlite"
  let destination = @journal.open_journal(
    sqlite, destination_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let completed = match
    receive_durable_store_transfer(
      destination, client, destination_root, origin, request, "native-store-use",
      1048576L, 8L,
    ) {
    Ok(value) => value
    Err(InvalidRequest) => fail("native Store download: invalid request")
    Err(SourceMismatch) => fail("native Store download: source mismatch")
    Err(Rejected(status)) =>
      fail("native Store download: rejected " + status.to_string())
    Err(Physical(_)) => fail("native Store download: HTTP failure")
    Err(Durable(_)) => fail("native Store download: journal failure")
    Err(Destination(_)) => fail("native Store download: destination failure")
    Err(Protocol(_)) => fail("native Store download: protocol failure")
    Err(Consumer(_)) => fail("native Store download: consumer failure")
    Err(ReconciliationRequired) =>
      fail("native Store download: reconciliation required")
  }
  assert_true(@transfer.record_is_destination_committed(completed))
  assert_true(destination.close())
  let destination_reopened = @journal.open_journal(
    sqlite, destination_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let completed_again = receive_durable_store_transfer(
    destination_reopened, client, destination_root, origin, request, "native-store-use",
    1048576L, 8L,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(completed_again))
  let receipt = destination_reopened
    .inspect_destination_receipt(request)
    .unwrap()
    .unwrap()
  let receipt_cid = @transfer.destination_receipt_cid(receipt)
  let first = pin_durable_store_destination_material(
    destination_reopened, destination_root, request, "native-store-use", "reader-first",
    receipt_cid,
  ).unwrap()
  validate_destination_material_use(first).unwrap()
  assert_true(destination_material_use_available(first))
  let stopped = stream_destination_material_use(first, 4, fn(_, _) {
    Err("consumer stopped")
  })
  assert_true(stopped is Err(Consumer("consumer stopped")))
  let delivered : Array[Byte] = []
  stream_destination_material_use(first, 4, fn(_, bytes) {
    for byte in bytes {
      delivered.push(byte)
    }
    Ok(())
  }).unwrap()
  let expected : Array[Byte] = []
  for chunk in chunks {
    for byte in chunk {
      expected.push(byte)
    }
  }
  assert_eq(Bytes::from_array(delivered), Bytes::from_array(expected))
  let second = pin_durable_store_destination_material(
    destination_reopened, destination_root, request, "native-store-use", "reader-second",
    receipt_cid,
  ).unwrap()
  validate_destination_material_use(second).unwrap()
  assert_true(
    reclaim_durable_store_destination_material(first)
    is Err(Durable(@journal.MaterialInUse)),
  )
  assert_true(release_destination_material_use(second).unwrap())
  assert_false(destination_material_use_available(second))
  assert_true(reclaim_durable_store_destination_material(first).unwrap())
  assert_eq(
    destination_reopened.destination_capacity_usage().unwrap().reserved_bytes,
    0L,
  )
  assert_true(destination_reopened.close())
  let reclaimed = @journal.open_journal(
    sqlite, destination_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  assert_true(
    pin_durable_store_destination_material(
      reclaimed, destination_root, request, "native-store-use", "reader-after-reclaim",
      receipt_cid,
    )
    is Err(Durable(@journal.RecoveryRequired)),
  )
  assert_true(reclaimed.close())
  assert_true(client.close())
}

///|
test "native Store cleanup follows durable destination ownership" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  let http = @http.load_library(path).unwrap()
  let client = http.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let root = @filesystem.open_root(store_root).unwrap()
  let foreign = @journal.open_journal(
    sqlite,
    sqlite_root + "/store-foreign-allocation.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let foreign_request = native_transfer_request(
    [b"foreign-target"],
    @transfer.TransferStore,
  )
  ignore(foreign.accept(foreign_request).unwrap())
  let foreign_final = destination_object_name(foreign_request, 0).unwrap()
  let foreign_staging = destination_staging_name(
    foreign_request, "foreign-use", 0,
  ).unwrap()
  let final_writer = root.create_writer("foreign-final-seed", 7L).unwrap()
  final_writer.append(b"foreign").unwrap()
  let final_generation = final_writer.seal(foreign_final).unwrap()
  let staging_writer = root.create_writer(foreign_staging, 7L).unwrap()
  staging_writer.append(b"foreign").unwrap()
  let staging_ownership = staging_writer.ownership()
  assert_true(
    cancel_durable_store_transfer(
      foreign, client, root, "https://unused.invalid", foreign_request, "foreign-use",
    )
    is Err(ReconciliationRequired),
  )
  assert_true(root.verify_generation(foreign_final, final_generation))
  guard root.inspect_generation(foreign_staging).unwrap() is Some(staging) else {
    fail("foreign staging generation disappeared")
  }
  assert_eq(staging.device, staging_ownership.device)
  assert_eq(staging.inode, staging_ownership.inode)
  staging_writer.cancel().unwrap()
  root.reclaim_generation(foreign_final, final_generation).unwrap()
  assert_true(foreign.close())
  let owned = @journal.open_journal(
    sqlite,
    sqlite_root + "/store-owned-allocation.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let owned_request = native_transfer_request(
    [b"owned-residual"],
    @transfer.TransferStore,
  )
  ignore(owned.accept(owned_request).unwrap())
  assert_true(
    owned.reserve_destination_holding(owned_request, 1024L, 8L).unwrap(),
  )
  let owned_final = destination_object_name(owned_request, 0).unwrap()
  let owned_staging = destination_staging_name(owned_request, "owned-use", 0).unwrap()
  let allocation = owned
    .prepare_destination_allocation(
      owned_request, "owned-use", 0, owned_staging, owned_final,
    )
    .unwrap()
  let writer = root.create_writer(owned_staging, 14L).unwrap()
  writer.append(b"owned-residual").unwrap()
  ignore(
    owned
    .record_destination_allocation_owned(allocation, writer.ownership())
    .unwrap(),
  )
  let cancelled = cancel_durable_store_transfer(
    owned, client, root, "https://unused.invalid", owned_request, "owned-use",
  ).unwrap()
  assert_eq(@transfer.record_projection(cancelled)[1], 4)
  assert_true(root.inspect_generation(owned_staging).unwrap() is None)
  assert_eq(owned.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  root.sync_directory().unwrap()
  assert_true(owned.close())
  assert_true(client.close())
}

///|
test "terminal Store retransmission keeps destination capacity released" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  let http = @http.load_library(path).unwrap()
  let client = http.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = sqlite_root + "/store-terminal-resend.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let root = @filesystem.open_root(store_root).unwrap()
  let request = native_transfer_request(
    [b"terminal-resend"],
    @transfer.TransferStore,
  )
  let (_, admitted) = journal.accept(request).unwrap()
  assert_true(journal.reserve_destination_holding(request, 1024L, 8L).unwrap())
  commit_durable_transition(
    journal,
    @transfer.prepare_failure(admitted, true, true).unwrap(),
  ).unwrap()
  let failed = journal.require(request).unwrap()
  commit_durable_transition(
    journal,
    @transfer.prepare_cleanup(failed, true, true, true).unwrap(),
  ).unwrap()
  assert_true(journal.release_destination_holding(request).unwrap())
  for attempt = 0; attempt < 3; attempt = attempt + 1 {
    assert_true(
      receive_durable_store_transfer(
        journal, client, root, "https://unused.invalid", request, "terminal-use",
        1024L, 8L,
      )
      is Err(ReconciliationRequired),
    )
    let usage = journal.destination_capacity_usage().unwrap()
    assert_eq(usage.reserved_bytes, 0L)
    assert_eq(usage.reserved_objects, 0L)
  }
  assert_true(journal.close())
  let reopened = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  assert_true(
    receive_durable_store_transfer(
      reopened, client, root, "https://unused.invalid", request, "terminal-use",
      1024L, 8L,
    )
    is Err(ReconciliationRequired),
  )
  assert_eq(reopened.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(reopened.close())
  assert_true(client.close())
}
