///|
fn sf_read_collection_units(
  original : @shape.CollectionConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: original.record_headers,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
// ONE real normalizing Describe parser/index. Provider projection returns
// before Common recovery begins; those complete parser workspaces are not
// simultaneous. Their shared Source/decoder owners retain every refusal path.
fn sf_read_describe_parse_inventory(
  limits : @catalog.DescribeLimits,
  source_nodes? : Int? = None,
) -> @execution.PreparationRepresentationUnits? {
  let nodes = Int::min(
    Int::min(limits.max_bytes, limits.max_nodes),
    source_nodes.unwrap_or(limits.max_nodes),
  )
  if nodes < 1 {
    return None
  }
  guard @source.json_construction_extent(
      limits.max_bytes,
      nodes,
      limits.max_depth,
      normalize_keys=true,
    )
    is Some(parsed) &&
    @decode.admission_construction_inventory(
      nodes,
      nodes,
      nodes,
      nodes,
      Int::min(nodes, limits.max_depth),
    )
    is Some(index) else {
    return None
  }
  @execution.compose_preparation_representation([
    {
      record_headers: parsed.record_headers,
      reference_slots: parsed.reference_slots,
      scalar_words: parsed.scalar_words,
      // parse_json_bytes owns its decoded input String independently of
      // the Source parser's tree and normalized-key/output text.
      owned_utf16_units: parsed.owned_utf16_units + limits.max_bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    {
      record_headers: index.indexed.record_headers +
      index.keys.record_headers +
      index.ancestry.record_headers +
      index.controls.record_headers,
      reference_slots: index.indexed.reference_slots +
      index.keys.reference_slots +
      index.ancestry.reference_slots +
      index.controls.reference_slots,
      scalar_words: index.indexed.scalar_words +
      index.keys.scalar_words +
      index.ancestry.scalar_words +
      index.controls.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
// Exact named-Describe protocol: one Resource, one original response and an
// incomplete Catalog observation. No listing/static declaration is generated.
// The live caller drops the first full observation after extracting its plan,
// before the independent recheck; selected metadata remains in that plan.
// The SAME three original metadata families are used by named Describe and
// by historical whole-Catalog restoration. Aggregate callers supply total
// fields/references, not one full byte budget for every selected Resource.
fn sf_read_metadata_construction_inventory(
  fields : Int64,
  references : Int64,
) -> @shape.CollectionConstructionExtent? {
  @shape.collection_construction_extent({
    records: 3L * (2L + 5L * fields),
    record_references: 3L * (4L + 8L * fields),
    record_words: 3L * (5L + 17L * fields),
    reference_arrays: 3L * (1L + fields),
    reference_items: 3L * (fields + references),
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: fields,
  })
}

///|
fn sf_read_observation_construction_inventory(
  limits : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  source_nodes? : Int? = None,
) -> @execution.PreparationExecutionInventory? {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_fields < 1 ||
    limits.max_name_units < 1 ||
    max_observation_bytes < 1 ||
    binding_units < 0 ||
    resource_units < 1 {
    return None
  }
  let bytes = limits.max_bytes.to_int64()
  let nodes = Int::min(limits.max_bytes, limits.max_nodes).to_int64()
  // A completed field includes at least {"name":"a","type":"x"}; one
  // current failed field can allocate before that complete-prefix proof.
  let fields = Int::min(limits.max_fields, limits.max_bytes / 23 + 1).to_int64()
  // Every retained referenceTo item spent a distinct original JSON node.
  // Copies borrow each String, never F independently full max_fields lists.
  guard @execution.checked_preparation_add_product(
      0L,
      fields,
      limits.max_fields.to_int64(),
    )
    is Some(reference_bound) else {
    return None
  }
  let references = Int64::min(nodes, reference_bound)
  // FieldMetadata is 1H/7R/10W, plus its four possible Some carriers
  // 4H/1R/7W. Its reference_to array is expanded by the collection owner.
  // ResourceMetadata is 1H/4R/3W plus optional deletable 1H/0R/2W.
  // Three simultaneous families bound original sync, observation copy and
  // resource/projection copy, including a failed prefix and recheck overlap.
  guard sf_read_metadata_construction_inventory(fields, references)
    is Some(metadata) else {
    return None
  }
  // Binding(13), SiteCatalog(1), CatalogSync(5), Listing(4), selected entry(4),
  // two Described alternatives(1 each), CatalogObservation(6), result/evidence
  // (7+9), JS recovered binding/entry/root objects(13+4+6), and ten original
  // vector/Option/tuple carriers coexist with the current metadata family.
  guard @shape.collection_construction_extent({
      records: 24L,
      record_references: 96L,
      record_words: 32L,
      reference_arrays: 10L,
      reference_items: 16L,
      scalar_arrays: 1L,
      scalar_items: 1L,
      maps: 2L,
      map_entries: 2L,
    })
    is Some(carriers) else {
    return None
  }
  // Fixed keys/version, use CID, digest/null and decimal generation spelling
  // fit within 1024 units. All other emitted Strings are these original
  // binding/name quantities, with the existing JSON writer's <=6 escaping.
  let observation = Int64::min(
    max_observation_bytes.to_int64(),
    1024L + 6L * (binding_units.to_int64() + resource_units.to_int64()),
  ).to_int()
  guard @encode.text_writer_construction_inventory(observation, 25, 4)
    is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(digest) &&
    sf_read_describe_parse_inventory(limits, source_nodes~) is Some(parse) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  // project_field's bounded scalar/lookup/result family is sequential per
  // field. Co-count 32 original indexed-child constructors, current reference
  // list growth, typed failure/span/path and per-resource sorting controls.
  guard @shape.collection_construction_extent({
      records: 64L + 32L * child.record_headers,
      record_references: 96L + 32L * child.reference_slots,
      record_words: 96L + 32L * child.scalar_words,
      reference_arrays: 8L,
      reference_items: nodes + 2L * fields + 16L,
      scalar_arrays: 1L,
      scalar_items: limits.max_depth.to_int64() + 1L,
      maps: 1L,
      map_entries: fields,
    })
    is Some(projection) &&
    @execution.compose_preparation_representation([
      sf_read_collection_units(metadata),
      sf_read_collection_units(carriers),
      {
        // Two independently decoded metadata String families can overlap:
        // the selected prior plan and the current observation. Copies within
        // either family borrow those Strings. The fixed 64 headers cover
        // observation JSON keys/values, base64/body/digest and binding carriers.
        record_headers: 64L + 2L * (3L * fields + references),
        reference_slots: 0L,
        scalar_words: 0L,
        // Metadata String payload is retained once within each family. The
        // two observation bodies, parsed binding and original base64 evidence
        // remain distinct. Reader raw-response backing is composed separately.
        owned_utf16_units: 2L * bytes +
        3L * observation.to_int64() +
        4L * ((bytes + 2L) / 3L) +
        // Prior/current observation CIDs, resource/response digests and the
        // new run/dispatch/occurrence Strings fit eight original CID slots.
        8L * 71L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.compose_preparation_representation([
      parse,
      sf_read_collection_units(projection),
      {
        record_headers: writer.record_headers + 3L * digest.record_headers,
        reference_slots: writer.reference_slots + 3L * digest.reference_slots,
        scalar_words: writer.scalar_words + 3L * digest.scalar_words,
        owned_utf16_units: writer.owned_utf16_units +
        3L * digest.owned_utf16_units +
        4L * 71L,
        // Common recovery decodes the same base64 evidence to original Bytes;
        // observation hashing owns its UTF8 buffer independently of that body.
        owned_wire_bytes: bytes +
        observation.to_int64() +
        3L * digest.owned_wire_bytes,
      },
    ])
    is Some(workspace) else {
    return None
  }
  Some({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// Inventory-only upper member of this connector's closed scalar domain.
// The current 0.1 Decimal owner admits P<=38; the endpoint is checked in the
// independent vectors. This immutable builtin is NOT a Program/Parameter
// contract, admission, value issuer or replacement for any original query
// column Contract. Only its existing constructor inventory is consumed here.
let sf_read_value_inventory_contract : @contract.Contract = @contract.decimal_contract(
  38,
  0,
  nullable=false,
).unwrap()

///|
fn sf_read_query_construction_inventory(
  limits : @catalog.QueryPageLimits,
  columns : Int,
  pages : Int,
  api_units : Int,
  soql_units : Int,
  source_nodes? : Int? = None,
  value_nodes? : Int? = None,
) -> @execution.PreparationExecutionInventory? {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_rows < 1 ||
    limits.max_locator_units < 1 ||
    columns < 1 ||
    pages < 1 ||
    api_units < 1 ||
    soql_units < 1 ||
    limits.max_nodes == 2147483647 {
    return None
  }
  let parser_nodes = Int::max(
    1,
    Int::min(limits.max_nodes, source_nodes.unwrap_or(limits.max_nodes)),
  )
  let limits = {
    ..limits,
    max_nodes: Int::max(
      1,
      Int::min(limits.max_nodes, value_nodes.unwrap_or(limits.max_nodes)),
    ),
  }
  let n = limits.max_nodes.to_int64()
  let width = columns.to_int64()
  let rows = limits.max_rows.to_int64()
  let (component_fields, names) = @catalog.address_component_role_bounds()
  let decimal_text_units = match sf_read_value_inventory_contract.shape {
    @contract.Decimal(precision~, ..) => precision + 3
    _ => return None
  }
  // Treat the admitted row/cell forest as one virtual Object root. Its N
  // field edges dominate Array edge storage without constructing that root.
  // A real compound has >=2 scalar children, so <=N/3 compound Objects exist.
  // Empty Arrays may consume the other nodes. In the same Value owner's affine
  // families, extrema are all scalar leaves, maximal compounds+scalar leaves,
  // and maximal compounds+empty Arrays. Take their coordinate maxima, not the
  // sum of three separately full Value phases or two copies of the node bound.
  let geometry : @decode.SubtreeConstructionGeometry = {
    nodes: limits.max_nodes + 1,
    arrays: 0,
    array_items: 0,
    objects: 1,
    fields: limits.max_nodes,
    texts: limits.max_nodes,
    max_object_fields: limits.max_nodes,
    max_key_utf16: names,
    max_text_utf16: Int::max(limits.max_bytes, decimal_text_units),
    total_utf16: limits.max_bytes.to_int64() +
    n * (names.to_int64() + decimal_text_units.to_int64()),
    work: 0L,
  }
  let object_bound = limits.max_nodes / 3
  let phases = []
  for
    g in [
      geometry,
      {
        ..geometry,
        objects: object_bound + 1,
        texts: limits.max_nodes - object_bound,
      },
      {
        ..geometry,
        objects: object_bound + 1,
        arrays: limits.max_nodes - object_bound,
        texts: 0,
      },
    ] {
    guard @admitted.contract_value_phase_construction_inventory(
        sf_read_value_inventory_contract,
        g,
        limits.max_depth.to_int64(),
        limits.max_depth,
      )
      is Some(phase) else {
      return None
    }
    phases.push(phase)
  }
  let values = phases[0]
  let mut rh = values.returned.record_headers
  let mut rr = values.returned.reference_slots
  let mut rw = values.returned.scalar_words
  let mut returned_text = values.returned_utf16_units
  for phase in phases {
    rh = Int64::max(rh, phase.returned.record_headers)
    rr = Int64::max(rr, phase.returned.reference_slots)
    rw = Int64::max(rw, phase.returned.scalar_words)
    returned_text = Int64::max(returned_text, phase.returned_utf16_units)
  }
  let returned : @shape.CollectionConstructionExtent = {
    record_headers: rh,
    reference_slots: rr,
    scalar_words: rw,
  }
  // All returned cells coexist, but admit_query_cell runs serially. Its
  // converted input is one scalar, one multipicklist Array of Strings, or one
  // compound Object containing <=the original role-table scalar children.
  // Do not retain a page-sized Object traversal for every constructed cell.
  let current_geometries : Array[@decode.SubtreeConstructionGeometry] = [
    {
      nodes: 1,
      arrays: 0,
      array_items: 0,
      objects: 0,
      fields: 0,
      texts: 1,
      max_object_fields: 0,
      max_key_utf16: 0,
      max_text_utf16: Int::max(limits.max_bytes, decimal_text_units),
      total_utf16: Int::max(limits.max_bytes, decimal_text_units).to_int64(),
      work: 0L,
    },
    {
      nodes: limits.max_nodes,
      arrays: 1,
      array_items: limits.max_nodes - 1,
      objects: 0,
      fields: 0,
      texts: limits.max_nodes - 1,
      max_object_fields: 0,
      max_key_utf16: 0,
      max_text_utf16: limits.max_bytes,
      total_utf16: limits.max_bytes.to_int64(),
      work: 0L,
    },
    {
      nodes: component_fields + 1,
      arrays: 0,
      array_items: 0,
      objects: 1,
      fields: component_fields,
      texts: component_fields,
      max_object_fields: component_fields,
      max_key_utf16: names,
      max_text_utf16: Int::max(limits.max_bytes, decimal_text_units),
      total_utf16: limits.max_bytes.to_int64() +
      component_fields.to_int64() * (names + decimal_text_units).to_int64(),
      work: 0L,
    },
  ]
  let mut th = 0L
  let mut tr = 0L
  let mut tw = 0L
  let mut temporary_text = 0L
  for index, current in current_geometries {
    let original = if index == 1 {
      // The original multipicklist conversion admits String items, never
      // Decimal coefficients. Its real Array traversal may reach max_nodes.
      @contract.array_contract(
        @contract.primitive(@contract.StringType, nullable=false),
        nullable=false,
      ).unwrap()
    } else {
      sf_read_value_inventory_contract
    }
    guard @admitted.contract_value_phase_construction_inventory(
        original,
        current,
        limits.max_depth.to_int64(),
        Int::min(2, limits.max_depth),
      )
      is Some(phase) else {
      return None
    }
    th = Int64::max(th, phase.temporary.record_headers)
    tr = Int64::max(tr, phase.temporary.reference_slots)
    tw = Int64::max(tw, phase.temporary.scalar_words)
    temporary_text = Int64::max(temporary_text, phase.temporary_utf16_units)
  }
  let temporary : @shape.CollectionConstructionExtent = {
    record_headers: th,
    reference_slots: tr,
    scalar_words: tw,
  }
  guard @decode.preserving_json_admission_construction_inventory(
      limits.max_bytes,
      parser_nodes,
      limits.max_depth,
    )
    is Some(parsed) &&
    @decode.admission_construction_inventory(
      limits.max_nodes,
      Int::min(component_fields, limits.max_nodes),
      1,
      1,
      Int::min(2, limits.max_depth),
    )
    is Some(converted_index) &&
    @contract.object_construction_inventory(component_fields, names)
    is Some(object) &&
    @shape.scale_collection_construction_extent(object.retained, width)
    is Some(objects) else {
    return None
  }
  // QueryPage's checked roots/cells and names arrays, the native pending page,
  // rows/columns returned by query_page_values, and shared typed-consumption
  // argument/charge carriers. All page rows exist before total-row refusal;
  // never replace max_rows by the smaller successful capture row bound.
  guard @execution.checked_preparation_add_product(0L, rows, width)
    is Some(cells) &&
    @execution.checked_preparation_add_product(
      4L * width + 2L * rows,
      cells,
      3L,
    )
    is Some(cell_slots) &&
    @shape.collection_construction_extent({
      records: 4L * n + 4L * rows + 24L,
      record_references: 8L * n + 4L * rows + 48L,
      record_words: 4L * n + 4L * rows + 32L,
      reference_arrays: 3L * rows + 8L,
      reference_items: cell_slots,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(converted) &&
    @shape.collection_construction_extent({
      // ReadProjection(12), QueryRead(10), both native page limits(5+8),
      // plan/contract/component/name arrays, query-result/page evidence and
      // original protocol/current/transport/consume callbacks. Each selected
      // compound has <=10 original components; their FieldMetadata is borrowed.
      records: 40L + 12L * width + 3L * pages.to_int64(),
      record_references: 128L + 28L * width + 6L * pages.to_int64(),
      record_words: 64L + 4L * width + 4L * pages.to_int64(),
      reference_arrays: 12L + 4L * width,
      reference_items: 16L * width + 2L * pages.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L + width,
      map_entries: 12L * width,
    })
    is Some(plan) else {
    return None
  }
  let path_units = 64L + api_units.to_int64() + 3L * soql_units.to_int64()
  guard @shape.collection_construction_extent({
      // Per possible component: primitive Text/Decimal Contract and its
      // original Some plus the caller's (role,Contract) input tuple. The
      // object assembler's fields/sort/NFC remain with its original owner.
      records: 5L * component_fields.to_int64() * width,
      record_references: 9L * component_fields.to_int64() * width,
      record_words: 5L * component_fields.to_int64() * width,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(components) else {
    return None
  }
  guard @execution.compose_preparation_representation([
      sf_read_collection_units(plan),
      sf_read_collection_units(objects),
      sf_read_collection_units(components),
      sf_read_collection_units(returned),
      {
        record_headers: 4L + pages.to_int64(),
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: returned_text +
        path_units +
        pages.to_int64() * limits.max_locator_units.to_int64() +
        2L * pages.to_int64() * 71L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) else {
    return None
  }
  let normalization : @execution.PreparationRepresentationUnits = match
    values.normalization {
    Some(original) =>
      {
        record_headers: original.record_headers,
        reference_slots: original.reference_slots,
        scalar_words: original.scalar_words,
        owned_utf16_units: original.owned_utf16_units,
        owned_wire_bytes: 0L,
      }
    None =>
      {
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      }
  }
  guard @execution.compose_preparation_representation([
      {
        record_headers: parsed.record_headers,
        reference_slots: parsed.reference_slots,
        scalar_words: parsed.scalar_words,
        owned_utf16_units: parsed.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      // Scalar/multipicklist/compound conversions construct their own Source
      // nodes/fields/arrays while borrowing spans and original names. No new
      // byte parser runs for that tree; only this original indexed admission.
      sf_read_collection_units(converted),
      {
        record_headers: converted_index.indexed.record_headers +
        converted_index.keys.record_headers +
        converted_index.ancestry.record_headers +
        converted_index.controls.record_headers,
        reference_slots: converted_index.indexed.reference_slots +
        converted_index.keys.reference_slots +
        converted_index.ancestry.reference_slots +
        converted_index.controls.reference_slots,
        scalar_words: converted_index.indexed.scalar_words +
        converted_index.keys.scalar_words +
        converted_index.ancestry.scalar_words +
        converted_index.controls.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      sf_read_collection_units(temporary),
      sf_read_collection_units(object.scratch),
      normalization,
      {
        record_headers: 8L,
        reference_slots: 0L,
        scalar_words: 0L,
        // Current decimal lexeme/builder/output, multipicklist split and
        // converted canonical/date text coexist with the retained Value batch.
        // 128 units cover the closed Decimal/date spelling constructors.
        owned_utf16_units: temporary_text +
        object.scratch_utf16_units +
        4L * limits.max_bytes.to_int64() +
        2L * path_units +
        128L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(workspace) else {
    return None
  }
  Some({
    retained,
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Closed native Describe/recovery/query constructor envelope for the existing
/// installed Source. Original profile/limits supply these DATA bounds before
/// callbacks. No Source initialization, declaration/Environment regeneration,
/// permission, Ledger or replacement checked Contract is supplied here.
pub fn native_read_construction_capacity(
  describe : @catalog.DescribeLimits,
  query : @catalog.QueryPageLimits,
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  columns : Int,
  pages : Int,
  api_units : Int,
  soql_units : Int,
  query_geometry? : @source.JsonSourceGeometry? = None,
  describe_geometry? : @source.JsonSourceGeometry? = None,
  value_nodes? : Int? = None,
) -> @execution.ExecutionCapacity? {
  guard sf_read_observation_construction_inventory(
      describe,
      max_observation_bytes,
      binding_units,
      resource_units,
      // Only this parser/index workspace follows the same original body.
      // Retained prior/current metadata and failed prefixes keep the full
      // existing Describe limits; the reader's monotonic quote covers both.
      source_nodes=describe_geometry.map(geometry => geometry.node_upper),
    )
    is Some(metadata) &&
    sf_read_query_construction_inventory(
      query,
      columns,
      pages,
      api_units,
      soql_units,
      source_nodes=query_geometry.map(geometry => geometry.node_upper),
      value_nodes~,
    )
    is Some(query) &&
    @execution.compose_preparation_representation([
      metadata.retained,
      query.retained,
    ])
    is Some(retained) &&
    @execution.preparation_representation_cost(retained) is Some(r) &&
    @execution.preparation_representation_cost(metadata.workspace) is Some(m) &&
    @execution.preparation_representation_cost(query.workspace) is Some(q) &&
    // An original current QueryRead/body can exist only after both named
    // Describe consumers completed. Keep their retained families, not their
    // already-retired parser/index workspace beside every later query page.
    @execution.checked_preparation_add_product(
      r,
      if query_geometry is Some(_) {
        q
      } else {
        Int64::max(m, q)
      },
      1L,
    )
    is Some(e) else {
    return None
  }
  // Both returned prefixes coexist, but native provider metadata, Common
  // recovery and the query parser are awaited sequentially by one Reader.
  @execution.execution_capacity(r, e)
}

///|
/// The existing named Describe constructor, including its retained evidence,
/// normalizing parser, native metadata, binding projection and recovery peak.
/// An Effect metadata occurrence consumes these SAME Owner quantities; this
/// supplies neither HTTP/secret backing nor a Run, read decision or grant.
pub fn named_describe_construction_capacity(
  describe : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  source_geometry? : @source.JsonSourceGeometry? = None,
) -> @execution.ExecutionCapacity? {
  guard sf_read_observation_construction_inventory(
      describe,
      max_observation_bytes,
      binding_units,
      resource_units,
      source_nodes=source_geometry.map(geometry => geometry.node_upper),
    )
    is Some(inventory) else {
    return None
  }
  @execution.preparation_execution_capacity(inventory)
}

///|
/// Lexical geometry of this original received body only. Its caller funds the
/// decoded Source String and fixed preflight controls before entering here.
/// This neither validates Describe grammar nor supplies metadata/authority;
/// a refused preflight leaves the original consumer's full envelope intact.
pub fn named_describe_response_geometry(
  body : Bytes,
  limits : @catalog.DescribeLimits,
) -> @source.JsonSourceGeometry? {
  if body.length() > limits.max_bytes {
    return None
  }
  let text = @utf8.decode(body[:], ignore_bom=false) catch { _ => return None }
  let preflight = match
    @source.start_json_source_preflight(text, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  defer @source.cancel_json_source_preflight(preflight)
  for tick = 0 {
    match @source.advance_json_source_preflight(preflight, 4096) {
      Ok(JsonSourceContinue(..)) => continue tick + 1
      Ok(JsonSourceReady(geometry, ..)) => break Some(geometry)
      _ => break None
    }
  }
}

///|
// Pre-entry backing for that exact Source decode and lexical scan. The later
// Describe parser reuses this workspace sequentially; no grammar tree or
// metadata family is allocated by this fixed-control prelude.
fn sf_read_describe_preflight_capacity(
  max_bytes : Int,
) -> @execution.ExecutionCapacity? {
  if max_bytes < 1 {
    return None
  }
  let controls = @source.json_source_preflight_control_extent()
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: controls.record_headers + 4L,
      reference_slots: controls.reference_slots + 10L,
      scalar_words: controls.scalar_words + 4L,
      owned_utf16_units: max_bytes.to_int64(),
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
