///|
// A SELECT without FROM evaluates over one logical row. The existing Values
// contract requires a nonempty schema, so its private witness is not part of
// expression scope or any user Result. It is computation, not a Source or an
// input Artifact, and never resolves an installed relation alias.
fn source_free_input(
  query : @query.Query,
  limits : Limits,
) -> Input raise Abort {
  // A bare star has no user-visible input columns. Never publish the private
  // Values witness through the identity-projection optimization.
  if @query.operation_at(query, 0) is Some(Select(projections, _)) &&
    projections.any(projection => projection.star is Some(_)) {
    raise Abort(UnsupportedProjection)
  }
  let document = @query.query_document(query)
  let generated = @origin.range(document, 0, 0, kind=Generated).unwrap()
  let builder = match @builder.create(document, limits.source) {
    Ok(value) => value
    Err(issue) => raise Abort(Construction(issue))
  }
  let construction : Construction = { builder, generated, }
  try {
    let field = "aql_source_free_unit"
    let name = "aql_source_free"
    let seed = construction.object([
      ("as", construction.text(name)),
      (
        "values",
        construction.object([
          (
            "schema",
            construction.object([
              (
                field,
                construction.object([
                  ("type", construction.text("boolean")),
                  ("nullable", construction.add(Bool(false))),
                ]),
              ),
            ]),
          ),
          (
            "rows",
            construction.array([
              construction.object([(field, construction.add(Bool(true)))]),
            ]),
          ),
        ]),
      ),
    ])
    let source = match @builder.finish(builder, seed) {
      Ok(value) => value
      Err(issue) => raise Abort(Construction(issue))
    }
    {
      relation: [],
      name,
      source: GeneratedValues(@builder.cursor(source)),
      visible_fields: [field],
      graph_bindings: [],
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      raise Abort(issue)
    }
  }
}

///|
fn query_columns(
  query : @query.Query,
  input : Input,
) -> Array[String] raise Abort {
  if @query.relation(query).is_empty() {
    []
  } else {
    columns(input)
  }
}
