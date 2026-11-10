///|
// New same-file predecessor cases use the existing explicit Arena fixture.
// This proves physical lineage only, not Account/claim or ordinary acceptance.
#borrow(bytes)
extern "C" fn target_lineage_pwrite(
  descriptor : Int,
  bytes : Bytes,
  count : Int64,
  offset : Int64,
) -> Int64 = "pwrite"

///|
extern "C" fn target_lineage_sync(descriptor : Int) -> Int = "fsync"

///|
#borrow(source, target)
extern "C" fn target_lineage_rename(source : Bytes, target : Bytes) -> Int = "rename"

///|
fn target_io_fixture_lineage_work(directory : String, kind : Int) -> Unit raise {
  let suffix = match kind {
    4 => "chain"
    5 => "inplace"
    6 => "replaced"
    _ => fail("exact lineage fixture required")
  }
  let name = "target-" + suffix + ".json"
  let provider = target_io_fixture_provider(directory, name)
  let first = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "first",
    update=Some(
      (
        "sha256:a77b7acbf9bec014f38f734e7a6a4aad2907d4ca590d3a5e25cd108485f356b1",
        "{\"value\":9}", "target-first-stage",
      ),
    ),
  ).unwrap()
  target_io_fixture_run(first)
  let ack = first.replacement_acknowledgment().unwrap()
  let first_wire = target_io_fixture_text.replace_all(
    old="\"value\":1",
    new="\"value\":9",
  )
  assert_eq(ack.replacement(), @utf8.encode(first_wire))
  assert_true(first.close().unwrap())
  assert_true(first.replacement_acknowledgment() is None)
  // A separately prepared equal DATA selection is not this original provider.
  let equal_provider = target_io_fixture_provider(directory, name)
  assert_true(
    prepare_native_relation_file_target_io(
      equal_provider,
      ["value"],
      "second",
      update=Some(
        (
          "sha256:86f081f20834cf21e140b97be1aa98187fd8b32e283921cf5b8cf4ee2db75a12",
          "{\"value\":8}", "foreign-stage",
        ),
      ),
      predecessor=Some(ack),
    )
    is Err(ForeignOriginal),
  )
  if kind == 5 {
    // Stable in-place edit: device/inode/size remain exactly the ACK's values.
    // A generation-only check would wrongly permit this foreign full-file edit.
    let foreign = @utf8.encode(
      first_wire.replace_all(old="untouched", new="external!"),
    )
    let descriptor = capture_fixture_open(
      @utf8.encode(directory + "/" + name + "\u{0000}"),
      2,
    )
    assert_true(descriptor >= 0)
    assert_eq(
      target_lineage_pwrite(
        descriptor,
        foreign,
        foreign.length().to_int64(),
        0L,
      ),
      foreign.length().to_int64(),
    )
    assert_eq(target_lineage_sync(descriptor), 0)
    assert_eq(capture_fixture_close(descriptor), 0)
  }
  if kind == 6 {
    // Independently authored same bytes replace the file under a new inode.
    assert_eq(
      target_lineage_rename(
        @utf8.encode(directory + "/foreign-copy.json\u{0000}"),
        @utf8.encode(directory + "/" + name + "\u{0000}"),
      ),
      0,
    )
  }
  let second = prepare_native_relation_file_target_io(
    provider,
    ["value"],
    "second",
    update=Some(
      (
        "sha256:86f081f20834cf21e140b97be1aa98187fd8b32e283921cf5b8cf4ee2db75a12",
        "{\"value\":8}", "target-second-stage",
      ),
    ),
    predecessor=Some(ack),
  ).unwrap()
  assert_true(second.replacement_acknowledgment() is None)
  if kind == 4 {
    target_io_fixture_run(second)
    let final_ack = second.replacement_acknowledgment().unwrap()
    assert_eq(final_ack.identity(), "second")
    assert_eq(
      final_ack.expected_version(),
      "sha256:86f081f20834cf21e140b97be1aa98187fd8b32e283921cf5b8cf4ee2db75a12",
    )
    assert_eq(
      final_ack.replacement(),
      @utf8.encode(first_wire.replace_all(old="\"value\":2", new="\"value\":8")),
    )
    assert_eq(
      second.byte_counts(),
      (first_wire.length().to_int64(), first_wire.length().to_int64()),
    )
    assert_true(second.replacement_attempted)
  } else {
    let mut rejected = false
    for _ in 0..<100 {
      match second.advance() {
        Err(ForeignOriginal) => {
          rejected = true
          break
        }
        Err(_) => fail("unexpected lineage refusal")
        Ok(true) => fail("foreign file reached second write")
        Ok(false) => ()
      }
    }
    assert_true(rejected)
    assert_false(second.replacement_attempted)
    assert_true(second.writer is None)
    assert_true(second.replacement_acknowledgment() is None)
    if kind == 5 {
      let observed = second.observation.unwrap().generation().unwrap()
      assert_eq(observed, ack.generation())
      assert_eq(second.byte_counts(), (first_wire.length().to_int64(), 0L))
    } else {
      assert_eq(second.byte_counts(), (0L, 0L))
      assert_true(second.reader is None)
      assert_true(
        second.observation.unwrap().generation().unwrap() != ack.generation(),
      )
    }
    // Refusal remains sticky; observing it again cannot advance or create IO.
    assert_true(second.advance() is Err(ForeignOriginal))
  }
  assert_true(second.close().unwrap())
  assert_true(second.predecessor is None)
  assert_true(second.replacement_acknowledgment() is None)
}

///|
test "Native same-file second row consumes original generation and full-byte predecessor" {
  target_io_fixture_physical(4)
}

///|
test "Native same-generation foreign edit refuses second row before write" {
  target_io_fixture_physical(5)
}

///|
test "Native same-bytes foreign replacement refuses second row before read" {
  target_io_fixture_physical(6)
}
