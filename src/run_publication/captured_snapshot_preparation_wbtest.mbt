///|
fn snapshot_contract(
  name : String,
  identity : String,
  wire : String,
) -> PublicationContract {
  {
    name,
    identity,
    identity_field: "fixture_identity",
    wire_usage: None,
    wire,
    value: parse_contract_wire(wire, 10000, 1000, 16).unwrap(),
  }
}

///|
fn snapshot_admission_fixture(
  wire : String,
  fields : Array[String],
  count : Int,
  workspace? : Int = 100,
) -> CapturedResultSnapshotPreparation {
  let definition = snapshot_contract(
    "result_definition", "definition", "{\"result_name\":\"answer\"}",
  )
  // Independent logical preimage; no product snapshot or writer supplies it.
  let digest = @sha.text_hex("{\"sort\":\"relation\",\"value\":" + wire + "}").unwrap()
  let artifact = snapshot_contract(
    "result_artifact",
    "artifact",
    "{\"actual_row_count\":" +
    count.to_string() +
    ",\"logical_result_cid\":\"sha256:" +
    digest +
    "\",\"result_definition_cid\":\"definition\"}",
  )
  start_captured_result_snapshot(
    definition, artifact, wire, fields, 10000, 1000, 16, workspace,
  ).unwrap()
}

///|
fn snapshot_admission_finish(
  preparation : CapturedResultSnapshotPreparation,
  quantum : Int,
) -> Result[CapturedResultSnapshot, CapturedRunIssuanceIssue] raise {
  for _ in 0..<10000 {
    match preparation.advance(quantum) {
      Err(issue) => return Err(issue)
      Ok((done, work)) => {
        assert_true(work <= quantum)
        if done {
          return preparation.finish()
        }
        assert_true(work > 0)
      }
    }
  }
  fail("snapshot admission did not terminate")
}

///|
test "snapshot admission preserves canonical Text and exact authored field order" {
  let text = String::make(129, 'é') + "e\u0301\r\n😀"
  let wire = "[{\"n\":7,\"s\":\"" +
    String::make(129, 'é') +
    "e\u0301\\r\\n😀\"}]"
  for quantum in [1, 7, 64] {
    let preparation = snapshot_admission_fixture(wire, ["s", "n"], 1)
    assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
    let snapshot = snapshot_admission_finish(preparation, quantum).unwrap()
    assert_eq(snapshot.fields, ["s", "n"])
    assert_eq(@json.stringify_value(snapshot.rows, 10000, 1000, 16), wire)
    guard snapshot.rows is @json.Array(rows) else { fail("rows") }
    guard @json.object_field(@json.array_at(rows, 0).unwrap(), "s")
      is Some(@json.String(actual)) else {
      fail("text")
    }
    assert_eq(actual, text)
    assert_eq(preparation.live, 0)
    preparation.cancel()
    assert_eq(snapshot.fields, ["s", "n"])
    assert_true(preparation.finish() is Err(CaptureIssuanceEncoding))
  }
}

///|
test "snapshot admission rejects row, field, canonical and identity substitutions" {
  for
    (wire, fields, count, expected) in [
      ("[{\"n\":7}]", ["n", "n"], 1, CaptureIssuanceInvalidFields("answer")),
      ("[{\"n\":7}]", ["s"], 1, CaptureIssuanceInvalidFields("answer")),
      (
        "[{\"n\":7}]",
        ["n"],
        2,
        CaptureIssuanceReferenceMismatch("actual_row_count"),
      ),
      ("[ {\"n\":7}]", ["n"], 1, CaptureIssuanceInvalidRows("answer")),
      ("[7]", [], 1, CaptureIssuanceInvalidFields("answer")),
    ] {
    let preparation = snapshot_admission_fixture(wire, fields, count)
    assert_true(
      snapshot_admission_finish(preparation, 1) is Err(issue) &&
      issue == expected,
    )
    assert_eq(preparation.live, 0)
    assert_true(preparation.rows is None && preparation.wire is None)
    assert_true(preparation.fields.is_empty() && preparation.keys.is_empty())
  }
}

///|
test "snapshot admission reserves empty-row field inventory and cancels every phase" {
  // Eight owner slots, two fields with three references each, four sort slots.
  let exact = snapshot_admission_fixture("[]", ["s", "n"], 0, workspace=18)
  assert_eq(snapshot_admission_finish(exact, 1).unwrap().fields, ["s", "n"])
  assert_eq(exact.peak, 18)
  let short = snapshot_admission_fixture("[]", ["s", "n"], 0, workspace=17)
  assert_true(
    snapshot_admission_finish(short, 1) is Err(CaptureIssuanceEncoding),
  )
  assert_eq(short.peak, 14)
  assert_eq(short.live, 0)
  for cut in 0..<100 {
    let preparation = snapshot_admission_fixture("[{\"n\":7}]", ["n"], 1)
    for _ in 0..<cut {
      let (done, _) = preparation.advance(1).unwrap()
      if done {
        break
      }
    }
    preparation.cancel()
    preparation.cancel()
    assert_eq(preparation.live, 0)
    assert_true(preparation.rows is None && preparation.wire is None)
    assert_true(preparation.fields.is_empty() && preparation.keys.is_empty())
    assert_true(preparation.advance(1) is Err(CaptureIssuanceEncoding))
  }
}
