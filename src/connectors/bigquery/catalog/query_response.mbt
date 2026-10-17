///|
pub(all) struct QueryLimits {
  description : DescriptionLimits
  max_rows : Int
  max_total_rows : Int64
  max_value_nodes : Int
  max_value_text_bytes : Int
  max_job_bytes : Int
  max_page_token_bytes : Int
}

///|
pub(all) enum QueryIssue {
  InvalidQueryLimits
  QueryLimit
  InvalidQueryResponse
  InvalidQueryJob
  ForeignQueryJob
  QueryPending
  QueryDiagnostics
  QuerySchemaMismatch(String)
  InvalidQueryCell(String)
  QueryValueAdmission(String, @admitted.Issue)
} derive(Eq, Debug)

///|
/// Routing DATA for the same observed Job. It is not a request, permission,
/// current observation, durable Job record, launch token or completion ACK.
pub struct QueryJob {
  priv project : String
  priv job_id : String
  priv location : String
}

///|
/// A single bounded response, bound to the original projection and Job DATA.
/// Page completion does not establish full-result completion or physical stop.
pub struct QueryPage {
  priv projection : ReadProjection
  priv job : QueryJob
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv total_rows : Int64
  priv page_token : String?
  priv response_sha256 : String
}

///|
priv struct QueryColumn {
  original : ColumnDescription
  mode : String
  children : Array[QueryColumn]
}

///|
priv struct QueryValueBudget {
  mut nodes : Int
  mut text_bytes : Int
  max_depth : Int
}

///|
pub fn query_job(
  project : String,
  job_id : String,
  location : String,
  max_bytes : Int,
) -> Result[QueryJob, QueryIssue] {
  if max_bytes <= 0 {
    return Err(InvalidQueryLimits)
  }
  let mut remaining = max_bytes
  for text in [project, job_id, location] {
    guard name_size(text, remaining) is Some(size) else {
      return Err(InvalidQueryJob)
    }
    remaining -= size
  }
  // JobReference's declared identifier domain, not a fabricated UUID-only
  // restriction. Routing still needs the original authenticated physical port.
  if job_id.length() > 1024 ||
    !job_id.to_array().all(c =>
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-') {
    return Err(InvalidQueryJob)
  }
  Ok({ project, job_id, location, })
}

///|
fn valid_query_limits(limits : QueryLimits) -> Bool {
  valid_limits(limits.description) &&
  limits.max_rows >= 0 &&
  limits.max_total_rows >= 0L &&
  limits.max_value_nodes > 0 &&
  limits.max_value_text_bytes > 0 &&
  limits.max_job_bytes > 0 &&
  limits.max_page_token_bytes > 0
}

///|
fn query_root(bytes : Bytes, limits : QueryLimits) -> Result[@decode.Cursor, QueryIssue] {
  if !valid_query_limits(limits) {
    return Err(InvalidQueryLimits)
  }
  let bound = limits.description
  if bytes.length() > bound.max_bytes {
    return Err(QueryLimit)
  }
  let parsed = match @source.parse_json_bytes_preserving(bytes, {
    max_input_bytes: bound.max_bytes,
    max_nodes: bound.max_nodes,
    max_depth: bound.max_depth,
  }) {
    Ok(value) => value
    Err({ issue: InputLimit | NodeLimit | DepthLimit, .. }) => return Err(QueryLimit)
    Err(_) => return Err(InvalidQueryResponse)
  }
  match @decode.admit(parsed, {
    max_nodes: bound.max_nodes,
    max_depth: bound.max_depth,
    max_string_bytes: bound.max_bytes,
    max_total_string_bytes: bound.max_bytes,
  }) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidQueryResponse)
  }
}

///|
fn native_kind(kind : String) -> String {
  match kind {
    "FLOAT" => "FLOAT64"
    "BOOLEAN" => "BOOL"
    "DECIMAL" => "NUMERIC"
    "BIGDECIMAL" => "BIGNUMERIC"
    "STRUCT" => "RECORD"
    _ => kind
  }
}

///|
fn find_query_original(columns : Array[ColumnDescription], name : String) -> ColumnDescription? {
  for column in columns {
    if column.name == name { return Some(column) }
  }
  None
}

///|
fn query_column(
  cursor : @decode.Cursor,
  original : ColumnDescription,
  budget : DescriptionBudget,
  depth : Int,
  limits : DescriptionLimits,
) -> Result[QueryColumn, QueryIssue] {
  if depth > limits.max_depth || budget.fields == 0 {
    return Err(QueryLimit)
  }
  budget.fields -= 1
  guard @decode.open_object(cursor) is Ok(object) &&
    required_text(object, "name") == Some(original.name) &&
    required_text(object, "type") is Some(kind) &&
    native_kind(kind) == native_kind(original.native_type) else {
    return Err(QuerySchemaMismatch(original.name))
  }
  for text in [original.name, kind] {
    guard name_size(text, budget.names) is Some(size) else {
      return Err(QueryLimit)
    }
    budget.names -= size
  }
  let mode = match @decode.lookup(object, "mode") {
    None => "NULLABLE"
    Some(value) => match @decode.text(value) {
      Ok(text) => text
      Err(_) => return Err(QuerySchemaMismatch(original.name))
    }
  }
  if !["NULLABLE", "REQUIRED", "REPEATED"].contains(mode) ||
    ((mode == "REPEATED") != (original.mode == "REPEATED")) {
    return Err(QuerySchemaMismatch(original.name))
  }
  // Query schemas may omit parameterization. Never replace the captured
  // original contract with an unparameterized decimal default. When supplied,
  // used constraints must agree with the observed original metadata.
  let effective = match original.contract {
    Some(contract) => match contract.shape {
      @contract.Array(element, ..) => element
      _ => contract
    }
    None => return Err(QuerySchemaMismatch(original.name))
  }
  let (precision, scale) = match effective.shape {
    @contract.Decimal(precision~, scale~) => (Some(precision.to_int64()), Some(scale.to_int64()))
    _ => (original.precision, original.scale)
  }
  for (key, expected) in [("precision", precision), ("scale", scale)] {
    if @decode.lookup(object, key) is Some(_) {
      match optional_decimal(object, key, original.name) {
        Ok(value) if value == expected => ()
        _ => return Err(QuerySchemaMismatch(original.name))
      }
    }
  }
  let children : Array[QueryColumn] = []
  if native_kind(kind) == "RECORD" {
    guard @decode.lookup(object, "fields") is Some(fields) &&
      @decode.array_length(fields) == Some(original.children.length()) else {
      return Err(QuerySchemaMismatch(original.name))
    }
    let seen : Array[String] = []
    for index in 0..<original.children.length() {
      let field = @decode.element_at(fields, index).unwrap()
      guard @decode.open_object(field) is Ok(child) &&
        required_text(child, "name") is Some(name) && !seen.contains(name) else {
        return Err(QuerySchemaMismatch(original.name))
      }
      seen.push(name)
      guard find_query_original(original.children, name) is Some(selected) else {
        return Err(QuerySchemaMismatch(name))
      }
      match query_column(field, selected, budget, depth + 1, limits) {
        Ok(value) => children.push(value)
        Err(issue) => return Err(issue)
      }
    }
  } else if @decode.lookup(object, "fields") is Some(_) {
    return Err(QuerySchemaMismatch(original.name))
  }
  Ok({ original, mode, children, })
}

///|
fn query_checked(
  cursor : @decode.Cursor,
  contract : @contract.Contract,
  name : String,
  budget : QueryValueBudget,
) -> Result[@admitted.CheckedValue, QueryIssue] {
  match @admitted.admit_usage(contract, cursor, {
    max_nodes: budget.nodes,
    max_text_bytes: budget.text_bytes,
    max_depth: budget.max_depth,
  }) {
    Ok((value, nodes, text)) => {
      budget.nodes -= nodes
      budget.text_bytes -= text
      Ok(value)
    }
    Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) => Err(QueryLimit)
    Err(issue) => Err(QueryValueAdmission(name, issue))
  }
}

///|
fn converted_query_cell(
  node : @source.Node,
  contract : @contract.Contract,
  name : String,
  budget : QueryValueBudget,
) -> Result[@admitted.CheckedValue, QueryIssue] {
  match @decode.admit(node, {
    max_nodes: budget.nodes,
    max_depth: budget.max_depth,
    max_string_bytes: budget.text_bytes,
    max_total_string_bytes: budget.text_bytes,
  }) {
    Ok(cursor) => query_checked(cursor, contract, name, budget)
    Err(_) => Err(QueryLimit)
  }
}

///|
fn query_cell_value(
  cursor : @decode.Cursor,
  column : QueryColumn,
  contract : @contract.Contract,
  repeated : Bool,
  budget : QueryValueBudget,
  depth : Int,
  limits : QueryLimits,
) -> Result[@admitted.CheckedValue, QueryIssue] {
  let name = column.original.name
  if depth > budget.max_depth || budget.nodes <= 0 {
    return Err(QueryLimit)
  }
  if @decode.is_null(cursor) {
    // SQL NULL is distinct from an absent v, an empty array and JSON "null".
    if repeated || column.mode == "REQUIRED" {
      return Err(InvalidQueryCell(name))
    }
    return query_checked(cursor, contract, name, budget)
  }
  if repeated {
    guard contract.shape is @contract.Array(element, ..) &&
      @decode.array_length(cursor) is Some(count) else {
      return Err(InvalidQueryCell(name))
    }
    if count > budget.nodes - 1 {
      return Err(QueryLimit)
    }
    budget.nodes -= 1
    let values : Array[@admitted.Value] = []
    for index in 0..<count {
      guard @decode.closed_object(@decode.element_at(cursor, index).unwrap(), ["v"]) is Ok(wrapper) &&
        @decode.lookup(wrapper, "v") is Some(value) && !@decode.is_null(value) else {
        return Err(InvalidQueryCell(name))
      }
      match query_cell_value(value, column, element, false, budget, depth + 1, limits) {
        Ok(value) => values.push(value.value)
        Err(issue) => return Err(issue)
      }
    }
    guard @admitted.recheck_runtime_value(@admitted.array_value(values), contract, {
      max_nodes: limits.max_value_nodes,
      max_text_bytes: limits.max_value_text_bytes,
      max_depth: budget.max_depth,
    }) is Some(checked) else { return Err(InvalidQueryCell(name)) }
    return Ok(checked)
  }
  if native_kind(column.original.native_type) == "RECORD" {
    guard @decode.closed_object(cursor, ["f"]) is Ok(object) &&
      @decode.lookup(object, "f") is Some(fields) &&
      @decode.array_length(fields) == Some(column.children.length()) else {
      return Err(InvalidQueryCell(name))
    }
    budget.nodes -= 1
    let values : Array[(String, @admitted.Value)] = []
    for index, child in column.children {
      guard @decode.closed_object(@decode.element_at(fields, index).unwrap(), ["v"]) is Ok(wrapper) &&
        @decode.lookup(wrapper, "v") is Some(value) &&
        child.original.contract is Some(child_contract) else {
        return Err(InvalidQueryCell(child.original.name))
      }
      match query_cell_value(value, child, child_contract, child.mode == "REPEATED", budget, depth + 1, limits) {
        Ok(value) => values.push((child.original.name, value.value))
        Err(issue) => return Err(issue)
      }
    }
    guard @admitted.object_value(values) is Some(value) &&
      @admitted.recheck_runtime_value(value, contract, {
        max_nodes: limits.max_value_nodes,
        max_text_bytes: limits.max_value_text_bytes,
        max_depth: budget.max_depth,
      }) is Some(checked) else { return Err(InvalidQueryCell(name)) }
    return Ok(checked)
  }
  guard @decode.text(cursor) is Ok(text) else {
    return Err(InvalidQueryCell(name))
  }
  match native_kind(column.original.native_type) {
    "STRING" | "DATE" => query_checked(cursor, contract, name, budget)
    "NUMERIC" | "BIGNUMERIC" => {
      guard contract.shape is @contract.Decimal(precision~, scale~) else {
        return Err(QuerySchemaMismatch(name))
      }
      let canonical = match @admitted.normalize_decimal_text(text, precision, scale, budget.text_bytes) {
        Ok(value) => value
        Err(InputLimit | InvalidLimits) => return Err(QueryLimit)
        Err(_) => return Err(InvalidQueryCell(name))
      }
      converted_query_cell({ value: String(canonical), span: @decode.cursor_span(cursor), }, contract, name, budget)
    }
    "BOOL" => {
      let flag = match text {
        "true" => true
        "false" => false
        _ => return Err(InvalidQueryCell(name))
      }
      converted_query_cell({ value: Bool(flag), span: @decode.cursor_span(cursor), }, contract, name, budget)
    }
    "FLOAT64" => {
      let parsed = match @source.parse_json_bytes_preserving(@utf8.encode(text), {
        max_input_bytes: budget.text_bytes,
        max_nodes: budget.nodes,
        max_depth: budget.max_depth,
      }) {
        Ok(value) if value.value is Number(_) => value
        _ => return Err(InvalidQueryCell(name))
      }
      converted_query_cell(parsed, contract, name, budget)
    }
    "JSON" => {
      let (value, nodes, bytes) = match @admitted.admit_json_literal(text, {
        max_nodes: budget.nodes,
        max_text_bytes: budget.text_bytes,
        max_depth: budget.max_depth,
      }) {
        Ok(value) => value
        Err(_) => return Err(InvalidQueryCell(name))
      }
      guard @admitted.recheck_runtime_value(value.value, contract, {
        max_nodes: budget.nodes,
        max_text_bytes: budget.text_bytes,
        max_depth: budget.max_depth,
      }) is Some(checked) else { return Err(QueryLimit) }
      budget.nodes -= nodes
      budget.text_bytes -= bytes
      Ok(checked)
    }
    _ => Err(InvalidQueryCell(name))
  }
}

///|
pub fn project_query_page(
  projection : ReadProjection,
  job : QueryJob,
  bytes : Bytes,
  limits : QueryLimits,
) -> Result[QueryPage, QueryIssue] {
  let root = match query_root(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "jobReference") is Some(reference) &&
    @decode.open_object(reference) is Ok(reference) else {
    return Err(InvalidQueryResponse)
  }
  let location = match @decode.lookup(reference, "location") {
    None => "US" // The provider's documented JobReference default only.
    Some(value) => match @decode.text(value) {
      Ok(text) => text
      Err(_) => return Err(InvalidQueryResponse)
    }
  }
  guard required_text(reference, "projectId") == Some(job.project) &&
    required_text(reference, "jobId") == Some(job.job_id) && location == job.location &&
    job.project == projection.original.target.project else {
    return Err(ForeignQueryJob)
  }
  match query_job(job.project, job.job_id, job.location, limits.max_job_bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @decode.lookup(object, "jobComplete") is Some(done) &&
    @decode.boolean(done) is Ok(done) else {
    return Err(InvalidQueryResponse)
  }
  if !done {
    if @decode.lookup(object, "rows") is Some(_) || @decode.lookup(object, "totalRows") is Some(_) {
      return Err(InvalidQueryResponse)
    }
    return Err(QueryPending)
  }
  if @decode.lookup(object, "errors") is Some(errors) {
    guard @decode.array_length(errors) is Some(count) else { return Err(InvalidQueryResponse) }
    if count > 0 {
      // These can be warnings; do not convert their presence to Job failed or
      // committed. The physical caller retains the original diagnostic facts.
      return Err(QueryDiagnostics)
    }
  }
  guard required_text(object, "totalRows") is Some(total) else {
    return Err(InvalidQueryResponse)
  }
  let total_rows = match @scalar.read_decimal_int64(total) {
    Ok(value) if value >= 0L && value <= limits.max_total_rows => value
    _ => return Err(QueryLimit)
  }
  let page_token = match @decode.lookup(object, "pageToken") {
    None => None
    Some(cursor) => match @decode.text(cursor) {
      Ok("") => None
      Ok(text) => {
        match @scalar.admit_utf8_length(text, limits.max_page_token_bytes) {
          Err(_) => return Err(QueryLimit)
          Ok(_) => ()
        }
        Some(text)
      }
      Err(_) => return Err(InvalidQueryResponse)
    }
  }
  guard @decode.lookup(object, "schema") is Some(schema) &&
    @decode.open_object(schema) is Ok(schema) &&
    @decode.lookup(schema, "fields") is Some(fields) &&
    @decode.array_length(fields) == Some(projection.fields.length()) else {
    return Err(QuerySchemaMismatch(""))
  }
  let metadata_budget : DescriptionBudget = {
    fields: limits.description.max_fields,
    names: limits.description.max_name_bytes,
  }
  let columns : Array[QueryColumn] = []
  for index, name in projection.fields {
    guard find_query_original(projection.original.columns, name) is Some(original) &&
      original.contract is Some(_) else { return Err(QuerySchemaMismatch(name)) }
    match query_column(@decode.element_at(fields, index).unwrap(), original, metadata_budget, 1, limits.description) {
      Ok(value) => columns.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let rows_cursor = @decode.lookup(object, "rows")
  let count = match rows_cursor {
    None if total_rows == 0L => 0
    Some(cursor) => match @decode.array_length(cursor) {
      Some(count) => count
      None => return Err(InvalidQueryResponse)
    }
    _ => return Err(InvalidQueryResponse)
  }
  if count > limits.max_rows || count.to_int64() > total_rows {
    return Err(QueryLimit)
  }
  let rows : Array[Array[@admitted.CheckedValue]] = []
  let budget : QueryValueBudget = {
    nodes: limits.max_value_nodes,
    text_bytes: limits.max_value_text_bytes,
    max_depth: limits.description.max_depth,
  }
  for index in 0..<count {
    let row = @decode.element_at(rows_cursor.unwrap(), index).unwrap()
    guard @decode.closed_object(row, ["f"]) is Ok(row) &&
      @decode.lookup(row, "f") is Some(fields) &&
      @decode.array_length(fields) == Some(columns.length()) else {
      return Err(InvalidQueryResponse)
    }
    let values : Array[@admitted.CheckedValue] = []
    for index, column in columns {
      guard @decode.closed_object(@decode.element_at(fields, index).unwrap(), ["v"]) is Ok(wrapper) &&
        @decode.lookup(wrapper, "v") is Some(cursor) else {
        return Err(InvalidQueryCell(column.original.name))
      }
      match query_cell_value(cursor, column, column.original.contract.unwrap(), column.mode == "REPEATED", budget, 1, limits) {
        Ok(value) => values.push(value)
        Err(issue) => return Err(issue)
      }
    }
    rows.push(values)
  }
  Ok({ projection, job, rows, total_rows, page_token, response_sha256: @sha.hex(bytes), })
}

///|
pub fn query_page_matches_original(page : QueryPage, projection : ReadProjection, job : QueryJob) -> Bool {
  physical_equal(page.projection, projection) && physical_equal(page.job, job)
}

///|
pub fn query_page_row_count(page : QueryPage) -> Int {
  page.rows.length()
}

///|
pub fn query_page_total_rows(page : QueryPage) -> Int64 {
  page.total_rows
}

///|
pub fn query_page_next_token(page : QueryPage) -> String? {
  page.page_token
}

///|
pub fn query_page_cell(page : QueryPage, row : Int, column : Int) -> @admitted.CheckedValue? {
  match page.rows.get(row) {
    Some(values) => values.get(column)
    None => None
  }
}

///|
pub fn query_page_response_sha256(page : QueryPage) -> String {
  page.response_sha256
}
