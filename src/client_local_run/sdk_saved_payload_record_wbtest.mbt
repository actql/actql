///|
// Actual Common output/request/Sealed codec and complete observed commit.
// Device/inode and transition confirmations are typed fixture metadata, not
// physical File/Store/COMMIT or installed product evidence.
test "saved SDK Sealed record restores exact original request and committed binding" {
  let fixture = sdk_read_fixture(bound_scope=true, sealed_payload=true)
  defer (fixture.cleanup)()
  let source = sdk_saved_source(fixture).unwrap()
  let original = fixture.payload.unwrap()
  let wire = @payload.publication_payload_record_durable_json(original).unwrap()
  let (restored, binding) = restore_local_sdk_saved_payload_record(
    source,
    fixture.account,
    fixture.owner,
    fixture.view,
    "answer",
    @utf8.encode(wire),
  ).unwrap()
  assert_eq(
    @payload.publication_payload_record_durable_json(restored).unwrap(),
    wire,
  )
  assert_eq(
    @publication.publication_contract_json(binding),
    @publication.publication_contract_json(
      fixture.owner.view_binding(fixture.view, 0).unwrap(),
    ),
  )
  assert_true(
    validate_local_sdk_saved_payload_record(
      source,
      account(Deny),
      fixture.owner,
      fixture.view,
      "answer",
      restored,
    )
    is Err(InvalidOriginal),
  )
  assert_true(
    validate_local_sdk_saved_payload_record(
      source,
      fixture.account,
      fixture.owner,
      fixture.view,
      "foreign",
      restored,
    )
    is Err(_),
  )
}

///|
test "saved SDK record refuses foreign material request attempt state and bytes" {
  let fixture = sdk_read_fixture(bound_scope=true, sealed_payload=true)
  defer (fixture.cleanup)()
  let source = sdk_saved_source(fixture).unwrap()
  let wire = @payload.publication_payload_record_durable_json(
    fixture.payload.unwrap(),
  ).unwrap()
  for
    bad in [
      wire.replace(
        old="8cd664de3db2ebc3a68f6507c3d786addcdaffc9393fea9ce94364129ba27a98",
        new="0".repeat(64),
      ),
      wire.replace(old="sealed", new="writing"),
      "{}",
    ] {
    assert_true(
      restore_local_sdk_saved_payload_record(
        source,
        fixture.account,
        fixture.owner,
        fixture.view,
        "answer",
        @utf8.encode(bad),
      )
      is Err(_),
    )
  }
  let request = prepare_local_preflight_payload_request(
    fixture.preflight,
    0,
    fixture.result,
    fixture.account,
    "sha256:" + "4".repeat(64),
    "sha256:" + "e".repeat(64),
    9L,
  ).unwrap()
  let foreign = @payload.prepare_publication_payload_record(request)
  assert_true(
    validate_local_sdk_saved_payload_record(
      source,
      fixture.account,
      fixture.owner,
      fixture.view,
      "answer",
      foreign,
    )
    is Err(InvalidOriginal),
  )
  let other = sdk_read_fixture(bound_scope=true, sealed_payload=true)
  defer (other.cleanup)()
  assert_true(
    validate_local_sdk_saved_payload_record(
      source,
      fixture.account,
      other.owner,
      other.view,
      "answer",
      fixture.payload.unwrap(),
    )
    is Err(InvalidOriginal),
  )
}
