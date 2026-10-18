///|
/// Extend the same original property binding with the public database Source
/// columns. The legacy property-only binding and its bytes remain unchanged.
/// This is checked DATA, not installation membership, a key proof or a Ref.
pub fn with_notion_source_system_contracts(
  binding : NotionDataSourceReadContracts,
  limits : NotionReadContractLimits,
) -> Result[NotionDataSourceReadContracts, NotionReadContractIssue] {
  if !read_contract_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !binding.system_columns.is_empty() {
    return Err(InvalidDeclaration)
  }
  let names = [
    "id", "url", "created_time", "created_by", "last_edited_time", "last_edited_by",
    "resource", "version",
  ]
  if names.length() > limits.max_columns ||
    binding.columns.length() > limits.max_columns - names.length() {
    return Err(BudgetExceeded)
  }
  let count = binding.columns.length() + names.length()
  if count >= limits.contracts.max_nodes || limits.contracts.max_depth < 2 {
    return Err(BudgetExceeded)
  }
  let mut work = limits.max_work
  let mut text = limits.contracts.max_text_bytes
  let fields = []
  for column in binding.columns {
    let bytes = @utf8.encode(column.name).length()
    if work == 0 || bytes > work - 1 || bytes > text {
      return Err(BudgetExceeded)
    }
    work -= 1 + bytes
    text -= bytes
    fields.push((column.name, column.contract))
  }
  let systems = []
  for name in names {
    let bytes = name.length()
    if work == 0 || bytes > work - 1 || bytes > text {
      return Err(BudgetExceeded)
    }
    work -= 1 + bytes
    text -= bytes
    let contract = if name == "created_time" || name == "last_edited_time" {
      @contract.primitive(TimestampType, nullable=false)
    } else {
      @contract.string_contract(nullable=false, min_length=Some(1L)).unwrap()
    }
    systems.push((name, contract))
    fields.push((name, contract))
  }
  let schema = match
    @contract.object_contract(
      fields,
      nullable=false,
      max_fields=limits.max_columns,
      max_name_bytes=limits.metadata.max_bytes,
    ) {
    Ok(value) => value
    // Do not overwrite a property whose original column has a system name.
    // Its explicit original read declaration can select a distinct column.
    Err(_) => return Err(InvalidColumn("names"))
  }
  Ok({ ..binding, system_columns: systems, schema, })
}

///|
fn notion_row_column_count(binding : NotionDataSourceReadContracts) -> Int {
  binding.columns.length() + binding.system_columns.length()
}

///|
fn notion_row_column(
  binding : NotionDataSourceReadContracts,
  index : Int,
) -> (String, @contract.Contract) {
  if index < binding.columns.length() {
    let column = binding.columns[index]
    (column.name, column.contract)
  } else {
    binding.system_columns[index - binding.columns.length()]
  }
}

///|
fn admit_notion_system_cell(
  row : OriginalNotionQueryRow,
  name : String,
  contract : @contract.Contract,
  limits : @admitted.Limits,
) -> Result[(@admitted.CheckedValue, Int, Int), NotionReadRowIssue] {
  guard @decode.open_object(row.original) is Ok(original) else {
    return Err(InvalidSystemField(name))
  }
  let field = match name {
    "resource" => "id"
    "version" => "last_edited_time"
    _ => name
  }
  guard @decode.lookup(original, field) is Some(cursor) else {
    return Err(InvalidSystemField(name))
  }
  let selected = if name == "created_by" || name == "last_edited_by" {
    guard @decode.open_object(cursor) is Ok(user) &&
      text_is(user, "object", "user") &&
      @decode.lookup(user, "id") is Some(id) else {
      return Err(InvalidSystemField(name))
    }
    id
  } else {
    cursor
  }
  guard @decode.text(selected) is Ok(text) && !text.is_empty() else {
    return Err(InvalidSystemField(name))
  }
  let value = if name == "created_time" || name == "last_edited_time" {
    guard @admitted.normalize_timestamp_text(text, limits.max_text_bytes)
      is Some(canonical) else {
      return Err(InvalidSystemField(name))
    }
    canonical
  } else {
    // In particular, version is the original last_edited_time spelling.
    // It is a correlation coordinate, not a canonical Timestamp or capability.
    text
  }
  let cursor = match
    @decode.admit(
      { value: @source.String(value), span: @decode.cursor_span(selected), },
      {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_text_bytes,
        max_total_string_bytes: limits.max_text_bytes,
      },
    ) {
    Ok(value) => value
    Err(_) => return Err(BudgetExceeded)
  }
  match @admitted.admit_usage(contract, cursor, limits) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidSystemField(name))
  }
}
