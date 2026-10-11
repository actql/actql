///|
// A FROM postfix transforms its own table before any surrounding JOIN or
// SELECT. Use the ordinary projected producer boundary for that relation;
// only the postfix output alias belongs to the outer query's range scope.
fn QueryParser::from_pivot_source(
  self : QueryParser,
  relation : Array[NamePart],
  input_alias : NamePart?,
  ctes : Array[CtePart],
) -> (Array[NamePart], NamePart?, Array[CtePart]) raise QueryAbort {
  if !self.has("PIVOT") {
    return (relation, input_alias, ctes)
  }
  let clause = self.pivot_clause()
  let output_alias = self.optional_source_alias()
  let bound = self.bind_query({
    source: self.source,
    positional_output: false,
    bound_source: None,
    ctes,
    relation,
    source_alias: input_alias,
    graph: None,
    joins: [],
    operations: [Pivot(clause)],
    sets: [],
    final_operations: [],
    effect: None,
    table_effect: None,
    work: self.work,
  })
  (bound.relation, output_alias, bound.ctes)
}
