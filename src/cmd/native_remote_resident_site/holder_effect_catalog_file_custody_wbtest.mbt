///|
/// Read/cleanup callback models only. These do not manufacture a producer,
/// preparation grant, physical close ACK or successful Provider execution.
test "Catalog file callback returns text after both current fences" {
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let reads = Ref(0)
  let fences = Ref(0)
  assert_eq(
    holder_catalog_file_read(
      failure,
      () => {
        fences.val += 1
        true
      },
      () => {
        reads.val += 1
        Ok("original file text")
      },
    ),
    Some("original file text"),
  )
  assert_eq(reads.val, 1)
  assert_eq(fences.val, 2)
  assert_true(failure.val is None)
}

///|
test "Catalog file callback current refusal performs no read" {
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let reads = Ref(0)
  assert_true(
    holder_catalog_file_read(failure, () => false, () => {
      reads.val += 1
      Ok("unread")
    })
    is None,
  )
  assert_eq(reads.val, 0)
}

///|
test "Catalog read failure retains the same opaque object and refuses another read" {
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  guard @bounded_files.read_bounded_text_file_with_custody(
      "unopened", "unread", 0L,
    )
    is Err(original) else {
    fail("invalid limit admitted")
  }
  let reads = Ref(0)
  assert_true(
    holder_catalog_file_read(failure, () => true, () => {
      reads.val += 1
      Err(original)
    })
    is None,
  )
  assert_true(physical_equal(failure.val.unwrap(), original))
  assert_true(
    holder_catalog_file_read(failure, () => true, () => {
      reads.val += 1
      Ok("must not be read")
    })
    is None,
  )
  assert_eq(reads.val, 1)
  assert_true(original.issue() is @bounded_files.InvalidLimit)
}

///|
test "Catalog file callback changed final fence does not publish text" {
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let checks = Ref(0)
  assert_true(
    holder_catalog_file_read(
      failure,
      () => {
        checks.val += 1
        checks.val == 1
      },
      () => Ok("withheld"),
    )
    is None,
  )
  assert_eq(checks.val, 2)
}

///|
test "Catalog cleanup lost reply retains original responsibility until same Owner ACK" {
  guard @bounded_files.read_bounded_text_file_with_custody(
      "unopened", "unread", 0L,
    )
    is Err(original) else {
    fail("invalid limit admitted")
  }
  let failure = Ref(Some(original))
  let closes = Ref(0)
  let same_owner = Ref(true)
  assert_false(
    retry_holder_catalog_file_failure(failure, retained => {
      same_owner.val = same_owner.val && physical_equal(retained, original)
      closes.val += 1
      Err(@filesystem.Cleanup("fixture reply unconfirmed"))
    }),
  )
  assert_true(physical_equal(failure.val.unwrap(), original))
  assert_true(
    retry_holder_catalog_file_failure(failure, retained => {
      same_owner.val = same_owner.val && physical_equal(retained, original)
      closes.val += 1
      retained.retry_cleanup()
    }),
  )
  assert_true(failure.val is None)
  assert_true(
    retry_holder_catalog_file_failure(failure, _ => {
      closes.val += 1
      Err(@filesystem.Cleanup("duplicate close"))
    }),
  )
  assert_eq(closes.val, 2)
  assert_true(same_owner.val)
  assert_true(original.issue() is @bounded_files.InvalidLimit)
}

///|
test "Catalog diagnostic selection rejects before current and physical read" {
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let reads = Ref(0)
  let checks = Ref(0)
  for ceiling in [-1, 0] {
    assert_true(holder_catalog_file_read_with_ceiling(
      failure,
      () => { checks.val += 1; true },
      ceiling,
      _ => { reads.val += 1; Ok("unread") },
    ) is None)
  }
  assert_eq(reads.val, 0)
  assert_eq(checks.val, 0)
  assert_true(failure.val is None)
}

///|
test "Catalog physical callback receives exact independent diagnostic ceiling" {
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let selected = Ref(0)
  let checks = Ref(0)
  assert_eq(holder_catalog_file_read_with_ceiling(
    failure,
    () => { checks.val += 1; true },
    7,
    ceiling => { selected.val = ceiling; Ok("original bounded text") },
  ), Some("original bounded text"))
  assert_eq(selected.val, 7)
  assert_eq(checks.val, 2)
}

///|
test "Catalog bounded diagnostic refusal retains original failure without a second read" {
  guard @bounded_files.read_bounded_text_file_with_custody(
    "unopened", "unread", 0L, diagnostic_ceiling=Some(7),
  ) is Err(original) else { fail("invalid limit admitted") }
  let failure : Ref[@bounded_files.NativeBoundedTextFailure?] = Ref(None)
  let reads = Ref(0)
  let selected = Ref(0)
  assert_true(holder_catalog_file_read_with_ceiling(
    failure,
    () => true,
    7,
    ceiling => { selected.val = ceiling; reads.val += 1; Err(original) },
  ) is None)
  assert_true(physical_equal(failure.val.unwrap(), original))
  let checks = Ref(0)
  assert_true(holder_catalog_file_read_with_ceiling(
    failure,
    () => { checks.val += 1; true },
    7,
    _ => { reads.val += 1; Ok("must not be read") },
  ) is None)
  assert_eq(reads.val, 1)
  assert_eq(selected.val, 7)
  assert_eq(checks.val, 0)
  assert_true(original.issue() is @bounded_files.InvalidLimit)
}
