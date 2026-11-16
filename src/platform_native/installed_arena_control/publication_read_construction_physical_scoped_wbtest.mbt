///|
// A real original Read/SQLite Library component proof. This does not issue a
// publication, emulate the failed CLI's 512MiB case or acknowledge its Store.
priv struct PublicationReadReceiver {
  host : InstalledArenaHost
  read : InstalledArenaOriginalRead
  consumer : InstalledArenaOriginalReadConsumer
  library : @sqlite.Library
  mode : Int
  mut original : @sqlite.NativeStoreOperationOriginal?
  mut active : Bool
  mut cleanup : Bool
  mut calls : Int
  mut failure : InstalledArenaOriginalReadIssue?
}

///|
#borrow(library, receiver)
extern "C" fn publication_read_prepare_original(
  library : @sqlite.Library,
  receiver : PublicationReadReceiver,
  route : FuncRef[(PublicationReadReceiver, @sqlite.Library, Int) -> Int],
  delivery : FuncRef[(PublicationReadReceiver, @sqlite.Library, Int) -> Int],
  preparation : FuncRef[
    (PublicationReadReceiver, @sqlite.Library, Int, Int, Int, Int) -> Int,
  ],
  publication : FuncRef[
    (PublicationReadReceiver, @sqlite.Library, Int64, Int64, Int64, Int) -> Int,
  ],
) -> @sqlite.NativeStoreOperationOriginal = "actql_native_sqlite_prepare_store_operation_with_publication_construction"

///|
fn publication_read_route(
  receiver : PublicationReadReceiver,
  library : @sqlite.Library,
  tag : Int,
) -> Int {
  if !physical_equal(library, receiver.library) {
    return 21
  }
  match tag {
    -1 =>
      if receiver.host.require_domain_original_read_consumer_current(
          receiver.consumer,
        )
        is Ok(_) {
        0
      } else {
        22
      }
    0 => {
      if receiver.active ||
        receiver.cleanup ||
        receiver.host.enter_domain_original_read_consumer(receiver.consumer)
        is Err(_) {
        return 23
      }
      receiver.active = true
      0
    }
    3 => {
      if !receiver.active {
        return 24
      }
      let result = if receiver.cleanup {
        receiver.host.leave_domain_original_read(receiver.read)
      } else {
        receiver.host.leave_domain_original_read_consumer(receiver.consumer)
      }
      if result is Err(_) {
        return 25
      }
      receiver.active = false
      0
    }
    4 => {
      // Reconcile the actual old entry before entering the original cleanup
      // context. A caller Bool is never a physical leave/cleanup ACK.
      if receiver.active {
        if receiver.host.leave_domain_original_read_consumer(receiver.consumer)
          is Err(_) {
          return 26
        }
        receiver.active = false
      }
      if receiver.host.enter_domain_original_read_cleanup(receiver.read)
        is Err(_) {
        return 27
      }
      receiver.cleanup = true
      receiver.active = true
      0
    }
    _ => 28
  }
}

///|
fn publication_read_fund(
  receiver : PublicationReadReceiver,
  library : @sqlite.Library,
  r : Int64,
  e : Int64,
  raw : Int64,
  _retained_output : Int,
) -> Int {
  receiver.calls += 1
  if !physical_equal(library, receiver.library) ||
    !receiver.active ||
    receiver.cleanup {
    return 31
  }
  if receiver.mode == 2 {
    // The same bridge observes reentry itself. Returning zero cannot erase
    // the latched original failure or turn it into allocation authority.
    receiver.original.unwrap().enter_store() |> ignore
    return 0
  }
  match
    receiver.host.prepare_domain_original_read_construction(
      receiver.read,
      r,
      e,
      raw,
    ) {
    Ok(_) => 0
    Err(issue) => {
      receiver.failure = Some(issue)
      32
    }
  }
}

///|
fn publication_read_original_work(
  host : InstalledArenaHost,
  sqlite : InstalledArenaSqliteLibrary,
  mode : Int,
) -> Bool raise {
  let read = match
    host
    .prepare_domain_original_read(sqlite.domain, {
      bootstrap_retained: 16384L,
      bootstrap_execution: 8192L,
      workspace_execution: 65536L,
      read_retained: 65536L,
      read_execution: 131072L,
    })
    .unwrap() {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) => fail("publication Read preparation pending")
  }
  let consumer = host
    .prepare_domain_original_read_consumer(read, 8192L, 16384L)
    .unwrap()
  let receiver : PublicationReadReceiver = {
    host,
    read,
    consumer,
    library: sqlite.library.unwrap(),
    mode,
    original: None,
    active: false,
    cleanup: false,
    calls: 0,
    failure: None,
  }
  let original = publication_read_prepare_original(
    receiver.library,
    receiver,
    fn(receiver, library, tag) {
      publication_read_route(receiver, library, tag)
    },
    fn(_, _, _) { 41 },
    fn(_, _, _, _, _, _) { 42 },
    fn(receiver, library, r, e, raw, output) {
      publication_read_fund(receiver, library, r, e, raw, output)
    },
  )
  receiver.original = Some(original)
  original.activate().unwrap()
  // Outside the original flight no callback or allocation is attempted.
  assert_true(original.has_publication_constructor() is Err(_))
  assert_true(original.prepare_publication_scaffold() is Err(_))
  assert_eq(receiver.calls, 0)
  assert_eq(original.primary_code(), 0)
  original.enter_store().unwrap()
  assert_eq(original.has_publication_constructor().unwrap(), true)
  let initial_r = read.funded_retained_bytes
  let initial_e = read.funded_execution_bytes
  if mode == 2 {
    assert_true(original.prepare_publication_scaffold() is Err(_))
    assert_eq(original.primary_code(), -2)
    assert_eq(read.funded_retained_bytes, initial_r)
    assert_eq(read.funded_execution_bytes, initial_e)
  } else {
    original.prepare_publication_scaffold().unwrap()
    let raw = @sqlite.publication_construction_block_bound(7, 31, 0)
    assert_true(raw > 0L)
    original.prepare_publication_construction(2048L, 8192L, raw, false).unwrap()
    assert_eq(
      read.funded_retained_bytes,
      consumer.initial_retained_bytes + 2048L,
    )
    assert_eq(
      read.funded_execution_bytes,
      consumer.initial_execution_bytes + 8192L,
    )
    let funded_r = read.funded_retained_bytes
    let funded_e = read.funded_execution_bytes
    original.prepare_publication_construction(0L, 0L, raw, false).unwrap()
    assert_eq(read.funded_retained_bytes, funded_r)
    assert_eq(read.funded_execution_bytes, funded_e)
    assert_true(receiver.failure is None)
    if mode == 0 {
      // The closed index evaluator is prepaid before any numeric recipe is
      // evaluated; it grows this SAME original, without replacing the loan.
      original.prepare_publication_scaffold(index=true).unwrap()
      assert_true(read.funded_retained_bytes > funded_r)
      assert_true(read.funded_execution_bytes > funded_e)
      assert_true(physical_equal(read.consumer.unwrap(), consumer))
    }
    if mode == 1 {
      // Genuine policy excess on this SAME finite Read, before construction.
      assert_true(
        original.prepare_publication_construction(
          2048L,
          512L * domain_page_bytes(),
          raw,
          false,
        )
        is Err(_),
      )
      assert_true(receiver.failure is Some(_))
      assert_eq(read.funded_retained_bytes, funded_r)
      assert_eq(read.funded_execution_bytes, funded_e)
      assert_eq(original.primary_code(), 32)
    }
  }
  if mode != 0 {
    let calls = receiver.calls
    assert_true(original.prepare_publication_scaffold() is Err(_))
    assert_eq(receiver.calls, calls)
    assert_true(original.leave_store() is Err(_))
    original.enter_cleanup().unwrap()
    assert_true(original.prepare_publication_scaffold() is Err(_))
  }
  original.leave_store().unwrap()
  original.close_checked().unwrap()
  receiver.original = None
  // Retire the observed failure DATA only after the original bridge's actual
  // return/close acknowledgements. This cannot revive its normal duty.
  receiver.failure = None
  assert_true(original.prepare_publication_scaffold() is Err(_))
  host.close_domain_original_read(read).unwrap()
  assert_true(read.closed && read.consumer is None)
  !receiver.active
}

///|
test "publication constructor funds only its same actual Read and preserves its maximum" {
  store_wal_physical_case(false, publication_probe=1)
}

///|
test "publication constructor keeps its failed finite Read prefix and actual cleanup duty" {
  store_wal_physical_case(false, publication_probe=2)
}

///|
test "publication constructor reentry cannot be hidden by a successful callback result" {
  store_wal_physical_case(false, publication_probe=3)
}
