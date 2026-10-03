///|
test "Catalog Graph law closes through the same owned keyed law as constructor and MATCH" {
  let selected = core_catalog_grammar(@environment.GraphLawBody)
  assert_eq(selected, AdoptedBody(@pipeline.PropertyGraphLaw))
  assert_eq(
    core_contract_cid(selected),
    @environment.catalog_grammar_cid(@environment.GraphLawBody),
  )
  assert_eq(
    @environment.catalog_grammar_cid(@environment.GraphLawBody),
    "sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc",
  )
}
