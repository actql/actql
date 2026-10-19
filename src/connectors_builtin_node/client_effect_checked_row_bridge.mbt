///|
// Private same-runtime DATA projections. Captured/Mapping keeps the original
// typed values; selecting a vendor property here is not a target or write permit.
struct ClientEffectNotionPropertyWrite {
  row : @strategy.CapturedEffectCheckedProposalRow
  source : @notion_catalog.NotionDataSourceCatalog
  field_index : Int
  property_index : Int
  value : @admitted.CheckedValue
  end_field : (Int, @admitted.CheckedValue)?
  write : @notion_catalog.NotionPropertyWrite
}

///|
pub(all) enum ClientEffectNotionPropertyIssue {
  NotReady
  ForeignOriginal
  InvalidField
  BudgetExceeded
  Codec(@notion_catalog.NotionPropertyWriteIssue)
} derive(Debug)

///|
#export_name("clientProgramEffectInputExportNextOriginalRow")
pub fn client_program_effect_input_export_next_original_row(
  stream : @execution.CompletedOutputExport,
  max_nodes : Int,
  max_depth : Int,
  max_utf16_units : Int,
) -> Result[
  (Int, String, @execution.CompletedOutputExportOriginalRow)?,
  @execution.CompletedExportIssue,
] {
  @execution.next_completed_output_export_original_row(
    stream, max_nodes, max_depth, max_utf16_units,
  ).map(row => {
    row.map(pair => {
      (
        @execution.completed_output_export_original_row_index(pair.1),
        pair.0,
        pair.1,
      )
    })
  })
}

///|
#export_name("clientProgramEffectOriginalRowRetire")
pub fn client_program_effect_original_row_retire(
  row : @execution.CompletedOutputExportOriginalRow,
) -> Unit {
  @execution.retire_completed_output_export_original_row(row)
}

///|
#export_name("clientProgramEffectOriginalRowAvailable")
pub fn client_program_effect_original_row_available(
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  row : @execution.CompletedOutputExportOriginalRow,
) -> Bool {
  @strategy.captured_effect_local_result_original_row_available(
    inputs, exported, row,
  )
}

///|
#export_name("clientProgramEffectCheckedProposalRow")
pub fn client_program_effect_checked_proposal_row(
  plan : @strategy.CapturedEffectProposalPlan,
  exported : @strategy.CapturedEffectLocalResultExport,
  original : @execution.CompletedOutputExportOriginalRow,
  max_fields : Int,
  max_work : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_bytes : Int,
) -> Result[
  @strategy.CapturedEffectCheckedProposalRow,
  @strategy.CapturedEffectCheckedProposalIssue,
] {
  @strategy.project_captured_effect_checked_proposal_row(
    plan,
    exported,
    original,
    max_fields,
    max_work,
    { max_nodes, max_depth, max_text_bytes, },
  )
}

///|
#export_name("clientProgramEffectCheckedProposalRowAvailable")
pub fn client_program_effect_checked_proposal_row_available(
  row : @strategy.CapturedEffectCheckedProposalRow,
) -> Bool {
  @strategy.captured_effect_checked_proposal_row_available(row)
}

///|
#export_name("clientProgramEffectCheckedProposalRowRetire")
pub fn client_program_effect_checked_proposal_row_retire(
  row : @strategy.CapturedEffectCheckedProposalRow,
) -> Unit {
  @strategy.retire_captured_effect_checked_proposal_row(row)
}

///|
// These two admissions are ordinary response DATA. They do not reconstruct a
// prior live observation, issue its completeness, or establish current custody.
#export_name("clientProgramNotionProjectDatabase")
pub fn client_program_notion_project_database(
  bytes : Bytes,
  limits : @notion_catalog.NotionDatabaseLimits,
) -> Result[
  @notion_catalog.NotionDatabaseCatalog,
  @notion_catalog.NotionDatabaseIssue,
] {
  @notion_catalog.project_notion_database(bytes, limits)
}

///|
#export_name("clientProgramNotionProjectDataSource")
pub fn client_program_notion_project_data_source(
  database : @notion_catalog.NotionDatabaseCatalog,
  index : Int,
  bytes : Bytes,
  limits : @notion_catalog.NotionDatabaseLimits,
) -> Result[
  @notion_catalog.NotionDataSourceCatalog,
  @notion_catalog.NotionDatabaseIssue,
] {
  @notion_catalog.project_notion_data_source(database, index, bytes, limits)
}

///|
#export_name("clientProgramNotionDatabaseLimits")
pub fn client_program_notion_database_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_data_sources : Int,
  max_properties : Int,
  max_identity_bytes : Int,
  max_name_bytes : Int,
) -> @notion_catalog.NotionDatabaseLimits {
  {
    max_bytes,
    max_nodes,
    max_depth,
    max_data_sources,
    max_properties,
    max_identity_bytes,
    max_name_bytes,
  }
}

///|
#export_name("clientProgramNotionPropertyWriteLimits")
pub fn client_program_notion_property_write_limits(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_properties : Int,
  max_items : Int,
  max_text_units : Int,
  max_work : Int,
) -> @notion_catalog.NotionPropertyWriteLimits {
  {
    max_bytes,
    max_nodes,
    max_depth,
    max_properties,
    max_items,
    max_text_units,
    max_work,
  }
}

///|
#export_name("clientProgramEffectNotionPropertyWrite")
pub fn client_program_effect_notion_property_write(
  row : @strategy.CapturedEffectCheckedProposalRow,
  field_index : Int,
  source : @notion_catalog.NotionDataSourceCatalog,
  property_index : Int,
  limits : @notion_catalog.NotionPropertyWriteLimits,
) -> Result[ClientEffectNotionPropertyWrite, ClientEffectNotionPropertyIssue] {
  guard @strategy.captured_effect_checked_proposal_row_field_at(
      row, field_index,
    )
    is Some((_, value)) else {
    return Err(InvalidField)
  }
  let write = match
    @notion_catalog.prepare_notion_property_write(
      source, property_index, value, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Codec(issue))
  }
  if !@strategy.captured_effect_checked_proposal_row_available(row) {
    return Err(NotReady)
  }
  Ok({
    row,
    source,
    field_index,
    property_index,
    value,
    end_field: None,
    write,
  })
}

///|
#export_name("clientProgramEffectNotionDateRangeWrite")
pub fn client_program_effect_notion_date_range_write(
  row : @strategy.CapturedEffectCheckedProposalRow,
  start_field : Int,
  end_field : Int,
  source : @notion_catalog.NotionDataSourceCatalog,
  property_index : Int,
  limits : @notion_catalog.NotionPropertyWriteLimits,
) -> Result[ClientEffectNotionPropertyWrite, ClientEffectNotionPropertyIssue] {
  guard @strategy.captured_effect_checked_proposal_row_field_at(
      row, start_field,
    )
    is Some((_, start)) &&
    @strategy.captured_effect_checked_proposal_row_field_at(row, end_field)
    is Some((_, end)) else {
    return Err(InvalidField)
  }
  let write = match
    @notion_catalog.prepare_notion_date_range_property_write(
      source, property_index, start, end, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Codec(issue))
  }
  if !@strategy.captured_effect_checked_proposal_row_available(row) {
    return Err(NotReady)
  }
  Ok({
    row,
    source,
    field_index: start_field,
    property_index,
    value: start,
    end_field: Some((end_field, end)),
    write,
  })
}

///|
fn client_effect_notion_property_write_current(
  write : ClientEffectNotionPropertyWrite,
  row : @strategy.CapturedEffectCheckedProposalRow,
  source : @notion_catalog.NotionDataSourceCatalog,
) -> Bool {
  if !physical_equal(write.row, row) || !physical_equal(write.source, source) {
    return false
  }
  guard @strategy.captured_effect_checked_proposal_row_field_at(
      row,
      write.field_index,
    )
    is Some((_, original)) &&
    physical_equal(original, write.value) else {
    return false
  }
  match write.end_field {
    None =>
      @notion_catalog.notion_property_write_matches(
        write.write,
        source,
        write.property_index,
        original,
      )
    Some((index, end)) => {
      guard @strategy.captured_effect_checked_proposal_row_field_at(row, index)
        is Some((_, original_end)) &&
        physical_equal(original_end, end) else {
        return false
      }
      @notion_catalog.notion_date_range_property_write_matches(
        write.write,
        source,
        write.property_index,
        original,
        original_end,
      )
    }
  }
}

///|
#export_name("clientProgramEffectNotionWritesJson")
pub fn client_program_effect_notion_writes_json(
  row : @strategy.CapturedEffectCheckedProposalRow,
  source : @notion_catalog.NotionDataSourceCatalog,
  writes : Array[ClientEffectNotionPropertyWrite],
  limits : @notion_catalog.NotionPropertyWriteLimits,
) -> Result[String, ClientEffectNotionPropertyIssue] {
  if !@strategy.captured_effect_checked_proposal_row_available(row) {
    return Err(NotReady)
  }
  if limits.max_properties < 0 ||
    limits.max_work < 0 ||
    writes.length() > limits.max_properties ||
    writes.length() > limits.max_work {
    return Err(BudgetExceeded)
  }
  for write in writes {
    if !client_effect_notion_property_write_current(write, row, source) {
      return Err(ForeignOriginal)
    }
  }
  let wire = match
    @notion_catalog.notion_page_properties_write_wire(
      source,
      writes.map(write => write.write),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Codec(issue))
  }
  if !@strategy.captured_effect_checked_proposal_row_available(row) {
    return Err(NotReady)
  }
  Ok(wire)
}
