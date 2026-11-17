///|
/// The SAME installed RowSource emits typed JSON row arrays. The descriptor
/// binds that identity response codec to its original checked declaration;
/// it creates no Request, reference, read permission or completion receipt.
pub fn bind_installed_row_read_profile(
  declaration : RowDeclaration,
  source_ref : String,
) -> Result[RowDeclaration, RowMappingIssue] {
  guard row_declaration_file_read_profile(declaration, source_ref) is None &&
    row_declaration_view(declaration, source_ref) is Some(view) &&
    row_declaration_keyed_read_schema_identities(declaration, source_ref)
    is Some((request, response)) &&
    declaration.views.search_by(item => physical_equal(item, view))
    is Some(index) &&
    declaration.view_bodies.get(index) is Some(wire) else {
    return Err(InvalidSpecification)
  }
  let body = try {
    let writer = @encode.writer(2048, 32, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("source_view_contract_cid", view.view_cid),
        ("request_schema_cid", request),
        ("response_schema_cid", response),
        ("response_encoding", "typed_json_row_array"),
        ("version", "actql-installed-row-source-read/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(OutputLimit)
  }
  let contract = match
    @publication.seal_publication_contract(
      "installed_row_source_read", body, 2048, 32, 2,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let profile = InstalledRowRead(source_ref, view, wire, contract)
  Ok({
    ..declaration,
    file_read_profiles: Some(
      match declaration.file_read_profiles {
        None => [profile]
        Some(profiles) => [..profiles, profile]
      },
    ),
  })
}

///|
/// Before-construction quote for the fixed descriptor and the SAME declaration
/// export/JS metadata view. Bound by actual retained metadata, never file bytes,
/// rows or a codec policy maximum. The installing Source material funds it.
pub fn installed_row_read_profile_construction_inventory(
  declaration : RowDeclaration,
) -> @execution.PreparationRepresentationUnits? {
  let mut units = 0L
  for wires in [declaration.contracts, declaration.view_bodies] {
    for wire in wires {
      guard @execution.checked_preparation_add_product(
          units,
          wire.length().to_int64(),
          1L,
        )
        is Some(next) else {
        return None
      }
      units = next
    }
  }
  guard units < 44739242L &&
    relation_construction_decoded_construction(2048, 32, 2, false)
    is Some(parsed) &&
    relation_construction_writer_units(2048, 32, 2) is Some(writer) &&
    @encode.hash_writer_construction_inventory(32, 2) is Some(hash) &&
    relation_construction_json_forest(128L) is Some(tree) &&
    relation_construction_decoded_construction(
      (12L * units + 4096L).to_int(),
      (8L * units + 128L).to_int(),
      (units + 32L).to_int(),
      false,
    )
    is Some(exported) &&
    @shape.collection_construction_extent({
      // Enum H1/R4/W1, declaration H1/R11, Some H1/R1/W1, quote/
      // result/projection frontiers and the old/new profile backing coexist.
      records: 12L,
      record_references: 40L,
      record_words: 12L,
      reference_arrays: 4L,
      reference_items: 32L +
      declaration.file_read_profiles
      .map(values => 2L * values.length().to_int64())
      .unwrap_or(0L),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.compose_preparation_representation([
    parsed,
    writer,
    exported,
    {
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    },
    relation_construction_collection_units(tree),
    relation_construction_collection_units(controls),
  ])
}
