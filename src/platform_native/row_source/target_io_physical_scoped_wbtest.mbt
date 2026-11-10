///|
// This is an explicit physical-component fixture, not Account, Effect claim,
// operation-ledger, ordinary CLI or complete constructor-envelope acceptance.
let target_io_fixture_text = " {\"items\":[{\"id\":\"first\",\"value\":1},{\"id\":\"second\",\"value\":2}],\"keep\":\"untouched\"}\n"

///|
fn target_io_fixture_provider(
  directory : String,
  name : String,
) -> NativeRelationFilePreparedProvider {
  prepare_native_relation_file_provider(
    capture_fixture_declaration(),
    {
      directory,
      name,
      resource: "records",
      items_path: ["items"],
      key_path: None,
      primary_identity: "id",
    },
    {
      page: { max_bytes: 4096, max_nodes: 128, max_depth: 8, max_rows: 2, },
      max_work: 1000000,
      chunk_bytes: 32,
      diagnostic_ceiling: 256,
    },
  ).unwrap()
}

///|
fn target_io_fixture_run(child : NativeRelationFileTargetIO) -> Unit raise {
  let mut complete = false
  for _ in 0..<100 {
    if child.advance().unwrap() {
      complete = true
      break
    }
  }
  assert_true(complete)
}

///|
fn target_io_fixture_update_work(directory : String) -> Unit raise {
  let provider = target_io_fixture_provider(directory, "target-update.json")
  let read = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
  ).unwrap()
  assert_eq(read.snapshot(), None)
  assert_true(read.replacement_acknowledgment() is None)
  assert_eq(read.byte_counts(), (0L, 0L))
  target_io_fixture_run(read)
  let (before, version) = read.snapshot().unwrap()
  assert_eq(before, "{\"id\":\"first\",\"value\":1}")
  // Independent literal canonical-row digest, not a product-generated oracle.
  assert_eq(
    version, "sha256:a77b7acbf9bec014f38f734e7a6a4aad2907d4ca590d3a5e25cd108485f356b1",
  )
  assert_eq(
    read.byte_counts(),
    (target_io_fixture_text.length().to_int64(), 0L),
  )
  // Preview preparation validates against the SAME complete observed target,
  // without acquiring a Writer or changing either original observation.
  read.check_update("{\"value\":9}").unwrap()
  assert_true(read.check_update("{\"value\":\"bad\"}") is Err(Document(_)))
  assert_eq(read.snapshot(), Some((before, version)))
  assert_false(read.replacement_attempted)
  assert_eq(read.byte_counts().1, 0L)
  assert_true(read.close().unwrap())
  assert_true(read.check_update("{\"value\":9}") is Err(Unavailable))
  assert_true(read.close().unwrap())
  assert_eq(read.snapshot(), None)

  let update = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
    update=Some((version, "{\"value\":9}", "target-update-stage")),
  ).unwrap()
  target_io_fixture_run(update)
  assert_eq(update.snapshot(), Some((before, version)))
  assert_eq(
    update.byte_counts(),
    (
      target_io_fixture_text.length().to_int64(),
      target_io_fixture_text.length().to_int64(),
    ),
  )
  assert_true(update.replacement_attempted)
  let ack = update.replacement_acknowledgment().unwrap()
  assert_eq(ack.identity(), "first")
  assert_eq(ack.expected_version(), version)
  assert_eq(ack.changes_wire(), "{\"value\":9}")
  assert_eq(ack.selection().name, "target-update.json")
  let expected = target_io_fixture_text.replace_all(
    old="\"value\":1",
    new="\"value\":9",
  )
  assert_eq(ack.replacement(), @utf8.encode(expected))
  assert_eq(ack.generation().size, expected.length().to_int64())
  assert_true(
    update.root
    .unwrap()
    .verify_file_generation("target-update.json", ack.generation()),
  )
  assert_true(update.close().unwrap())
  assert_true(update.replacement_acknowledgment() is None)
  // This retained immutable observation is historical evidence, not another
  // physical child, current target proof or permission to repeat replacement.
  assert_eq(ack.replacement(), @utf8.encode(expected))
  let fresh = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
  ).unwrap()
  target_io_fixture_run(fresh)
  let (after, after_version) = fresh.snapshot().unwrap()
  assert_eq(after, "{\"id\":\"first\",\"value\":9}")
  assert_true(after_version != version)
  assert_true(fresh.close().unwrap())

  let stale = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
    update=Some((version, "{\"value\":7}", "target-stale-stage")),
  ).unwrap()
  let mut refused = false
  for _ in 0..<100 {
    match stale.advance() {
      Ok(false) => ()
      Err(Document(@rows.ForeignSource)) => {
        refused = true
        break
      }
      _ => fail("stale original target version did not refuse before write")
    }
  }
  assert_true(refused)
  assert_false(stale.replacement_attempted)
  assert_eq(
    stale.byte_counts(),
    (target_io_fixture_text.length().to_int64(), 0L),
  )
  assert_true(stale.advance() is Err(Document(@rows.ForeignSource)))
  assert_eq(stale.snapshot(), None)
  assert_true(stale.replacement_acknowledgment() is None)
  assert_true(stale.close().unwrap())
}

///|
fn target_io_fixture_cancel_work(directory : String) -> Unit raise {
  let provider = target_io_fixture_provider(directory, "target-cancel.json")
  let child = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
  ).unwrap()
  assert_false(child.advance().unwrap())
  assert_false(child.advance().unwrap())
  assert_eq(child.byte_counts(), (32L, 0L))
  assert_eq(child.snapshot(), None)
  assert_true(child.reader is Some(_))
  assert_true(child.close().unwrap())
  assert_true(child.reader is None && child.root is None)
  assert_true(child.close().unwrap())
  assert_true(child.advance() is Err(Unavailable))
  assert_eq(child.byte_counts(), (32L, 0L))
}

///|
fn target_io_fixture_physical(kind : Int) -> Unit raise {
  let directory = @env.get_env_var("ACTQL_TEST_NATIVE_TARGET_IO_ROOT").unwrap()
  let suffix = match kind {
    0 => "update"
    1 => "cancel"
    2 => "sync"
    4 => "chain"
    5 => "inplace"
    6 => "replaced"
    _ => "funding"
  }
  let path = @utf8.encode(directory + "/target-backing-" + suffix + "\u{0000}")
  let descriptor = capture_fixture_open(path, 2)
  assert_true(descriptor >= 0)
  let parent_bytes = 384L * 1024L * 1024L
  let arena = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    parent_bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: parent_bytes,
    },
    65536L,
  ).unwrap()
  arena.acquire_fd(descriptor).unwrap()
  let backing = arena.borrow_backing().unwrap()
  arena.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    arena
    .prepare_domain(backing, descriptor, 256L * 1024L * 1024L, {
      planning_work: 8,
      attempts: 4,
      holdings: 2,
      transfer_bytes: 16384L,
      retained_bytes: 16L * 1024L * 1024L,
      execution_bytes: 64L * 1024L * 1024L,
    })
    .unwrap() {
    @arena.PreparedDomain(value) => value
    _ =>
      fail("selected Native target fixture did not prepare its original domain")
  }
  arena.transfer_domain(domain).unwrap()
  arena.leave_backing_borrow_scope(backing).unwrap()
  arena.return_backing_borrow(backing).unwrap()
  arena.prepare_domain_read(domain).unwrap()
  let execution = match
    arena.prepare_domain_retained_execution(domain).unwrap() {
    @arena.ReadyRetainedExecution(value) => value
    _ => fail("selected Native target fixture retained execution is partial")
  }
  arena.enter_domain_retained_execution(execution).unwrap()
  match kind {
    0 => target_io_fixture_update_work(directory)
    1 => target_io_fixture_cancel_work(directory)
    2 => target_io_fixture_sync_work(directory)
    4 | 5 | 6 => target_io_fixture_lineage_work(directory, kind)
    _ => target_io_fixture_funding_work(directory)
  }
  arena.leave_domain_retained_execution(execution).unwrap()
  arena.close_domain_retained_execution(execution).unwrap()
  arena.close_domain_after_owner_ack(domain).unwrap()
  arena.try_close().unwrap()
  assert_eq(capture_fixture_close(descriptor), 0)
}

///|
test "Native target I/O reads original before and updates only the checked row once" {
  target_io_fixture_physical(0)
}

///|
test "Native target I/O retires its same partial Reader without refunding bytes" {
  target_io_fixture_physical(1)
}

///|
#borrow(root)
extern "C" fn target_io_fail_root_sync(
  root : @files.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
fn target_io_fixture_sync_work(directory : String) -> Unit raise {
  let provider = target_io_fixture_provider(directory, "target-sync.json")
  let read = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
  ).unwrap()
  target_io_fixture_run(read)
  let (_, version) = read.snapshot().unwrap()
  assert_true(read.close().unwrap())
  let child = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
    update=Some((version, "{\"value\":9}", "target-sync-stage")),
  ).unwrap()
  let mut prepared = false
  for _ in 0..<100 {
    assert_false(child.advance().unwrap())
    if child.phase is TargetWriting {
      prepared = true
      break
    }
  }
  assert_true(prepared)
  target_io_fail_root_sync(child.root.unwrap(), 1)
  assert_true(child.advance() is Err(Filesystem(@files.Write(_))))
  assert_true(child.replacement_attempted)
  assert_true(child.replacement_acknowledgment() is None)
  assert_eq(child.snapshot(), None)
  let observed = child.byte_counts()
  assert_eq(
    observed,
    (
      target_io_fixture_text.length().to_int64(),
      target_io_fixture_text.length().to_int64(),
    ),
  )
  // A failed durable replacement has no normal result or retry entrance.
  assert_true(child.advance() is Err(Filesystem(@files.Write(_))))
  assert_eq(child.byte_counts(), observed)
  assert_true(child.close().unwrap())
  // Physical cleanup preserves the already replaced business file. This
  // independent read is not a business success or a claim/Journal ACK.
  let fresh = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
  ).unwrap()
  target_io_fixture_run(fresh)
  assert_eq(fresh.snapshot().unwrap().0, "{\"id\":\"first\",\"value\":9}")
  assert_true(fresh.close().unwrap())
}

///|
test "Native target I/O preserves a replaced file after ambiguous directory sync" {
  target_io_fixture_physical(2)
}

///|
// Explicit quota callbacks, not a normal operation/Account supplier. Actual
// original FS observations/readers prove the callback precedes body allocation.
fn target_io_fixture_funding_work(directory : String) -> Unit raise {
  let provider = target_io_fixture_provider(directory, "target-funding.json")
  let calls = Ref(0)
  let measured = Ref(-1)
  let before_body = Ref(false)
  let holder : Ref[NativeRelationFileTargetIO?] = Ref(None)
  let child = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
    before_response=Some(bytes => {
      calls.val += 1
      measured.val = bytes
      let original = holder.val.unwrap()
      before_body.val = original.observation is Some(_) &&
        original.reader is None &&
        original.buffer is None &&
        original.advance() is Err(Unavailable) &&
        original.close() is Err(Unavailable)
      true
    }),
  ).unwrap()
  holder.val = Some(child)
  target_io_fixture_run(child)
  assert_eq(calls.val, 1)
  assert_eq(measured.val, target_io_fixture_text.length())
  assert_true(before_body.val)
  assert_eq(
    child.byte_counts(),
    (target_io_fixture_text.length().to_int64(), 0L),
  )
  assert_eq(child.snapshot().unwrap().0, "{\"id\":\"first\",\"value\":1}")
  assert_false(child.replacement_attempted)
  assert_true(child.close().unwrap())
  holder.val = None
  let refusals = Ref(0)
  let refused = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
    before_response=Some(_ => {
      refusals.val += 1
      false
    }),
  ).unwrap()
  assert_true(refused.advance() is Err(Capacity))
  assert_true(refused.reader is None && refused.buffer is None)
  assert_true(refused.root is Some(_) && refused.observation is Some(_))
  assert_eq(refused.byte_counts(), (0L, 0L))
  assert_true(refused.advance() is Err(Capacity))
  assert_eq(refusals.val, 1)
  assert_true(refused.close().unwrap())
  assert_true(refused.root is None && refused.observation is None)
  assert_true(
    prepare_native_relation_file_target_io(
      provider,
      ["value"],
      "first",
      update=Some(("version", "{}", "stage")),
      before_response=Some(_ => true),
    )
    is Err(InvalidInput),
  )
  // A distinct named update entrance stages its SAME response outside locks.
  // Decline happens before Reader/body/write and keeps the partial Root for
  // the original close; the general update+callback refusal above stays exact.
  let update_holder : Ref[NativeRelationFileTargetIO?] = Ref(None)
  let update_calls = Ref(0)
  let update_before_body = Ref(false)
  let update = prepare_native_relation_file_target_update_io(
    provider,
    ["value"],
    "first",
    (
      "sha256:a77b7acbf9bec014f38f734e7a6a4aad2907d4ca590d3a5e25cd108485f356b1",
      "{\"value\":9}", "target-staged-update",
    ),
    bytes => {
      let current = update_holder.val.unwrap()
      update_calls.val += 1
      update_before_body.val = bytes == target_io_fixture_text.length() &&
        current.lock is None &&
        current.reader is None &&
        current.buffer is None &&
        current.advance() is Err(Unavailable) &&
        current.close() is Err(Unavailable)
      true
    },
  ).unwrap()
  update_holder.val = Some(update)
  target_io_fixture_run(update)
  assert_eq(update_calls.val, 1)
  assert_true(update_before_body.val)
  assert_true(update.replacement_attempted)
  assert_eq(
    update.replacement_acknowledgment().unwrap().replacement(),
    @utf8.encode(
      target_io_fixture_text.replace_all(old="\"value\":1", new="\"value\":9"),
    ),
  )
  assert_true(update.close().unwrap())
  update_holder.val = None
  let declined = prepare_native_relation_file_target_update_io(
    provider,
    ["value"],
    "first",
    ("version", "{}", "declined-update"),
    _ => false,
  ).unwrap()
  assert_true(declined.advance() is Err(Capacity))
  assert_true(
    declined.lock is None && declined.reader is None && declined.buffer is None,
  )
  assert_false(declined.replacement_attempted)
  assert_eq(declined.byte_counts(), (0L, 0L))
  assert_true(declined.close().unwrap())
  let external = @utf8.encode(
    target_io_fixture_text.replace_all(old="\"value\":1", new="\"value\":7"),
  )
  let descriptor = capture_fixture_open(
    @utf8.encode(directory + "/target-funding.json\u{0000}"),
    2,
  )
  assert_true(descriptor >= 0)
  let mutated = Ref(false)
  let stale_after_callback = prepare_native_relation_file_target_update_io(
    provider,
    ["value"],
    "first",
    (
      "sha256:286d43ac0985c9c0fcba88ffdf628b47d1cd3ded536717747180f7364501d408",
      "{\"value\":8}", "stale-after-callback",
    ),
    _ => {
      mutated.val = target_lineage_pwrite(
          descriptor,
          external,
          external.length().to_int64(),
          0L,
        ) ==
        external.length().to_int64() &&
        target_lineage_sync(descriptor) == 0
      true
    },
  ).unwrap()
  let mut refused_after_callback = false
  for _ in 0..<100 {
    match stale_after_callback.advance() {
      Ok(false) => ()
      Err(Document(@rows.ForeignSource)) => {
        refused_after_callback = true
        break
      }
      _ => fail("post-callback original version must refuse before replacement")
    }
  }
  assert_true(mutated.val && refused_after_callback)
  assert_false(stale_after_callback.replacement_attempted)
  assert_true(stale_after_callback.close().unwrap())
  assert_eq(capture_fixture_close(descriptor), 0)
  for bytes in [-1, provider.limits.page.max_bytes + 1] {
    assert_true(
      native_relation_file_target_read_io_capacity(
        provider,
        1,
        response_bytes=Some(bytes),
      )
      is None,
    )
  }
  let initial = native_relation_file_target_read_io_capacity(
    provider,
    1,
    response_bytes=Some(0),
  ).unwrap()
  let actual = native_relation_file_target_read_io_capacity(
    provider,
    1,
    response_bytes=Some(target_io_fixture_text.length()),
  ).unwrap()
  let maximum = native_relation_file_target_read_io_capacity(provider, 1).unwrap()
  assert_true(
    @execution.execution_capacity_retained_bytes(initial) <=
    @execution.execution_capacity_retained_bytes(actual),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(actual) <=
    @execution.execution_capacity_retained_bytes(maximum),
  )
}

///|
test "Native target response funding uses the original size before Reader and buffer" {
  target_io_fixture_physical(3)
}
