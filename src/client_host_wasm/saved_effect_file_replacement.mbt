///|
// The dispatched row's private original supplies the target and canonical
// changes. The Host supplies the locked current bytes of the same file.
fn prepare_saved_effect_file_replacement(
  selected : StoredMockProjectWriteTarget,
  original : @host.ClientEffectSavedFileDispatch,
  data : Bytes,
  fund : (Int64) -> Bool,
) -> Result[Bytes, Int] {
  let resource = selected.write.mapping.resource
  let source = selected.source
  let page = @row_host.project_mock_row_page_limits()
  guard data.length() > 0 &&
    data.length() <= page.max_bytes &&
    selected.source.rows.iter().find_first(row => row.view.resource == resource)
    is Some(selection) &&
    original.replacement_material() is Some((identity, version, changes)) else {
    return Err(-31)
  }
  guard @execution.preparation_representation_cost(
      mock_effect_target_geometry_inventory(data.length()),
    )
    is Some(geometry) &&
    fund(geometry) else {
    return Err(-4)
  }
  guard mock_effect_target_mapping_limits(
      source,
      selection,
      data,
      mock_project_record_read_limits(source, selection, data.length(), page),
    )
    is Some((limits, raw_limits)) else {
    return Err(-31)
  }
  guard @row_host.relation_document_mapping_construction_inventory(limits).bind(
      @execution.preparation_representation_cost,
    )
    is Some(mapping) &&
    fund(mapping) else {
    return Err(-4)
  }
  guard @row_host.prepare_relation_document_contract(
      source.relation,
      resource,
      selection.primary_identity,
      limits,
    )
    is Ok(contract) else {
    return Err(-31)
  }
  let typed = @row_host.relation_document_prepared_contract(contract)
  let fields = selected.write.writable_fields
  let projection_limits = match
    @row_host.relation_document_text_contract_nodes(typed) {
    Some(schema_nodes) =>
      { ..raw_limits, max_nodes: Int::max(raw_limits.max_nodes, schema_nodes), }
    None => limits
  }
  guard @row_host.relation_document_raw_construction_inventory(raw_limits).bind(
      @execution.preparation_representation_cost,
    )
    is Some(raw) &&
    @row_host.relation_document_projection_construction_inventory(
      {
        original: typed,
        items_path_depth: selection.items_path.length(),
        key_path_depth: Some(selection.key_path.length()),
        writable_fields: fields.length(),
      },
      projection_limits,
    ).bind(@execution.preparation_representation_cost)
    is Some(projected) &&
    @row_host.relation_target_write_wire_construction(
      typed,
      limits,
      data.length(),
      changes.length(),
      deleting=false,
    )
    is Some(layout) &&
    @execution.preparation_representation_cost(layout.placement)
    is Some(mutation) &&
    @encode.text_writer_construction_inventory(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(writer) &&
    @encode.hash_writer_construction_inventory(
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + hash.record_headers + 20L,
      reference_slots: writer.reference_slots + hash.reference_slots + 31L,
      scalar_words: writer.scalar_words + hash.scalar_words + 17L,
      owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units + 71L,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(observe) &&
    fund(mapping + raw + projected + observe + mutation) else {
    return Err(-4)
  }
  let max_work = 16777216
  guard @row_host.admit_relation_document(data, limits, max_work)
    is Ok(document) &&
    @row_host.project_relation_target_document(
      document,
      source.relation,
      resource,
      selection.items_path,
      Some(selection.key_path),
      selection.primary_identity,
      fields,
      prepared_contract=Some(contract),
    )
    is Ok(target) else {
    return Err(-31)
  }
  defer @row_host.discard_relation_target_document_original(target) |> ignore
  guard @row_host.observe_relation_target(target, source.relation, identity)
    is Ok(row) &&
    @row_host.relation_target_version(row) == Some(version) else {
    return Err(-32)
  }
  @row_host.prepare_relation_target_update(
    target, row, version, changes, max_work,
  ).map_err(_ => -31)
}
