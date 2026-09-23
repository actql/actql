///|
pub(all) struct QueryPageLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_rows : Int
  max_locator_units : Int
}

///|
pub(all) enum QueryPageIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidLocator
  MissingRequiredField(String)
  NullRequiredField(String)
  UnexpectedField(String)
  ValueAdmission(String, @admitted.Issue)
} derive(Eq, Debug)

///|
/// One bounded Salesforce query batch. This is provider observation material,
/// not a typed Relation or a completed Acquisition receipt.
pub struct QueryPage {
  rows : Array[Array[@admitted.CheckedValue]]
  done : Bool
  next_url : String?
  total_size : Int64
  response_sha256 : String
}

///|
priv struct QueryValueBudget {
  mut nodes : Int
  mut text_bytes : Int
  max_depth : Int
}

///|
fn admit_query_cell(
  cursor : @decode.Cursor,
  contract : @contract.Contract,
  field_name : String,
  budget : QueryValueBudget,
) -> Result[@admitted.CheckedValue, QueryPageIssue] {
  let (checked, nodes, text) = match
    @admitted.admit_usage(contract, cursor, {
      max_nodes: budget.nodes,
      max_depth: budget.max_depth,
      max_text_bytes: budget.text_bytes,
    }) {
    Ok(result) => result
    Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) =>
      return Err(BudgetExceeded)
    Err(issue) => return Err(ValueAdmission(field_name, issue))
  }
  budget.nodes -= nodes
  budget.text_bytes -= text
  Ok(checked)
}

///|
fn query_api_version_valid(version : String) -> Bool {
  if version.length() < 4 || !version.has_prefix("v") {
    return false
  }
  let mut dot = false
  let mut before = 0
  let mut after = 0
  for index = 1; index < version.length(); index = index + 1 {
    let character = version[index]
    if character == '.' {
      if dot || before == 0 {
        return false
      }
      dot = true
    } else if character >= '0' && character <= '9' {
      if dot {
        after += 1
      } else {
        before += 1
      }
    } else {
      return false
    }
  }
  dot && after > 0 && version[1] != '0'
}

///|
fn query_page_locator_valid(locator : String, api_version : String) -> Bool {
  let prefix = "/services/data/" + api_version + "/query/"
  if locator.length() <= prefix.length() || !locator.has_prefix(prefix) {
    return false
  }
  for index = prefix.length(); index < locator.length(); index = index + 1 {
    let character = locator[index]
    if !((character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '_') {
      return false
    }
  }
  true
}

///|
pub fn project_query_page(
  bytes : Bytes,
  plan : ReadProjection,
  api_version : String,
  limits : QueryPageLimits,
) -> Result[QueryPage, QueryPageIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_rows < 0 ||
    limits.max_locator_units < 0 ||
    !query_api_version_valid(api_version) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  guard @decode.open_object(root) is Ok(object) &&
    @decode.lookup(object, "done") is Some(done_cursor) &&
    @decode.boolean(done_cursor) is Ok(done) &&
    @decode.lookup(object, "totalSize") is Some(total_cursor) &&
    @decode.safe_integer(total_cursor) is Ok(total_size) &&
    total_size >= 0L &&
    @decode.lookup(object, "records") is Some(records_cursor) &&
    @decode.array_length(records_cursor) is Some(count) else {
    return Err(InvalidResponse)
  }
  if count > limits.max_rows {
    return Err(BudgetExceeded)
  }
  let next_url = match @decode.field(object, "nextRecordsUrl") {
    Missing | ExplicitNull => None
    Present(cursor) =>
      match @decode.text(cursor) {
        Ok(value) => Some(value)
        Err(_) => return Err(InvalidLocator)
      }
  }
  if done {
    if next_url is Some(_) {
      return Err(InvalidLocator)
    }
  } else {
    guard next_url is Some(locator) &&
      locator.length() <= limits.max_locator_units &&
      query_page_locator_valid(locator, api_version) else {
      return Err(InvalidLocator)
    }
  }
  let rows = []
  let budget : QueryValueBudget = {
    nodes: limits.max_nodes,
    text_bytes: limits.max_bytes,
    max_depth: limits.max_depth,
  }
  for index in 0..<count {
    guard @decode.element_at(records_cursor, index) is Some(cursor) &&
      @decode.open_object(cursor) is Ok(record) &&
      @decode.object_field_names(cursor) is Ok(names) else {
      return Err(InvalidResponse)
    }
    for name in names {
      if name != "attributes" && !plan.fields.any(field => field.name == name) {
        return Err(UnexpectedField(name))
      }
    }
    let cells = []
    for column in 0..<plan.fields.length() {
      let field = plan.fields[column]
      let contract = plan.contracts[column]
      match @decode.lookup(record, field.name) {
        None => {
          if !field.nullable {
            return Err(MissingRequiredField(field.name))
          }
          if budget.nodes == 0 {
            return Err(BudgetExceeded)
          }
          budget.nodes -= 1
          cells.push(@admitted.checked_null_value(contract).unwrap())
        }
        Some(value) => {
          if @decode.is_null(value) && !field.nullable {
            return Err(NullRequiredField(field.name))
          }
          match admit_query_cell(value, contract, field.name, budget) {
            Ok(checked) => cells.push(checked)
            Err(issue) => return Err(issue)
          }
        }
      }
    }
    rows.push(cells)
  }
  Ok({ rows, done, next_url, total_size, response_sha256: @sha.hex(bytes), })
}

///|
pub fn query_page_row_count(page : QueryPage) -> Int {
  page.rows.length()
}

///|
pub fn query_page_cell(
  page : QueryPage,
  row : Int,
  column : Int,
) -> @admitted.CheckedValue? {
  match page.rows.get(row) {
    Some(values) => values.get(column)
    None => None
  }
}

///|
pub fn query_page_done(page : QueryPage) -> Bool {
  page.done
}

///|
pub fn query_page_next_url(page : QueryPage) -> String? {
  page.next_url
}

///|
pub fn query_page_response_sha256(page : QueryPage) -> String {
  page.response_sha256
}

///|
pub fn query_page_total_size(page : QueryPage) -> Int64 {
  page.total_size
}
