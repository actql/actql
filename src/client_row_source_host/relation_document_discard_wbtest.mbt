///|
fn relation_discard_fixture() -> (
  RowDeclaration,
  RelationDocument,
  RelationTargetDocument,
) {
  let declaration = relation_mapping_declaration()
  let raw = admit_relation_document(
    @utf8.encode(relation_document_test_text()),
    relation_document_test_limits(),
    10000000,
  ).unwrap()
  let target = project_relation_target_document(
    raw,
    declaration,
    "records",
    ["collection", "records"],
    None,
    "id",
    [],
  ).unwrap()
  (declaration, raw, target)
}

///|
test "row observation discard severs its own mark after parent invalidation" {
  let (declaration, raw, target) = relation_discard_fixture()
  let row = observe_relation_target(target, declaration, "first").unwrap()
  let copied = { ..row, }
  let before = relation_target_before(row).unwrap()
  let version = relation_target_version(row).unwrap()
  assert_false(discard_relation_target_row_original(copied))
  assert_eq(relation_target_version(row), Some(version))
  assert_true(discard_relation_document_original(raw))
  assert_true(relation_target_version(row) is None)
  assert_true(row.original is Some(_))
  assert_true(discard_relation_target_row_original(row))
  assert_true(row.original is None)
  assert_false(discard_relation_target_row_original(row))
  assert_false(discard_relation_target_row_original(copied))
  assert_false(before.is_empty())
  assert_true(version.has_prefix("sha256:"))
  assert_true(discard_relation_target_document_original(target))
}

///|
test "relation original discard severs only self marks and preserves retained immutable DATA" {
  let (declaration, raw, target) = relation_discard_fixture()
  let bytes = raw.bytes
  let root = raw.root
  let usage = relation_document_usage(raw).unwrap()
  let identity = relation_target_row_identity(target, 0).unwrap()
  assert_true(discard_relation_target_document_original(target))
  assert_true(target.original is None)
  assert_false(discard_relation_target_document_original(target))
  assert_true(relation_target_row_count(target) is None)
  assert_true(relation_target_row_identity(target, 0) is None)
  assert_true(
    observe_relation_target(target, declaration, identity) is Err(ForeignSource),
  )
  assert_eq(relation_document_usage(raw), Some(usage))
  assert_true(discard_relation_document_original(raw))
  assert_true(raw.original is None)
  assert_false(discard_relation_document_original(raw))
  assert_true(relation_document_usage(raw) is None)
  assert_eq(identity, "first")
  assert_eq(@utf8.decode(bytes), relation_document_test_text())
  assert_true(physical_equal(raw.bytes, bytes))
  assert_true(physical_equal(target.bytes, bytes))
  assert_true(physical_equal(raw.root, root))
  assert_eq(usage.projections, 1)
}

///|
test "copied relation carriers cannot discard or revive their original DATA" {
  let (_, raw, target) = relation_discard_fixture()
  let raw_copy = { ..raw, }
  let target_copy = { ..target, }
  assert_false(discard_relation_document_original(raw_copy))
  assert_false(discard_relation_target_document_original(target_copy))
  assert_true(relation_document_usage(raw) is Some(_))
  assert_eq(relation_target_row_count(target), Some(2))
  assert_true(physical_equal(raw_copy.original.unwrap(), raw))
  assert_true(physical_equal(target_copy.original.unwrap(), target))
  assert_true(discard_relation_target_document_original(target))
  assert_true(discard_relation_document_original(raw))
  assert_false(discard_relation_target_document_original(target_copy))
  assert_false(discard_relation_document_original(raw_copy))
  assert_true(relation_document_usage(raw_copy) is None)
  assert_true(relation_target_row_count(target_copy) is None)
  assert_true(raw.original is None)
  assert_true(target.original is None)
}

///|
test "relation child discard remains available after parent original invalidation" {
  let (declaration, raw, target) = relation_discard_fixture()
  let target_copy = { ..target, }
  assert_true(discard_relation_document_original(raw))
  assert_true(relation_document_usage(raw) is None)
  assert_true(relation_target_row_count(target) is None)
  assert_true(
    observe_relation_target(target, declaration, "first") is Err(ForeignSource),
  )
  // Getter validation still follows the parent. DATA discard only checks the
  // child's own original mark, so a prior parent discard cannot strand it.
  assert_false(discard_relation_target_document_original(target_copy))
  assert_true(target.original is Some(_))
  assert_true(discard_relation_target_document_original(target))
  assert_true(target.original is None)
  assert_false(discard_relation_target_document_original(target))
}

///|
test "discarding one relation projection leaves shared original and sibling unchanged" {
  let (declaration, raw, first) = relation_discard_fixture()
  let second = project_relation_target_document(
    raw,
    declaration,
    "records",
    ["collection", "records"],
    None,
    "id",
    [],
  ).unwrap()
  let usage = relation_document_usage(raw).unwrap()
  assert_true(discard_relation_target_document_original(first))
  assert_eq(relation_target_row_count(second), Some(2))
  assert_eq(relation_target_row_identity(second, 1), Some("second"))
  assert_eq(relation_document_usage(raw), Some(usage))
  assert_true(discard_relation_target_document_original(second))
  assert_eq(relation_document_usage(raw), Some(usage))
  assert_true(discard_relation_document_original(raw))
  assert_true(
    project_relation_target_document(
      raw,
      declaration,
      "records",
      ["collection", "records"],
      None,
      "id",
      [],
    )
    is Err(ForeignSource),
  )
}
