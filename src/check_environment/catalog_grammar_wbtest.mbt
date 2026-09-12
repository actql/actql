///|
test "Catalog grammar resolution checks role as well as CID" {
  for body in [EnvironmentBody, ValueGrammarBody] {
    assert_eq(
      catalog_dependency_grammar({
        role: GoverningGrammar,
        cid: catalog_grammar_cid(body),
      }),
      Some(body),
    )
  }
  assert_true(
    catalog_dependency_grammar({
      role: ValueGrammar,
      cid: catalog_grammar_cid(EnvironmentBody),
    })
    is None,
  )
  assert_true(
    catalog_dependency_grammar({
      role: GraphIdentityLaw,
      cid: catalog_grammar_cid(RelationLawBody),
    })
    is None,
  )
  assert_true(
    catalog_dependency_grammar({
      role: GoverningGrammar,
      cid: "sha256:unknown",
    })
    is None,
  )
}
