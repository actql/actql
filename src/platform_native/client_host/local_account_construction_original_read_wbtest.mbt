///|
// These cases consume the existing real paired Native Read fixture. They are
// normal Native regressions; compiling them is not an executed-runtime claim.
fn account_original_read_source(
  name : String,
) -> NativeLocalExistingAdoptionInput {
  let input = adoption_capture_test_input(name)
  let root = @filesystem.open_private_root(input.source_path).unwrap()
  let body = @utf8.encode(
    " ".repeat(1048577) +
    (@utf8.decode(local_selected_account) catch {
      _ => abort("invalid fixture UTF8")
    }),
  )
  let writer = root
    .create_writer(name + ".stage", body.length().to_int64())
    .unwrap()
  writer.append(body).unwrap()
  writer.seal(input.source_name).unwrap() |> ignore
  root.close().unwrap()
  input
}

///|
fn account_original_read_capture_case(
  fixture : JournalMetadataOriginalReadFixture,
  input : NativeLocalExistingAdoptionInput,
  operation : (NativeLocalAdoptionCapture) -> Int raise,
) -> Int raise {
  let capture = prepare_native_local_initial_adoption_capture_in_current_read_context(
    input,
    epoch_test_crypto(),
    256,
  ).unwrap()
  // Each direct case consumes/asserts its expected primary before returning
  // this stable scalar. It is not an escaped Read-owned error or permission.
  let primary = operation(capture)
  println("ACTQL_NATIVE_ACCOUNT_PRIMARY observed=\{primary}")
  fixture.original
  .stage(
    @arena.HostRead,
    fn() {
      match capture.close().issue() {
        None => Ok(())
        Some(AdoptionOriginal(issue)) => Err(issue)
        Some(_) => Err(CustodyLost)
      }
    },
    cleanup=true,
  )
  .unwrap()
  assert_true(capture.descriptor_cleanup_acknowledged())
  // The fixture has consumed this diagnostic; release only that DATA alias
  // after actual capture ACK. Funding/metadata_retained stays until Read close.
  // This is not a product rule discarding another caller's unconsumed error.
  fixture.original.account_construction_issue = None
  // Returning drops capture/session/failure and operation-local aliases before
  // the caller makes its FIRST pair/Read close. No GC or close retry is used.
  primary
}

///|
fn account_original_read_close_fixture(
  fixture : JournalMetadataOriginalReadFixture,
) -> Unit {
  fixture.journal.val = None
  fixture.original
  .stage(
    @arena.HostSqlite,
    fn() {
      fixture.database.val
      .unwrap()
      .close_checked()
      .map_err(issue => Physical(issue))
    },
    cleanup=true,
  )
  .unwrap()
  fixture.database.val = None
  fixture.host.close_local_host_resources(fixture.pair).unwrap()
  fixture.host.close_domain_after_owner_ack(fixture.sqlite_domain).unwrap()
  fixture.host.close_domain_after_owner_ack(fixture.read_domain).unwrap()
  fixture.host.try_close().unwrap()
}

///|
test "Account construction uses sufficient same original Read above one MiB and rereads current generation" {
  let input = account_original_read_source("account-original-read-large")
  // Reuse this existing bounded fixture: standalone intake must refuse before
  // acquiring a Reader or copying its >one-MiB body. The SAME funded read below
  // still admits it, so this is not a new Account grammar/physical size cap.
  let legacy_root = @filesystem.open_private_root(input.source_path).unwrap()
  assert_true(
    local_account_read(legacy_root, input.source_name, None, None)
    is Err(ConfigurationLimit),
  )
  assert_true(
    local_account_read(legacy_root, input.source_name, Some(2097152L), None)
    is Err(ConfigurationLimit),
  )
  let funded_calls = Ref(0)
  assert_true(
    local_account_read(
      legacy_root,
      input.source_name,
      Some(1L),
      Some(_ => {
        funded_calls.val += 1
        true
      }),
    )
    is Err(ConfigurationLimit),
  )
  assert_eq(funded_calls.val, 0)
  legacy_root.close().unwrap()
  let fixture = journal_metadata_original_read_fixture(retained_limit=8388608L)
  let primary = account_original_read_capture_case(fixture, input, capture => {
    fixture.original
    .stage(@arena.HostRead, fn() {
      match
        capture
        .open(
          construction=Some(value => {
            fixture.original.prepare_account_construction(value)
          }),
        )
        .issue() {
        None => Ok(())
        Some(AdoptionOriginal(issue)) => Err(issue)
        Some(_) => Err(CustodyLost)
      }
    })
    .unwrap()
    let session = capture.original_session().unwrap()
    assert_true(session.source_body.length() > 1048576)
    assert_true(
      session.configuration.retains_original_bytes(session.source_body),
    )
    assert_true(physical_equal(fixture.original.read, fixture.read))
    // A later original Journal must keep the actual Account prefix alongside
    // its first row constructor, even though no new Account parse is required.
    let prefix = fixture.original.metadata_retained
    let prepared_journal = prepare_native_local_journal_capture_with_original_resources(
      session,
      fixture.host,
      fixture.pair,
      fixture.read,
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
      metadata_retained=prefix,
    )
    assert_eq(
      prepared_journal.original_resources.unwrap().metadata_retained,
      prefix,
    )
    fixture.original
    .stage(@arena.HostRead, fn() {
      session.stage_configuration(
        construction=Some(value => {
          fixture.original.prepare_account_construction(value)
        }),
      )
    })
    .unwrap()
    fixture.original
    .stage(@arena.HostRead, fn() {
      session.check_original(
        construction=Some(value => {
          fixture.original.prepare_account_construction(value)
        }),
      )
    })
    .unwrap()
    // Replace the selected path while keeping the held original. Neither cached
    // admission nor an old callback can turn this new generation into current.
    let root = @filesystem.open_private_root(input.source_path).unwrap()
    root
    .reclaim_generation(input.source_name, session.source_generation)
    .unwrap()
    let writer = root
      .create_writer(
        "account-original-read-replaced.stage",
        session.source_body.length().to_int64(),
      )
      .unwrap()
    writer.append(session.source_body).unwrap()
    writer.seal(input.source_name).unwrap() |> ignore
    root.close().unwrap()
    assert_true(
      fixture.original.stage(@arena.HostRead, fn() {
        session.check_original(
          construction=Some(value => {
            fixture.original.prepare_account_construction(value)
          }),
        )
      })
      is Err(SourceChanged),
    )
    6
  })
  assert_eq(primary, 6)
  account_original_read_close_fixture(fixture)
}

///|
test "Account construction tiny same Read refuses before variable intake and retains original cleanup" {
  let input = account_original_read_source("account-original-read-small")
  let fixture = journal_metadata_original_read_fixture(retained_limit=262144L)
  let primary = account_original_read_capture_case(fixture, input, capture => {
    assert_true(
      fixture.original.stage(@arena.HostRead, fn() {
        match
          capture
          .open(
            construction=Some(value => {
              fixture.original.prepare_account_construction(value)
            }),
          )
          .issue() {
          None => Ok(())
          Some(AdoptionOriginal(issue)) => Err(issue)
          Some(_) => Err(CustodyLost)
        }
      })
      is Err(OriginalResources(@arena.Read(_))),
    )
    assert_true(capture.original_session() is None)
    let failure = capture.original_failure().unwrap()
    assert_true(failure.source_root is Some(_))
    assert_true(
      failure.parent is None && failure.root is None && failure.lock is None,
    )
    assert_true(
      fixture.original.account_construction_issue
      is Some(OriginalResources(@arena.Read(_))),
    )
    assert_true(physical_equal(capture.original_failure().unwrap(), failure))
    23
  })
  assert_eq(primary, 23)
  account_original_read_close_fixture(fixture)
}

///|
test "Account construction funded original still refuses foreign Account before state creation" {
  let selected = account_original_read_source("account-original-read-foreign")
  let input = { ..selected, account_id: "foreign-account", }
  let fixture = journal_metadata_original_read_fixture(retained_limit=8388608L)
  let primary = account_original_read_capture_case(fixture, input, capture => {
    assert_true(
      fixture.original.stage(@arena.HostRead, fn() {
        match
          capture
          .open(
            construction=Some(value => {
              fixture.original.prepare_account_construction(value)
            }),
          )
          .issue() {
          None => Ok(())
          Some(AdoptionOriginal(issue)) => Err(issue)
          Some(_) => Err(CustodyLost)
        }
      })
      is Err(ForeignAccount),
    )
    assert_true(capture.original_session() is None)
    assert_true(capture.original_failure().unwrap().parent is None)
    assert_true(fixture.original.account_construction_issue is None)
    3
  })
  assert_eq(primary, 3)
  account_original_read_close_fixture(fixture)
}
