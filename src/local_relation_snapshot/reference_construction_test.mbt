///|
test "Member reference quantity uses actual field text and does not admit its syntax" {
  for
    (reference, units) in [
      ("source:local/s/rows", 19),
      ("source:local/東京/rows", 20),
      ("source:local/s/~9", 17),
    ] {
    let body = base().replace(old="source:local/s/rows", new=reference)
    let environment = wire_environment("[" + body + "]", "[]")
    let original = @environment.member_at(environment, SchemaSnapshots, 0).unwrap()
    let bound = member_reference_construction_inspection_bound(original)
    let (recipe, work) = observe_member_reference_read_construction(original)
    // Original body has four top-level fields; source_ref is third.
    assert_eq(bound, 12L)
    assert_eq(work, 9L)
    assert_true(work <= bound)
    let recipe = recipe.unwrap()
    assert_eq(recipe.retained_utf16_units, 2L * units.to_int64())
    if reference == "source:local/s/~9" {
      assert_true(
        read_member(original, caps()) is Err(InvalidSnapshot(InvalidSnapshot)),
      )
    }
  }
}

///|
test "Member reference inspection keeps unavailable role separate from zero demand" {
  let environment = wire_environment("[]", "[" + base() + "]")
  let original = @environment.member_at(environment, MappingContracts, 0).unwrap()
  let (recipe, work) = observe_member_reference_read_construction(original)
  assert_true(recipe is None)
  assert_eq(work, 1L)
  assert_eq(member_reference_construction_inspection_bound(original), 1L)
  assert_true(read_member(original, caps()) is Err(WrongSection))
}
