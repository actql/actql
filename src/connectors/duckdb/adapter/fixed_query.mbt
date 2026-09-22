///|
/// Fixed-input SQL realizations, deliberately separate from Acquisition.
/// A group/count does not acquire a dummy predicate or bound SQL parameter.
pub enum FixedQuery {
  FilterSelect(NativeQuery)
  CountGroup(NativeCountGroup)
  InnerJoin(NativeInnerJoin)
}

///|
pub fn compile_fixed_query(
  owner : @lower.BoundPrepared,
  database_schema : String,
  table : String,
  limits : NativeQueryLimits,
) -> Result[FixedQuery, NativeQueryIssue] {
  if @lower.node_count(@lower.bound_preparation(owner)) == 1 {
    compile_fixed_count_group(owner, database_schema, table, limits).map(query => {
      CountGroup(query)
    })
  } else {
    compile_native_filter_select(owner, database_schema, table, limits).map(query => {
      FilterSelect(query)
    })
  }
}

///|
pub fn fixed_query_owner(query : FixedQuery) -> @lower.BoundPrepared {
  match query {
    FilterSelect(query) => query.owner
    CountGroup(query) => query.owner
    InnerJoin(query) => query.owner
  }
}

///|
pub fn fixed_query_sql(query : FixedQuery) -> String {
  match query {
    FilterSelect(query) => query.sql
    CountGroup(query) => query.sql
    InnerJoin(query) => query.sql
  }
}

///|
pub fn fixed_query_parameter_count(query : FixedQuery) -> Int {
  match query {
    FilterSelect(_) => 1
    CountGroup(_) => 0
    InnerJoin(_) => 0
  }
}

///|
pub fn fixed_query_parameter(
  query : FixedQuery,
  index : Int,
) -> PhysicalParameter? {
  match query {
    FilterSelect(query) if index == 0 => Some(query.parameter)
    _ => None
  }
}

///|
pub fn fixed_query_target(query : FixedQuery) -> @pipeline.Target {
  match query {
    FilterSelect(_) => Step(1)
    CountGroup(_) => Step(0)
    InnerJoin(_) => Step(0)
  }
}

///|
pub fn fixed_query_input_table(query : FixedQuery, port : Int) -> String? {
  match query {
    FilterSelect(query) if port == 0 => Some(query.table)
    CountGroup(query) if port == 0 => Some(query.table)
    InnerJoin(query) => query.tables.get(port)
    _ => None
  }
}

///|
fn fixed_query_output_names(query : FixedQuery) -> Array[String]? {
  match query {
    CountGroup(query) => Some(fixed_count_group_output_names(query))
    _ => None
  }
}
