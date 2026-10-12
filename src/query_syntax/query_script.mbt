///|
// One query-expression owner for every public SQL/Pipe producer binding.
// This wrapper neither adds declarations nor reparses the original source.
struct QueryScript {
  query : Query
}

///|
pub fn script_query(script : QueryScript) -> Query {
  script.query
}

///|
pub fn script_document(script : QueryScript) -> @origin.Document {
  query_document(script.query)
}

///|
pub fn script_work(script : QueryScript) -> Int {
  query_work(script.query)
}

///|
pub fn parse_query_script(
  text : String,
  limits : QueryLimits,
  source_path? : String = "<query>",
) -> Result[QueryScript, Diagnostic] {
  parse_query(text, limits, source_path~).map(single_query_script)
}

///|
pub fn single_query_script(query : Query) -> QueryScript {
  { query, }
}
