///|
// Reuse the selected keyword set without changing the permissive name parser.
// Closed schema keys and literal object keys have different admission roles.
fn query_reserved_word(value : String) -> Bool {
  [
    "ALL", "AND", "ANY", "ARRAY", "AS", "ASC", "ASSERT_ROWS_MODIFIED", "AT", "BETWEEN",
    "BY", "CASE", "CAST", "COLLATE", "CONTAINS", "CREATE", "CROSS", "CUBE", "CURRENT",
    "DEFAULT", "DEFINE", "DESC", "DISTINCT", "ELSE", "END", "ENUM", "ESCAPE", "EXCEPT",
    "EXCLUDE", "EXISTS", "EXTRACT", "FALSE", "FETCH", "FOLLOWING", "FOR", "FROM",
    "FULL", "GRAPH_TABLE", "GROUP", "GROUPING", "GROUPS", "HASH", "HAVING", "IF",
    "IGNORE", "IN", "INNER", "INTERSECT", "INTERVAL", "INTO", "IS", "JOIN", "LATERAL",
    "LEFT", "LIKE", "LIMIT", "LOOKUP", "MERGE", "NATURAL", "NEW", "NO", "NOT", "NULL",
    "NULLS", "OF", "ON", "OR", "ORDER", "OUTER", "OVER", "PARTITION", "PRECEDING",
    "PROTO", "QUALIFY", "RANGE", "RECURSIVE", "RESPECT", "RIGHT", "ROLLUP", "ROWS",
    "SELECT", "SET", "SOME", "STRUCT", "TABLESAMPLE", "THEN", "TO", "TREAT", "TRUE",
    "UNBOUNDED", "UNION", "UNNEST", "USING", "WHEN", "WHERE", "WINDOW", "WITH", "WITHIN",
  ].contains(ascii_upper(value))
}

///|
fn QueryParser::sga_output_name(
  self : QueryParser,
) -> NamePart raise QueryAbort {
  let token = self.peek()
  if token.value is Word(value) && query_reserved_word(value) {
    raise QueryAbort("Reserved output name requires backticks", token.start)
  }
  self.name()
}
