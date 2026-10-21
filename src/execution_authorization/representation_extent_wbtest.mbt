///|
fn extent_test_box(principal : Selector) -> SelectorBox {
  { principal, connection: All, resource: All, operation: All, }
}

///|
test "original Account retained extent distinguishes empty arrays and identity Strings" {
  let admitted = admit_account_configuration({
    account_id: "ac",
    entries: [],
    bootstrap: None,
  }).unwrap()
  let before = admitted.configuration_cid()
  assert_eq(admitted.representation_extent(), {
    configuration_records: 1L,
    bootstrap_records: 0L,
    entry_records: 0L,
    region_records: 0L,
    dimension_records: 0L,
    dynamic_array_records: 1L,
    dynamic_backing_slots: 0L,
    fixed_array_records: 0L,
    fixed_backing_slots: 0L,
    strings: 2L,
    text_utf16_units: 73L,
    original_byte_buffers: 0L,
    original_bytes: 0L,
  })
  assert_eq(admitted.configuration_cid(), before)
  assert_eq(admitted.representation_extent(), admitted.representation_extent())
}

///|
test "Account extent counts compiled scopes values and exact original backing" {
  let admitted = admit_account_configuration({
    account_id: "account",
    bootstrap: None,
    entries: [
      {
        entry_id: "read",
        outcome: Allow,
        scope: extent_test_box(AnyOf(["alice", "bob"])),
        exclusions: [],
      },
    ],
  }).unwrap()
  assert_eq(admitted.representation_extent(), {
    configuration_records: 1L,
    bootstrap_records: 0L,
    entry_records: 1L,
    region_records: 1L,
    dimension_records: 4L,
    dynamic_array_records: 6L,
    dynamic_backing_slots: 3L,
    fixed_array_records: 1L,
    fixed_backing_slots: 4L,
    strings: 5L,
    text_utf16_units: 90L,
    original_byte_buffers: 0L,
    original_bytes: 0L,
  })
  let tuple : AccessTuple = {
    principal: "alice",
    connection: "files",
    resource: "original",
    operation: "read",
  }
  assert_true(evaluate_account(admitted, tuple) is Allow(_))
}

///|
test "Account extent includes exclusion and bootstrap original holdings" {
  let admitted = admit_account_configuration({
    account_id: "account",
    bootstrap: Some({
      profile_id: "profile",
      profile_version: "v1",
      profile_cid: "sha256:" + "a".repeat(64),
    }),
    entries: [
      {
        entry_id: "read",
        outcome: Allow,
        scope: extent_test_box(All),
        exclusions: [extent_test_box(AnyOf(["bob"]))],
      },
    ],
  }).unwrap()
  assert_eq(admitted.representation_extent(), {
    configuration_records: 1L,
    bootstrap_records: 1L,
    entry_records: 1L,
    region_records: 2L,
    dimension_records: 8L,
    dynamic_array_records: 10L,
    dynamic_backing_slots: 3L,
    fixed_array_records: 2L,
    fixed_backing_slots: 8L,
    strings: 7L,
    text_utf16_units: 165L,
    original_byte_buffers: 0L,
    original_bytes: 0L,
  })
}

///|
test "Account extent preserves shared String occurrences and UTF16 units" {
  let name = "é😀"
  let admitted = admit_account_configuration({
    account_id: "account",
    bootstrap: None,
    entries: [
      {
        entry_id: "read",
        outcome: Allow,
        scope: {
          principal: AnyOf([name]),
          connection: All,
          resource: AnyOf([name]),
          operation: All,
        },
        exclusions: [],
      },
    ],
  }).unwrap()
  assert_eq(name.length(), 3)
  let extent = admitted.representation_extent()
  assert_eq(extent.strings, 5L)
  assert_eq(extent.text_utf16_units, 88L)
  assert_eq(extent.dynamic_backing_slots, 3L)
  assert_eq(extent.region_records, 1L)
}
