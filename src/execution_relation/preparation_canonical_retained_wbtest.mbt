///|
test "canonical retained fold preserves the existing domain geometry and backing slots" {
  let tree : @identity.CanonicalRepresentationExtent = {
    nodes: 5L,
    strings: 2L,
    text_utf16_units: 11L,
    arrays: 1L,
    objects: 1L,
    array_backing_slots: 4L,
    object_backing_slots: 3L,
    max_frame_slots: 9L,
  }
  // H18/R25/W18/T18 from the independent inventory, priced once by the
  // existing 16/8/8/2 tariff. Traversal frames are not retained tree backing.
  assert_eq(
    canonical_preparation_retained_bytes(tree, 2L, 3L, 4L, 7L),
    Some(668L),
  )
  assert_eq(
    canonical_preparation_retained_bytes(
      { ..tree, max_frame_slots: 1000L, },
      2L,
      3L,
      4L,
      7L,
    ),
    Some(668L),
  )
  // Spare canonical slots remain charged; the helper never deduplicates
  // independent occurrences or turns retained UTF16 into wire bytes.
  assert_eq(
    canonical_preparation_retained_bytes(
      { ..tree, array_backing_slots: 5L, },
      2L,
      3L,
      4L,
      7L,
    ),
    Some(676L),
  )
}

///|
test "canonical retained fold refuses negative counts and checked dimension or tariff overflow" {
  let zero : @identity.CanonicalRepresentationExtent = {
    nodes: 0L,
    strings: 0L,
    text_utf16_units: 0L,
    arrays: 0L,
    objects: 0L,
    array_backing_slots: 0L,
    object_backing_slots: 0L,
    max_frame_slots: 0L,
  }
  assert_eq(
    canonical_preparation_retained_bytes(zero, 0L, 0L, 0L, 0L),
    Some(0L),
  )
  for
    tree in [
      { ..zero, nodes: -1L, },
      { ..zero, strings: -1L, },
      { ..zero, text_utf16_units: -1L, },
      { ..zero, arrays: -1L, },
      { ..zero, objects: -1L, },
      { ..zero, array_backing_slots: -1L, },
      { ..zero, object_backing_slots: -1L, },
      { ..zero, max_frame_slots: -1L, },
      { ..zero, arrays: 9223372036854775807L, objects: 1L, },
      { ..zero, nodes: 9223372036854775807L, },
    ] {
    assert_true(
      canonical_preparation_retained_bytes(tree, 0L, 0L, 0L, 0L) is None,
    )
  }
  for
    (h, r, w, t) in [
      (-1L, 0L, 0L, 0L),
      (0L, -1L, 0L, 0L),
      (0L, 0L, -1L, 0L),
      (0L, 0L, 0L, -1L),
    ] {
    assert_true(canonical_preparation_retained_bytes(zero, h, r, w, t) is None)
  }
  // A nonnegative count can fit Int64 while its selected tariff cannot.
  assert_true(
    canonical_preparation_retained_bytes(zero, 9223372036854775807L, 0L, 0L, 0L)
    is None,
  )
}
