///|
test "SDK payload routes original selected artifact and durable binding without byte permission" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [fixture.result],
      "answer",
      8,
    )
    is Ok((0, 0)),
  )
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [],
      "answer",
      8,
    )
    is Err(MissingOriginal),
  )
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [fixture.result],
      "missing",
      8,
    )
    is Err(Stored(_)),
  )
}

///|
test "SDK payload routing retains inventory bound and accepts identical original aliases" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [fixture.result],
      "answer",
      0,
    )
    is Err(InvalidLimit),
  )
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [fixture.result, fixture.result],
      "answer",
      1,
    )
    is Err(InvalidLimit),
  )
  // Identical immutable references do not create an invented uniqueness rule.
  // Final Sealed-record binding/current checks remain required by the caller.
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [fixture.result, fixture.result],
      "answer",
      8,
    )
    is Ok((0, 0)),
  )
}

///|
test "SDK payload routing refuses foreign view and cancelled original owner" {
  let fixture = sdk_read_fixture()
  defer (fixture.cleanup)()
  let foreign = sdk_read_fixture()
  defer (foreign.cleanup)()
  let encoding = sdk_payload_encoding_fixture(fixture)
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      foreign.view,
      [fixture.result],
      "answer",
      8,
    )
    is Err(Stored(_)),
  )
  fixture.owner.cancel()
  assert_true(
    encoding.original_payload_ordinals(
      fixture.owner,
      fixture.view,
      [fixture.result],
      "answer",
      8,
    )
    is Err(Stored(_)),
  )
}
