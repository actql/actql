///|
// FROM postfixes consume one table before surrounding JOIN or SELECT. Use
// the existing UNPIVOT operation and projected producer; only its output
// alias belongs to the outer range scope. PIVOT retains its existing path.
fn QueryParser::from_postfix_source(
  self : QueryParser,
  relation : Array[NamePart],
  input_alias : NamePart?,
  bindings : Array[QueryBinding],
  implicit_source_alias? : Bool = false,
) -> (Array[NamePart], NamePart?, Array[QueryBinding], Bool) raise QueryAbort {
  if !self.has("UNPIVOT") {
    return self.from_pivot_source(relation, input_alias, bindings, implicit_source_alias~)
  }
  let clause = self.unpivot_clause()
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
    joins: [],
    operations: [Unpivot(clause)],
    sets: [],
    final_operations: [],
    effect: None,
    table_effect: None,
    work: self.work,
  })
  (bound.relation, output_alias, bound.bindings, false)
}
