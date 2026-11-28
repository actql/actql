///|
test "Local CSV physical response packet keeps the exact original count and disposition" {
  let success = b"\x14\x00\x00\x00\x00\x00\x00\x00\x03\x00\x00\x00abc"
  assert_eq(mock_effect_descriptor_field(success, 0), 20)
  guard sdk_local_csv_delivery(success, 3) is Some(Complete(bytes)) else {
    fail("exact raw CSV packet")
  }
  assert_eq(bytes.to_owned(), b"abc")
  let extent = b"\x14\x00\x00\x00\x03\x00\x00\x00\x03\x00\x00\x00"
  assert_true(sdk_local_csv_delivery(extent, 3) is Some(Extent(3L)))
  assert_true(sdk_local_csv_delivery(extent, 2) is None)
  assert_true(sdk_local_csv_delivery(success, 2) is None)
  assert_true(
    sdk_local_csv_delivery(
      b"\x14\x00\x00\x00\x00\x00\x00\x00\x02\x00\x00\x00abc", 3,
    )
    is None,
  )
  assert_true(
    sdk_local_csv_delivery(
      b"\x14\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00", 3,
    )
    is Some(FailedKnown(2L)),
  )
  assert_true(
    sdk_local_csv_delivery(
      b"\x14\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00a", 3,
    )
    is None,
  )
  assert_true(
    sdk_local_csv_delivery(
      b"\x14\x00\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00", 3,
    )
    is Some(FailedUnknown),
  )
  assert_true(
    sdk_local_csv_delivery(
      b"\x14\x00\x00\x00\x02\x00\x00\x00\x01\x00\x00\x00", 3,
    )
    is None,
  )
  assert_true(sdk_local_csv_delivery(b"", 3) is None)
}
