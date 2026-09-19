///|
test "nest expansion table covers order and reference projections" {
  let inherited = prepare_nest_expansion(false, false, false)
  assert_eq(inherited.length(), 11)
  assert_eq(nest_expansion_reference_count(inherited), 14)
  assert_false(nest_expansion_has_role(inherited, "ordered"))

  let authored = prepare_nest_expansion(false, false, true)
  assert_eq(authored.length(), 12)
  assert_eq(nest_expansion_reference_count(authored), 15)
  assert_true(nest_expansion_has_role(authored, "ordered"))

  let references = prepare_nest_expansion(true, true, false)
  assert_eq(references.length(), 13)
  assert_eq(nest_expansion_reference_count(references), 16)
  assert_true(nest_expansion_has_role(references, "parent_refs"))
  assert_true(nest_expansion_has_role(references, "child_refs"))
  assert_true(references[references.length() - 1].source_node)
}
