// Durable reconciliation requires real Native SQLite and owned scratch.

///|
fn reconciliation_reply(
  request : @transfer.RemoteTransferRequest,
) -> @transfer.RemoteTransferRecord {
  let record = @transfer.open_record(request)
  @transfer.commit_transition(@transfer.prepare_start(record).unwrap(), true).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_source_settled(record, true, false).unwrap(),
    true,
  ).unwrap()
  |> ignore
  @transfer.commit_transition(
    @transfer.prepare_destination_commit(record).unwrap(),
    true,
  ).unwrap()
  |> ignore
  record
}

///|
fn reconciliation_case(name : String) -> Unit raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY") is Some(path) else {
    fail("real SQLite library is required")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("owned SQLite scratch is required")
  }
  let library = @sqlite.load_library(path).unwrap()
  let database_path = root +
    "/reconciliation-" +
    name +
    "-" +
    @env.now().to_string() +
    ".sqlite3"
  let journal = @journal.open_journal(
    library, database_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let request = native_transfer_request_for(
    [b"alpha"],
    @transfer.DirectStream,
    name,
  )
  if name != "missing" {
    let (_, original) = journal.accept(request).unwrap()
    journal
    .commit_transition(@transfer.prepare_start(original).unwrap())
    .unwrap()
  }
  let mut stopped = 0
  let mut reads = 0
  let mut queries = 0
  let mut authorized = true
  let source = prepare_transfer_chunk_source(
    @transfer.request_projection(request)[6],
    @transfer.request_projection(request)[7],
    _ => {
      reads += 1
      Err("unexpected-payload-read")
    },
    () => Err("unexpected-payload-finish"),
    () => {
      stopped += 1
      Ok(())
    },
  ).unwrap()
  let lock = library.open_database(database_path, 1048576L).unwrap()
  let query = () => {
    queries += 1
    if name == "lost-current" {
      authorized = false
    }
    if name == "concurrent-cancel" {
      let saved = journal.require(request).unwrap()
      journal
      .commit_transition(@transfer.prepare_failure(saved, true, true).unwrap())
      .unwrap()
    }
    if name == "save-failure" {
      lock.begin_immediate().unwrap()
    }
    if name == "uncommitted" {
      Ok(@transfer.open_record(request))
    } else if name == "foreign" {
      Ok(
        reconciliation_reply(
          native_transfer_request_for(
            [b"alpha"],
            @transfer.DirectStream,
            name + "-foreign",
          ),
        ),
      )
    } else {
      Ok(reconciliation_reply(request))
    }
  }
  let result = reconcile_durable_direct_operation(
    journal,
    request,
    source,
    () => authorized,
    query,
  )
  assert_eq(reads, 0)
  assert_eq(queries, if name == "missing" { 0 } else { 1 })
  if name == "committed" {
    assert_true(@transfer.record_is_destination_committed(result.unwrap()))
    let revision = @transfer.record_revision(journal.require(request).unwrap())
    assert_true(
      @transfer.record_is_destination_committed(
        reconcile_durable_direct_operation(
          journal,
          request,
          source,
          () => true,
          () => Ok(reconciliation_reply(request)),
        ).unwrap(),
      ),
    )
    assert_eq(
      @transfer.record_revision(journal.require(request).unwrap()),
      revision,
    )
    assert_eq(stopped, 1)
  } else if name == "save-failure" {
    assert_true(result is Err(Durable(_)))
    assert_eq(stopped, 1)
    assert_eq(
      @transfer.direct_transfer_progress(journal.require(request).unwrap()),
      @transfer.DirectTransferCopying,
    )
    lock.rollback().unwrap()
    assert_true(
      @transfer.record_is_destination_committed(
        reconcile_durable_direct_operation(
          journal,
          request,
          source,
          () => true,
          () => Ok(reconciliation_reply(request)),
        ).unwrap(),
      ),
    )
    assert_eq(stopped, 1)
  } else {
    assert_true(result is Err(_))
    if name == "concurrent-cancel" {
      assert_eq(
        @transfer.record_projection(journal.require(request).unwrap())[1],
        4,
      )
      assert_eq(stopped, 1)
    } else if name != "missing" {
      assert_eq(
        @transfer.direct_transfer_progress(journal.require(request).unwrap()),
        @transfer.DirectTransferCopying,
      )
      assert_eq(stopped, 0)
    }
    source.close_source().unwrap() |> ignore
  }
  assert_eq(reads, 0)
  lock.close()
  assert_true(journal.close())
}

///|
test "direct reconciliation commits without payload replay" {
  reconciliation_case("committed")
}

///|
test "direct reconciliation retains uncommitted destination" {
  reconciliation_case("uncommitted")
}

///|
test "direct reconciliation refuses foreign occurrence" {
  reconciliation_case("foreign")
}

///|
test "direct reconciliation rechecks current authority" {
  reconciliation_case("lost-current")
}

///|
test "direct reconciliation preserves concurrent cancellation" {
  reconciliation_case("concurrent-cancel")
}

///|
test "direct reconciliation retries persistence without double stop" {
  reconciliation_case("save-failure")
}

///|
test "direct reconciliation never admits missing sender" {
  reconciliation_case("missing")
}
