///|
/// Admit the original native page under the acquisition's exact Common
/// contracts. Equivalent independently created CheckedValues are not reused:
/// every returned cell is admitted with the supplied original contract.
/// Columns may omit the mandatory physical locator, but cannot omit any
/// selected native field or invent an alias. This pure port grants no I/O.
pub fn admit_record_page_contracts(
  page : OriginalRecordPage,
  settings : AppNumberSettings?,
  columns : Array[String],
  contracts : Array[@contract.Contract],
  limits : RecordValueLimits,
  max_contract_pairs : Int,
) -> Result[Array[Array[@admitted.CheckedValue]], RecordValueIssue] {
  if max_contract_pairs <= 0 || !record_value_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let expected = match
    record_contracts(page.catalog, settings, page.names, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if columns.length() != contracts.length() ||
    columns.length() > limits.max_columns ||
    columns.length() < page.names.length() ||
    columns.length() > page.names.length() + 1 {
    return Err(UnrepresentableField("schema"))
  }
  let indexes = []
  let seen : Map[String, Bool] = Map([])
  for index, column in columns {
    if seen.contains(column) {
      return Err(UnrepresentableField(column))
    }
    seen[column] = true
    let mut field_index = -1
    if column != "$id" {
      for selected_index, selected in page.names {
        if column == selected {
          field_index = selected_index
          break
        }
      }
      if field_index < 0 {
        return Err(UnrepresentableField(column))
      }
    }
    let same = @contract.type_equal(
      expected[field_index + 1],
      contracts[index],
      max_contract_pairs,
    ) catch {
      _ => return Err(BudgetExceeded)
    }
    if !same {
      return Err(InvalidValue(column))
    }
    indexes.push(field_index)
  }
  for name in page.names {
    if !seen.contains(name) {
      return Err(UnrepresentableField(name))
    }
  }
  let budget : RecordValueBudget = {
    nodes: limits.max_nodes,
    text_bytes: limits.max_text_bytes,
    depth: limits.max_depth,
  }
  let result = []
  for record in page.records {
    let row = []
    for index, field_index in indexes {
      if field_index < 0 {
        if budget.nodes <= 0 || record.record_id.length() > budget.text_bytes {
          return Err(BudgetExceeded)
        }
        budget.nodes -= 1
        budget.text_bytes -= record.record_id.length()
        guard @admitted.checked_text_value(record.record_id, contracts[index])
          is Some(value) else {
          return Err(InvalidValue("$id"))
        }
        row.push(value)
      } else {
        match
          record_checked_cell(
            record.fields[field_index],
            contracts[index],
            budget,
          ) {
          Ok(value) => row.push(value)
          Err(issue) => return Err(issue)
        }
      }
    }
    result.push(row)
  }
  Ok(result)
}
