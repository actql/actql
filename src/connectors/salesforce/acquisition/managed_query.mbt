///|
pub(all) enum ManagedQueryIssue {
  InvalidOutputSchema
  Query(@catalog.QueryReadIssue)
  Values(@execution.ManagedOutputValueIssue)
  Closed
  Incomplete
}

///|
/// One provider query observation and one common typed output owner. The
/// physical adapter supplies bounded response bytes; MoonBit owns page order,
/// value admission, row accounting, and the terminal handoff. Its receipt is
/// provisional content evidence, not an Acquisition completion or permission.
pub struct ManagedQuery {
  plan : @catalog.ReadProjection
  read : @catalog.QueryRead
  values : @execution.ManagedOutputValues
  columns : Array[Int]
  mut open : Bool
}

///|
fn projection_columns(
  plan : @catalog.ReadProjection,
  schema : @schema.Schema,
) -> (Array[Int], @catalog.ReadProjection)? {
  let names = @catalog.read_projection_fields(plan)
  if @schema.field_count(schema) != names.length() {
    return None
  }
  let indices : Map[String, Int] = Map([])
  for source_column in 0..<names.length() {
    let name = names[source_column]
    if indices.contains(name) {
      return None
    }
    indices[name] = source_column
  }
  let columns = []
  let contracts : Array[@contract.Contract?] = Array::make(names.length(), None)
  for output_column in 0..<names.length() {
    let field = @schema.field_at(schema, output_column).unwrap()
    let name = @schema.field_reference_name(field)
    guard indices.get(name) is Some(source_column) else { return None }
    if contracts[source_column] is Some(_) {
      return None
    }
    contracts[source_column] = Some(@schema.field_contract(field))
    columns.push(source_column)
  }
  let exact = []
  for contract in contracts {
    match contract {
      Some(value) => exact.push(value)
      None => return None
    }
  }
  @catalog.bind_read_projection_contracts(plan, exact).map(bound => {
    (columns, bound)
  })
}

///|
fn output_columns(
  plan : @catalog.ReadProjection,
  values : @execution.ManagedOutputValues,
) -> (Array[Int], @catalog.ReadProjection)? {
  projection_columns(plan, @execution.managed_output_values_schema(values))
}

///|
pub fn prepare_managed_query(
  plan : @catalog.ReadProjection,
  api_version : String,
  page_limits : @catalog.QueryPageLimits,
  max_pages : Int,
  max_total_rows : Int64,
  values : @execution.ManagedOutputValues,
) -> Result[ManagedQuery, ManagedQueryIssue] {
  let (columns, bound) = match output_columns(plan, values) {
    Some(value) => value
    None => return Err(InvalidOutputSchema)
  }
  let read = match
    @catalog.begin_query_read(
      bound, api_version, page_limits, max_pages, max_total_rows,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Query(issue))
  }
  Ok({ plan: bound, read, values, columns, open: true, })
}

///|
pub fn managed_query_next_path(query : ManagedQuery) -> String? {
  if query.open {
    @catalog.query_read_next_path(query.read)
  } else {
    None
  }
}

///|
pub fn cancel_managed_query(query : ManagedQuery) -> Bool {
  if !query.open {
    return false
  }
  query.open = false
  @catalog.interrupt_query_read(query.read) |> ignore
  @execution.cancel_managed_output_values(query.values) |> ignore
  true
}

///|
pub fn accept_managed_query_page(
  query : ManagedQuery,
  path : String,
  bytes : Bytes,
) -> Result[@catalog.QueryPage, ManagedQueryIssue] {
  if !query.open {
    return Err(Closed)
  }
  let page = match @catalog.query_read_accept_page(query.read, path, bytes) {
    Ok(value) => value
    Err(issue) => {
      cancel_managed_query(query) |> ignore
      return Err(Query(issue))
    }
  }
  if !@catalog.query_page_matches_projection(page, query.plan) {
    cancel_managed_query(query) |> ignore
    return Err(InvalidOutputSchema)
  }
  for row in 0..<@catalog.query_page_row_count(page) {
    match
      @execution.append_managed_output_values(
        query.values,
        query.columns.length(),
        column => @catalog.query_page_cell(page, row, query.columns[column]),
      ) {
      Ok(_) => ()
      Err(issue) => {
        cancel_managed_query(query) |> ignore
        return Err(Values(issue))
      }
    }
  }
  match @catalog.acknowledge_query_page(query.read, page) {
    Ok(_) => Ok(page)
    Err(issue) => {
      cancel_managed_query(query) |> ignore
      Err(Query(issue))
    }
  }
}

///|
pub fn managed_query_complete(query : ManagedQuery) -> Bool {
  query.open && @catalog.query_read_complete(query.read)
}

///|
pub fn managed_query_row_count(query : ManagedQuery) -> Int64 {
  @catalog.query_read_row_count(query.read)
}

///|
pub fn finish_managed_query(
  query : ManagedQuery,
) -> Result[@execution.ManagedOutputValueReceipt, ManagedQueryIssue] {
  if !query.open {
    return Err(Closed)
  }
  if !@catalog.query_read_complete(query.read) {
    return Err(Incomplete)
  }
  query.open = false
  @execution.finish_managed_output_values(query.values).map_err(issue => {
    Values(issue)
  })
}
