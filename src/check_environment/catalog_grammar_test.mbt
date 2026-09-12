///|
test "Catalog interpretation dependencies preserve roles and shared targets" {
  let bodies : Array[CatalogGrammar] = [EnvironmentBody]
  let mut index = 0
  let mut edges = 0
  while index < bodies.length() {
    let body = bodies[index]
    let count = catalog_grammar_dependency_count(body)
    for invalid in [-2147483648, -1, count, 2147483647] {
      assert_true(catalog_grammar_dependency_at(body, invalid) is None)
    }
    for i in 0..<count {
      let edge = catalog_grammar_dependency_at(body, i).unwrap()
      assert_true(edge.pointer.has_prefix("/"))
      edges += 1
      if !bodies.contains(edge.target) {
        bodies.push(edge.target)
      }
    }
    index += 1
  }
  assert_eq(bodies.length(), 21)
  assert_eq(edges, 23)
  let identity = catalog_grammar_dependency_at(EnvironmentBody, 1).unwrap()
  let value = catalog_grammar_dependency_at(EnvironmentBody, 2).unwrap()
  assert_eq(identity.target, GraphLawBody)
  assert_eq(value.target, GraphLawBody)
  assert_true(identity.pointer != value.pointer)
}
