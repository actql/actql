///|
priv struct MockChurnRiskInput {
  connection : String
  connector_id : String
  registration : String
  revision : String
  query_aliases : Array[(String, String)]
  update_aliases : Array[(String, String)]
  views : Array[RowRelationViewSpec]
}

///|
/// Original declaration DATA only. The actual installed Host independently
/// retains its Project/profile, generation, physical Source and authority.
pub struct MockChurnRiskCatalogue {
  priv sources : Array[(String, RowDeclaration)]
  priv query_aliases : Array[(String, RowDeclaration)]
  priv update_aliases : Array[(String, RowDeclaration)]
}

///|
pub fn prepare_mock_churn_risk_catalogue(
  limits : RowDeclarationLimits,
) -> Result[MockChurnRiskCatalogue, RowHostIssue] {
  let sources = []
  let query_aliases = []
  let update_aliases = []
  for input in mock_churn_risk_inputs() {
    let declaration = match
      generate_relation_row_declaration(
        input.connector_id,
        input.registration,
        input.revision,
        input.views,
        limits,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    sources.push((input.connection, declaration))
    for (name, resource) in input.query_aliases {
      guard declaration.views.length() == 1 &&
        declaration.views[0].resource == resource else {
        return Err(InvalidSpecification)
      }
      query_aliases.push((name, declaration))
    }
    for (name, resource) in input.update_aliases {
      guard declaration.views.length() == 1 &&
        declaration.views[0].resource == resource else {
        return Err(InvalidSpecification)
      }
      update_aliases.push((name, declaration))
    }
  }
  Ok({ sources, query_aliases, update_aliases, })
}

///|
pub fn mock_churn_risk_source_count(value : MockChurnRiskCatalogue) -> Int {
  value.sources.length()
}

///|
pub fn mock_churn_risk_source_at(
  value : MockChurnRiskCatalogue,
  index : Int,
) -> (String, RowDeclaration)? {
  value.sources.get(index)
}

///|
pub fn mock_churn_risk_query_alias_count(value : MockChurnRiskCatalogue) -> Int {
  value.query_aliases.length()
}

///|
pub fn mock_churn_risk_query_alias_at(
  value : MockChurnRiskCatalogue,
  index : Int,
) -> (String, RowDeclaration)? {
  value.query_aliases.get(index)
}

///|
pub fn mock_churn_risk_update_alias_count(
  value : MockChurnRiskCatalogue,
) -> Int {
  value.update_aliases.length()
}

///|
pub fn mock_churn_risk_update_alias_at(
  value : MockChurnRiskCatalogue,
  index : Int,
) -> (String, RowDeclaration)? {
  value.update_aliases.get(index)
}
