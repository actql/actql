///|
test "Catalog Graph law closes through the same owned keyed law as constructor and MATCH" {
  let selected = core_catalog_grammar(@environment.GraphLawBody)
  assert_eq(selected, AdoptedBody(@pipeline.GraphLaw))
  assert_eq(
    core_contract_cid(selected),
    @environment.catalog_grammar_cid(@environment.GraphLawBody),
  )
  assert_eq(
    @environment.catalog_grammar_cid(@environment.GraphLawBody),
    "sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34",
  )
}
