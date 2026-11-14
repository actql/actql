///|
test "closed scalar parser overlap composes observed prefixes without raising the original one GiB quota" {
  let base = 15054224L
  let previous = 169656320L
  let next = 304385880L
  let imported = 672981712L
  let duplicate_text = 134663536L
  let other_owners = 100921666L
  let existing = base + previous + imported + other_owners
  assert_eq(existing, 958613922L)
  assert_eq(1073741824L - existing, 115127902L)
  assert_true(next - previous > 1073741824L - existing)
  let (imported_after, reusable_after, needed) = local_managed_import_working_overlap(
    imported, duplicate_text, previous, next,
  ).unwrap()
  assert_eq(imported_after, 538318176L)
  assert_eq(reusable_after, 0L)
  assert_eq(needed, 66024L)
  let complete = base + next + imported_after + other_owners
  assert_eq(complete, existing + needed)
  assert_true(complete >= existing && complete <= 1073741824L)
  // No second credit: later growth pays its complete new delta.
  assert_eq(
    local_managed_import_working_overlap(
      imported_after,
      reusable_after,
      next,
      next + 100L,
    ),
    Some((imported_after, 0L, 100L)),
  )
  // With no original closed scalar-import proof, the old full path remains.
  assert_eq(
    local_managed_import_working_overlap(imported, 0L, previous, next),
    Some((imported, 0L, next - previous)),
  )
}

///|
test "scalar overlap remains bounded across smaller grows and refuses invalid original prefixes" {
  assert_eq(
    local_managed_import_working_overlap(100L, 20L, 30L, 35L),
    Some((95L, 15L, 0L)),
  )
  assert_eq(
    local_managed_import_working_overlap(95L, 15L, 35L, 60L),
    Some((80L, 0L, 10L)),
  )
  assert_eq(
    local_managed_import_working_overlap(80L, 0L, 60L, 60L),
    Some((80L, 0L, 0L)),
  )
  for
    args in [
      (-1L, 0L, 0L, 1L),
      (10L, -1L, 0L, 1L),
      (10L, 11L, 0L, 1L),
      (10L, 1L, -1L, 1L),
      (10L, 1L, 2L, 1L),
    ] {
    assert_eq(
      local_managed_import_working_overlap(args.0, args.1, args.2, args.3),
      None,
    )
  }
  assert_eq(
    local_managed_import_working_overlap(
      9223372036854775807L, 1L, 0L, 9223372036854775807L,
    ),
    Some((9223372036854775806L, 0L, 9223372036854775806L)),
  )
}
