///|
// A FROM postfix transforms its own table before any surrounding JOIN or
// SELECT. Use the ordinary projected producer boundary for that relation;
// only the postfix output alias belongs to the outer query's range scope.
fn QueryParser::from_pivot_source(
  self : QueryParser,
  relation : Array[NamePart],
  input_alias : NamePart?,
  bindings : Array[QueryBinding],
  implicit_source_alias? : Bool = false,
) -> (Array[NamePart], NamePart?, Array[QueryBinding], Bool) raise QueryAbort {
  if !self.has("PIVOT") {
    return (relation, input_alias, bindings, implicit_source_alias)
  }
  let clause = self.pivot_clause()
  let output_alias = self.optional_source_alias()
  let bound = self.bind_query({
    source: self.source,
    primary: None,
    implicit_source_alias,
    positional_output: false,
    bound_source: None,
    bindings,
    relation,
    source_alias: input_alias,
    graph: None,
    file_listing: None,
    joins: [],
    operations: [Pivot(clause)],
    sets: [],
    final_operations: [],
    effect: None,
    table_effect: None,
    commands: [],
    work: self.work,
  })
  (bound.relation, output_alias, bound.bindings, false)
}
