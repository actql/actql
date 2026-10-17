///|
pub(all) struct RecordValueLimits {
  max_columns : Int
  max_name_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) enum RecordValueIssue {
  InvalidLimits
  BudgetExceeded
  ForeignSettings
  FieldUnavailable(String)
  UnrepresentableField(String)
  InvalidValue(String)
  DecimalValue(String, @admitted.DecimalTextIssue)
  ValueAdmission(String, @admitted.Issue)
} derive(Eq, Debug)

///|
pub struct CheckedRecordPage {
  priv original : OriginalRecordPage
  priv settings : AppNumberSettings?
  priv columns : Array[String]
  priv rows : Array[Array[@admitted.CheckedValue]]
}

///|
priv struct RecordValueBudget {
  mut nodes : Int
  mut text_bytes : Int
  depth : Int
}

///|
fn record_value_limits_valid(limits : RecordValueLimits) -> Bool {
  limits.max_columns > 0 &&
  limits.max_name_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_text_bytes > 0
}

///|
fn record_settings_match(
  catalog : FormFieldCatalog,
  settings : AppNumberSettings?,
) -> Bool {
  match settings {
    Some(settings) =>
      catalog.app_id == settings.app_id && catalog.revision == settings.revision
    None => true
  }
}

///|
fn record_field_contract(
  catalog : FormFieldCatalog,
  field : FormFieldMetadata,
  settings : AppNumberSettings?,
  limits : RecordValueLimits,
  budget : RecordValueBudget,
  depth : Int,
) -> Result[@contract.Contract, RecordValueIssue] {
  if budget.nodes <= 0 || depth > budget.depth {
    return Err(BudgetExceeded)
  }
  budget.nodes -= 1
  let nullable = field.required != Some(true)
  let text = @contract.primitive(@contract.StringType, nullable=false)
  match field.native_type {
    "NUMBER" | "CALC" if field.native_type == "NUMBER" ||
      field.calculation_format == Some("NUMBER") ||
      field.calculation_format == Some("NUMBER_DIGIT") => {
      guard settings is Some(original) else {
        return Err(FieldUnavailable(field.code))
      }
      // The provider documents integer digits <= digits - decimalPlaces,
      // and fractional storage precision decimalPlaces. DisplayScale does
      // not narrow this storage domain or change the supplied value.
      match
        @contract.decimal_contract(
          original.digits,
          original.decimal_places,
          nullable~,
        ) {
        Some(contract) => Ok(contract)
        None => Err(FieldUnavailable(field.code))
      }
    }
    "SINGLE_LINE_TEXT"
    | "MULTI_LINE_TEXT"
    | "RICH_TEXT"
    | "LINK"
    | "RECORD_NUMBER"
    | "STATUS"
    | "CREATOR"
    | "MODIFIER" => Ok(text)
    "RADIO_BUTTON" | "DROP_DOWN" =>
      Ok(@contract.primitive(@contract.StringType, nullable~))
    "DATE" => Ok(@contract.primitive(@contract.DateType, nullable~))
    "DATETIME" | "CREATED_TIME" | "UPDATED_TIME" =>
      Ok(@contract.primitive(@contract.TimestampType, nullable~))
    "CALC" if [
        Some("DATETIME"),
        Some("DATE"),
        Some("TIME"),
        Some("HOUR_MINUTE"),
        Some("DAY_HOUR_MINUTE"),
      ].contains(field.calculation_format) => Ok(text)
    "CHECK_BOX"
    | "MULTI_SELECT"
    | "CATEGORY"
    | "USER_SELECT"
    | "ORGANIZATION_SELECT"
    | "GROUP_SELECT"
    | "STATUS_ASSIGNEE" => {
      if budget.nodes <= 0 {
        return Err(BudgetExceeded)
      }
      budget.nodes -= 1
      match @contract.array_contract(text, nullable=false) {
        Some(contract) => Ok(contract)
        None => Err(FieldUnavailable(field.code))
      }
    }
    "SUBTABLE" => {
      if budget.nodes <= 1 {
        return Err(BudgetExceeded)
      }
      budget.nodes -= 2
      let entries = [("id", text)]
      for child in record_table_children(catalog, field) {
        if child.code == "id" {
          return Err(UnrepresentableField(child.code))
        }
        let contract = match
          record_field_contract(
            catalog,
            child,
            settings,
            limits,
            budget,
            depth + 2,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if entries.length() >= limits.max_columns {
          return Err(BudgetExceeded)
        }
        entries.push((child.code, contract))
      }
      let object = match
        @contract.object_contract(
          entries,
          nullable=false,
          max_fields=limits.max_columns,
          max_name_bytes=limits.max_name_bytes,
        ) {
        Ok(value) => value
        Err(@contract.ConstructionLimit) => return Err(BudgetExceeded)
        Err(_) => return Err(UnrepresentableField(field.code))
      }
      match @contract.array_contract(object, nullable=false) {
        Some(value) => Ok(value)
        None => Err(UnrepresentableField(field.code))
      }
    }
    // Shared Time/int64 and issued Content references must arrive through
    // their existing owners, never String/Double or a fabricated reference.
    _ => Err(FieldUnavailable(field.code))
  }
}

///|
fn record_contracts(
  catalog : FormFieldCatalog,
  settings : AppNumberSettings?,
  names : Array[String],
  limits : RecordValueLimits,
) -> Result[Array[@contract.Contract], RecordValueIssue] {
  if !record_value_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if names.length() >= limits.max_columns {
    return Err(BudgetExceeded)
  }
  if !record_settings_match(catalog, settings) {
    return Err(ForeignSettings)
  }
  let seen : Map[String, Bool] = Map([])
  let contracts = [@contract.primitive(@contract.StringType, nullable=false)]
  let budget : RecordValueBudget = {
    nodes: limits.max_nodes,
    text_bytes: limits.max_text_bytes,
    depth: limits.max_depth,
  }
  for name in names {
    if name.length() > limits.max_name_bytes {
      return Err(BudgetExceeded)
    }
    if name == "$id" || seen.contains(name) {
      return Err(UnrepresentableField(name))
    }
    seen[name] = true
    guard form_field_named(catalog, [name]) is Some(field) else {
      return Err(FieldUnavailable(name))
    }
    match record_field_contract(catalog, field, settings, limits, budget, 1) {
      Ok(value) => contracts.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let entries = [("$id", contracts[0])]
  for index, name in names {
    entries.push((name, contracts[index + 1]))
  }
  match
    @contract.object_contract(
      entries,
      nullable=false,
      max_fields=limits.max_columns,
      max_name_bytes=limits.max_name_bytes,
    ) {
    Ok(_) => ()
    Err(@contract.ConstructionLimit) => return Err(BudgetExceeded)
    Err(_) => return Err(UnrepresentableField("schema"))
  }
  Ok(contracts)
}

///|
fn record_value_node(
  field : OriginalRecordField,
  contract : @contract.Contract,
  budget : RecordValueBudget,
  depth : Int,
) -> Result[@source.Node, RecordValueIssue] {
  let code = field.metadata.code
  let cursor = field.value
  let span = @decode.cursor_span(cursor)
  if budget.nodes <= 0 || depth > budget.depth {
    return Err(BudgetExceeded)
  }
  budget.nodes -= 1
  let source : @source.Value = if @decode.is_null(cursor) {
    @source.Null
  } else {
    match field.metadata.native_type {
      "SUBTABLE" => {
        guard field.table_rows is Some(rows) &&
          contract.shape is @contract.Array(item, ..) &&
          item.shape is @contract.Object(fields) else {
          return Err(InvalidValue(code))
        }
        if rows.length() > budget.nodes {
          return Err(BudgetExceeded)
        }
        let values : Array[@source.Node] = []
        for row in rows {
          if budget.nodes < 2 || depth + 1 > budget.depth {
            return Err(BudgetExceeded)
          }
          budget.nodes -= 2
          if row.id.length() > budget.text_bytes {
            return Err(BudgetExceeded)
          }
          budget.text_bytes -= row.id.length()
          let entries : Array[@source.Field] = [
            {
              key: "id",
              key_span: span,
              value: { value: String(row.id), span, },
            },
          ]
          for child in row.fields {
            let mut child_contract = None
            for index in 0..<@contract.field_count(fields) {
              let entry = @contract.field_at(fields, index).unwrap()
              if entry.name == child.metadata.code {
                child_contract = Some(entry.contract)
                break
              }
            }
            guard child_contract is Some(child_contract) else {
              return Err(InvalidValue(child.metadata.code))
            }
            let value = match
              record_value_node(child, child_contract, budget, depth + 2) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
            entries.push({
              key: child.metadata.code,
              key_span: @decode.cursor_key_span(child.value).unwrap_or(span),
              value,
            })
          }
          values.push({ value: Object(entries), span, })
        }
        @source.Array(values)
      }
      "CHECK_BOX"
      | "MULTI_SELECT"
      | "CATEGORY"
      | "USER_SELECT"
      | "ORGANIZATION_SELECT"
      | "GROUP_SELECT"
      | "STATUS_ASSIGNEE" => {
        let count = @decode.array_length(cursor).unwrap()
        if count > budget.nodes || (count > 0 && depth >= budget.depth) {
          return Err(BudgetExceeded)
        }
        let values : Array[@source.Node] = []
        for index in 0..<count {
          let item = @decode.element_at(cursor, index).unwrap()
          let value = match @decode.text(item) {
            Ok(value) => value
            Err(_) => {
              guard @decode.open_object(item) is Ok(object) &&
                form_text(object, "code") is Some(code) else {
                return Err(InvalidValue(code))
              }
              code
            }
          }
          guard @scalar.admit_utf8_length(value, budget.text_bytes) is Ok(bytes) else {
            return Err(BudgetExceeded)
          }
          budget.text_bytes -= bytes
          budget.nodes -= 1
          values.push({ value: String(value), span: @decode.cursor_span(item), })
        }
        @source.Array(values)
      }
      _ => {
        let text = if field.metadata.native_type == "CREATOR" ||
          field.metadata.native_type == "MODIFIER" {
          form_text(@decode.open_object(cursor).unwrap(), "code").unwrap()
        } else {
          @decode.text(cursor).unwrap()
        }
        if contract.shape is @contract.Decimal(precision~, scale~) {
          if text.is_empty() {
            return Ok({ value: Null, span, })
          }
          let text = match
            @admitted.normalize_decimal_text(
              text,
              precision,
              scale,
              budget.text_bytes.max(1),
            ) {
            Ok(value) => value
            Err(issue) => return Err(DecimalValue(code, issue))
          }
          guard @scalar.admit_utf8_length(text, budget.text_bytes) is Ok(bytes) else {
            return Err(BudgetExceeded)
          }
          budget.text_bytes -= bytes
          @source.String(text)
        } else if contract.shape is @contract.Timestamp {
          if text.is_empty() {
            return Ok({ value: Null, span, })
          }
          // REST returns UTC whole seconds. The Common Owner checks the
          // calendar; adding zero milliseconds preserves that exact instant.
          let text = if text.length() == 20 && text.has_suffix("Z") {
            text[:19].to_owned() + ".000Z"
          } else {
            text
          }
          if text.length() == 24 && text < "1000-01-01T00:00:00.000Z" {
            return Err(InvalidValue(code))
          }
          guard @scalar.admit_utf8_length(text, budget.text_bytes) is Ok(bytes) else {
            return Err(BudgetExceeded)
          }
          budget.text_bytes -= bytes
          @source.String(text)
        } else {
          if contract.shape is @contract.Date &&
            text.length() == 10 &&
            text < "1000-01-01" {
            return Err(InvalidValue(code))
          }
          guard @scalar.admit_utf8_length(text, budget.text_bytes) is Ok(bytes) else {
            return Err(BudgetExceeded)
          }
          budget.text_bytes -= bytes
          @source.String(text)
        }
      }
    }
  }
  Ok({ value: source, span, })
}

///|
pub fn project_checked_record_page(
  page : OriginalRecordPage,
  settings : AppNumberSettings?,
  limits : RecordValueLimits,
) -> Result[CheckedRecordPage, RecordValueIssue] {
  let contracts = match
    record_contracts(page.catalog, settings, page.names, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let columns = ["$id"]
  for name in page.names {
    columns.push(name)
  }
  let budget : RecordValueBudget = {
    nodes: limits.max_nodes,
    text_bytes: limits.max_text_bytes,
    depth: limits.max_depth,
  }
  let rows = []
  for original in page.records {
    if budget.nodes <= 0 || original.record_id.length() > budget.text_bytes {
      return Err(BudgetExceeded)
    }
    budget.nodes -= 1
    budget.text_bytes -= original.record_id.length()
    let values = [
      @admitted.checked_text_value(original.record_id, contracts[0]).unwrap(),
    ]
    for index, field in original.fields {
      let construction : RecordValueBudget = {
        nodes: budget.nodes,
        text_bytes: budget.text_bytes,
        depth: budget.depth,
      }
      let node = match
        record_value_node(field, contracts[index + 1], construction, 1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let cursor = match
        @decode.admit(node, {
          max_nodes: budget.nodes,
          max_depth: budget.depth,
          max_string_bytes: budget.text_bytes,
          max_total_string_bytes: budget.text_bytes,
        }) {
        Ok(value) => value
        Err(_) => return Err(BudgetExceeded)
      }
      let (checked, nodes, text) = match
        @admitted.admit_usage(contracts[index + 1], cursor, {
          max_nodes: budget.nodes,
          max_depth: budget.depth,
          max_text_bytes: budget.text_bytes,
        }) {
        Ok(value) => value
        Err(@admitted.ValueIssue(@admitted.BudgetExceeded, ..)) =>
          return Err(BudgetExceeded)
        Err(issue) => return Err(ValueAdmission(field.metadata.code, issue))
      }
      budget.nodes -= nodes
      budget.text_bytes -= text
      values.push(checked)
    }
    rows.push(values)
  }
  Ok({ original: page, settings, columns, rows, })
}

///|
pub fn checked_record_columns(page : CheckedRecordPage) -> Array[String] {
  page.columns.copy()
}

///|
pub fn checked_record_rows(
  page : CheckedRecordPage,
) -> Array[Array[@admitted.CheckedValue]] {
  page.rows.map(row => row.copy())
}

///|
pub fn checked_record_original(page : CheckedRecordPage) -> OriginalRecordPage {
  page.original
}

///|
pub fn checked_record_settings(page : CheckedRecordPage) -> AppNumberSettings? {
  page.settings
}

///|
/// Common's canonical field-map DATA, available before record I/O. The existing
/// RowDeclaration/RowRun still admits it and owns actual acquisition/current.
pub fn record_schema_wire(
  catalog : FormFieldCatalog,
  settings : AppNumberSettings?,
  names : Array[String],
  limits : RecordValueLimits,
  max_output_bytes : Int,
) -> Result[String, RecordValueIssue] {
  if max_output_bytes <= 0 {
    return Err(InvalidLimits)
  }
  let contracts = match record_contracts(catalog, settings, names, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let entries = [("$id", contracts[0])]
  for index, name in names {
    entries.push((name, contracts[index + 1]))
  }
  let object = match
    @contract.object_contract(
      entries,
      nullable=false,
      max_fields=limits.max_columns,
      max_name_bytes=limits.max_name_bytes,
    ) {
    Ok(value) => value
    Err(@contract.ConstructionLimit) => return Err(BudgetExceeded)
    Err(_) => return Err(UnrepresentableField("schema"))
  }
  guard object.shape is @contract.Object(fields) else {
    return Err(UnrepresentableField("schema"))
  }
  let writer = @encode.writer(
    max_output_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_ordered_object(writer)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      @encode.ordered_key(writer, field.name)
      @contract.emit_checked(field.contract, writer)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
    _ => {
      @encode.cancel_writer(writer)
      Err(UnrepresentableField("schema"))
    }
  }
}
