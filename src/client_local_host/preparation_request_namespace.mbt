///|
// Input-proportional capture cells and additional resolver/projection closure
// contexts on the existing lowerer. The fixed Scope fields are separate.
// This describes at most eight contexts per original token, not VM frame/GC
// bytes, a new Ledger, a grant, or permission to spend unreserved capacity.
fn request_query_namespace_controls_bytes(tokens : Int64) -> Int64? {
  guard @execution.checked_preparation_add_product(0L, tokens, 8L) is Some(h) &&
    @execution.checked_preparation_add_product(0L, tokens, 20L) is Some(r) &&
    @execution.checked_preparation_add_product(0L, tokens, 12L) is Some(w) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// Four simultaneous lanes, all owned by the SAME synchronous compilation:
// 1. Original/remapped/selected/footer profiles, fallback names, tuples,
//    copied-star associations and old/new candidate/fold Strings (16H/48R/16W
//    per field cell). Borrowed field/name backing is not copied here.
// 2. View+Some links, expression frame/captures, access/undo/visit variants,
//    inspected nodes and optional result holders (16H/48R/24W per node cell).
// 3. Twelve profile/materialization vectors per snapshot, and eight live
//    expression/rollback/temp vectors. Shared collection laws include growing
//    old/new backing and spare slots. Map keys/values stay borrowed.
// 4. New display/materialization text and the resulting annotated/encoded
//    Program material. The existing import/writer/prefix/demand extent below
//    bounds that material, independently of these compiler DATA containers.
//
// E bounds original Query/operation snapshots; R bounds their row references;
// W bounds original input/syntax width, edits and actual star/JOIN growth.
// A single pass-through star has factor1. No runtime row count is used.
fn request_query_namespace_construction(
  tokens : Int64,
  geometry : (Int, Int, Int, Int, Int),
  inputs : (Int64, Int64),
  schema : (Int, Int),
  source_units : Int64,
  integer_context : Bool,
  has_star : Bool,
) -> (@execution.PreparationRepresentationUnits, Int, Int64)? {
  if tokens < 1L ||
    tokens > 2147483647L ||
    source_units < 0L ||
    inputs.0 < 0L ||
    inputs.1 < 0L ||
    schema.0 < 0 ||
    schema.1 < 0 ||
    geometry.0 < 0 ||
    geometry.1 < 0 ||
    geometry.2 < 1 ||
    geometry.3 < 0 ||
    geometry.4 < 0 {
    return None
  }
  let events = geometry.0.to_int64().max(1L)
  let references = geometry.4.to_int64() + 1L
  // With no published inputs the registered schemas are not another source
  // of fields. Nested checked fields are covered by the SAME cached complete
  // carrier-schema body node count, not a new traversal or protocol-value use.
  let schema_nodes = if inputs.0 == 0L { 0L } else { schema.1.to_int64() }
  let schema_names = if inputs.0 == 0L { 0L } else { schema.0.to_int64() }
  guard @execution.checked_preparation_add_product(inputs.0, schema_nodes, 1L)
    is Some(width) &&
    @execution.checked_preparation_add_product(width, geometry.1.to_int64(), 1L)
    is Some(width) &&
    @execution.checked_preparation_add_product(width, geometry.3.to_int64(), 1L)
    is Some(width) &&
    @execution.checked_preparation_add_product(
      0L,
      width.max(1L),
      geometry.2.to_int64(),
    )
    is Some(width) &&
    @execution.checked_preparation_add_product(
      0L,
      width,
      if integer_context {
        2L
      } else {
        1L
      },
    )
    is Some(width) else {
    return None
  }
  // Every individual field vector uses Int indexing. Saturation is a geometry
  // ceiling; checked totals still refuse overflow before any lowerer call.
  let width = width.min(2147483647L)
  guard @execution.checked_preparation_add_product(0L, events, references)
    is Some(snapshots) &&
    @execution.checked_preparation_add_product(0L, snapshots, width)
    is Some(fields) &&
    @execution.checked_preparation_add_product(0L, events, tokens)
    is Some(nodes) &&
    @execution.checked_preparation_add_product(
      0L,
      nodes,
      if has_star {
        width
      } else {
        1L
      },
    )
    is Some(nodes) &&
    @execution.checked_preparation_add_product(0L, snapshots, 12L)
    is Some(arrays) &&
    @execution.checked_preparation_add_product(arrays, 8L, 1L) is Some(arrays) &&
    @execution.checked_preparation_add_product(tokens, events, 1L)
    is Some(workspace) &&
    @execution.checked_preparation_add_product(workspace, width, 1L)
    is Some(workspace) &&
    @execution.checked_preparation_add_product(workspace, 1L, 1L)
    is Some(workspace) &&
    @execution.checked_preparation_add_product(0L, fields, 12L) is Some(items) &&
    @execution.checked_preparation_add_product(items, workspace, 16L)
    is Some(items) &&
    @execution.checked_preparation_add_product(0L, events, 2L) is Some(maps) &&
    @execution.checked_preparation_add_product(0L, maps, events)
    is Some(entries) &&
    @execution.checked_preparation_add_product(0L, nodes, 16L) is Some(h) &&
    @execution.checked_preparation_add_product(h, fields, 16L) is Some(h) &&
    @execution.checked_preparation_add_product(0L, nodes, 48L) is Some(r) &&
    @execution.checked_preparation_add_product(r, fields, 48L) is Some(r) &&
    @execution.checked_preparation_add_product(0L, nodes, 24L) is Some(w) &&
    @execution.checked_preparation_add_product(w, fields, 16L) is Some(w) else {
    return None
  }
  guard @shape.collection_construction_extent({
      records: h,
      record_references: r,
      record_words: w,
      reference_arrays: arrays,
      reference_items: items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps,
      map_entries: entries,
    })
    is Some(collections) else {
    return None
  }
  let controls = @shape.collection_construction_quotation_extent()
  // The existing four nodes per field cover both two-node select mappings.
  // A computed star field can additionally build a five-node property over
  // its shared evaluated receiver and one Group.by string. The whole receiver
  // is lowered once per original occurrence, not once per projected field.
  let material_per_field = if has_star { 10L } else { 4L }
  // Star property names can recur in the derive, projection and final Result
  // fields. Include three copies of the original name bound plus generated
  // slot names (receiver, property/key, projection and Result naming).
  let original_text_copies = if has_star { 3L } else { 1L }
  let generated_text_per_field = if has_star { 160L } else { 64L }
  guard @execution.checked_preparation_add_product(
      collections.record_headers,
      controls.record_headers,
      1L,
    )
    is Some(h) &&
    @execution.checked_preparation_add_product(
      collections.reference_slots,
      controls.reference_slots,
      1L,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(
      collections.scalar_words,
      controls.scalar_words,
      1L,
    )
    is Some(w) &&
    @execution.checked_preparation_add_product(source_units, inputs.1, 1L)
    is Some(text) &&
    @execution.checked_preparation_add_product(text, schema_names, 1L)
    is Some(text) &&
    @execution.checked_preparation_add_product(0L, text, original_text_copies)
    is Some(text) &&
    @execution.checked_preparation_add_product(
      text, width, generated_text_per_field,
    )
    is Some(text) &&
    @execution.checked_preparation_add_product(0L, snapshots, text.max(1L))
    is Some(text) &&
    @execution.checked_preparation_add_product(0L, text, 2L) is Some(utf16) &&
    @execution.checked_preparation_add_product(0L, fields, material_per_field)
    is Some(material_nodes) &&
    @execution.checked_preparation_add_product(material_nodes, snapshots, 16L)
    is Some(material_nodes) else {
    return None
  }
  if material_nodes >= 2147483647L || text > 2147483640L {
    return None
  }
  Some(
    (
      {
        record_headers: h,
        reference_slots: r,
        scalar_words: w,
        owned_utf16_units: utf16,
        owned_wire_bytes: 0L,
      },
      material_nodes.to_int(),
      text,
    ),
  )
}

///|
fn request_query_namespace_data_bytes(
  parsed : @query_syntax.Query,
  publication : @source_publication.PreparedPublishedQueryEnvironment,
  catalog : @checked.PreparedSourceCatalog,
  source_units : Int64,
) -> Int64? {
  let tokens = @query_syntax.token_count(@query_syntax.query_source(parsed)).to_int64()
  guard request_query_namespace_controls_bytes(tokens) is Some(controls) else {
    return None
  }
  if !@query_syntax.anonymous_output_context_required(parsed) {
    return Some(controls)
  }
  let environment = @checked.source_catalog_owner(catalog)
  let fields = if @query_syntax.anonymous_namespace_may_use_publication(parsed) {
    match
      @source_publication.prepared_published_query_input_field_geometry(
        publication, environment,
      ) {
      Ok(fields) => fields
      Err(_) => return None
    }
  } else {
    // All source paths resolved in their lexical scope or are locally
    // produced. Catalog admission and the base Context/copy costs remain.
    (0L, 0L)
  }
  let carriers = @environment.source_request_carriers(
    @checked.source_catalog_contracts(catalog),
  )
  let usage = @environment.carrier_schema_usage(carriers)
  guard request_query_namespace_construction(
      tokens,
      @query_syntax.anonymous_namespace_geometry(parsed),
      fields,
      (usage.0, usage.1),
      source_units,
      @query_syntax.integer_function_context_required(parsed),
      @query_syntax.anonymous_output_star_growth(parsed) > 0,
    )
    is Some((inventory, nodes, text)) &&
    @execution.preparation_representation_cost(inventory) is Some(metadata) &&
    request_query_literal_copy_bytes((nodes, text), 1) is Some(material) &&
    @execution.checked_preparation_add_product(controls, metadata, 1L)
    is Some(total) else {
    return None
  }
  @execution.checked_preparation_add_product(total, material, 1L)
}
