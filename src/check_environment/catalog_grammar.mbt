///|
/// Declared interpretation-body references, not concrete policy or Catalog data.
pub(all) enum CatalogGrammar {
  EnvironmentBody
  ValueGrammarBody
  GraphLawBody
  RelationLawBody
  ExpressionGrammar(ExpressionContractBody)
  TextPolicyGrammarBody
  CapacityGrammarBody
} derive(Eq, Debug)

///|
pub struct CatalogGrammarDependency {
  pointer : String
  target : CatalogGrammar
}

///|
/// Validate both the role and the pinned body; unknown is never a leaf.
pub fn catalog_dependency_grammar(v : CatalogBodyDependency) -> CatalogGrammar? {
  let body = match v.role {
    GoverningGrammar =>
      if v.cid == catalog_grammar_cid(ValueGrammarBody) {
        ValueGrammarBody
      } else {
        EnvironmentBody
      }
    ValueGrammar => ValueGrammarBody
    GraphIdentityLaw | GraphValueLaw => GraphLawBody
    RelationLaws => RelationLawBody
    ExpressionContract => ExpressionGrammar(ExpressionRoot)
  }
  if v.cid == catalog_grammar_cid(body) {
    Some(body)
  } else {
    None
  }
}

///|
pub fn catalog_grammar_dependency_count(v : CatalogGrammar) -> Int {
  match v {
    EnvironmentBody => environment_grammar_edge_count()
    ExpressionGrammar(body) => expression_contract_dependency_count(body)
    ValueGrammarBody
    | GraphLawBody
    | RelationLawBody
    | TextPolicyGrammarBody
    | CapacityGrammarBody => 0
  }
}

///|
pub fn catalog_grammar_dependency_at(
  v : CatalogGrammar,
  index : Int,
) -> CatalogGrammarDependency? {
  match v {
    EnvironmentBody => environment_grammar_edge(index)
    ExpressionGrammar(body) =>
      expression_contract_dependency_at(body, index).map(edge => {
        pointer: edge.pointer,
        target: ExpressionGrammar(edge.target),
      })
    ValueGrammarBody
    | GraphLawBody
    | RelationLawBody
    | TextPolicyGrammarBody
    | CapacityGrammarBody => None
  }
}
