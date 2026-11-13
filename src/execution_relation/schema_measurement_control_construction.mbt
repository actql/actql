///|
/// Managed control constructors of measurement-only schema emission. This is
/// not an identity-mode recipe and owns no hash/text sink, identity, name list
/// entries or wire. Writer/operation and CheckedEmission recipes, borrowed
/// checked schema, and scalar scanner/runtime stack are separate obligations.
pub(all) struct RelationSchemaMeasurementControls {
  collections : @shape.CollectionConstructionExtent
  max_record_references : Int
  max_record_words : Int
  reference_array_slots : Int64
} derive(Eq, Debug)

///|
/// Conservative sum of named allocation-site maxima, NOT loop iterations.
/// Phase-local observations retire before the next field. Counting sequential
/// return/refusal alternatives together avoids relying on early retirement.
/// The final metrics tuple belongs to measuring_writer_construction_extent;
/// its retained Some wrapper belongs here. Empty names arrays are allocated
/// at start and cancellation even though measurement never appends a name.
pub fn relation_schema_measurement_control_extent() -> RelationSchemaMeasurementControls {
  // RelationSchemaIdentityPreparation: eight reference fields, seven Int/Bool
  // fields, two Int64 counters (four scalar words).
  let preparation : @shape.CollectionConstructionExtent = {
    record_headers: 1L,
    reference_slots: 8L,
    scalar_words: 11L,
  }
  // Some(schema/writer/key/contract/measured), successful start/outer finish
  // Result wrappers. CheckedEmitter and ordered-key cursor objects themselves
  // are NOT included here; their original owners describe them.
  let retained_wrappers : @shape.CollectionConstructionExtent = {
    record_headers: 7L,
    reference_slots: 7L,
    scalar_words: 0L,
  }
  // Three advance success sites: already done, measurement finish, quantum
  // yield. Each returns a (Bool,Int) tuple inside Ok.
  let returns : @shape.CollectionConstructionExtent = {
    record_headers: 6L,
    reference_slots: 3L,
    scalar_words: 6L,
  }
  // start: InvalidLimits Err, FieldLimit Err, Encoding+Err (4H4R).
  // advance: Closed Err, Encoding+Err (3H3R). The outer measure function
  // has two propagated Err return sites (2H2R). Nullary issue tags borrow
  // their original variant constants; no output diagnostic text is built.
  let refusal : @shape.CollectionConstructionExtent = {
    record_headers: 9L,
    reference_slots: 9L,
    scalar_words: 0L,
  }
  // Indexed schema reads are shallow. Include Flat's field-name variant,
  // reconstructed Field, source/result Options and map closure; Scoped's
  // returned Option borrows its Field. field_reference_name_at similarly
  // returns borrowed admitted spelling through source/result Options+closure.
  let observations : @shape.CollectionConstructionExtent = {
    record_headers: 9L,
    reference_slots: 8L,
    scalar_words: 1L,
  }
  // reference_name_construction_extent is called for accounting in phase1:
  // reference_parts pair(2R), inventory(2R+Int64), two Collection extents
  // (three Int64 each). It DOES NOT construct the spelling String. The actual
  // field_reference_name_at borrows it. Existing name overcounts stay separate.
  let name_quote : @shape.CollectionConstructionExtent = {
    record_headers: 4L,
    reference_slots: 4L,
    scalar_words: 14L,
  }
  let names = @shape.collection_construction_extent({
    records: 0L,
    record_references: 0L,
    record_words: 0L,
    reference_arrays: 2L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let mut total = preparation
  for
    component in [
      retained_wrappers, returns, refusal, observations, name_quote, names,
    ] {
    total = @shape.add_collection_construction_extents(total, component).unwrap()
  }
  {
    collections: total,
    max_record_references: 8,
    max_record_words: 11,
    reference_array_slots: 12L,
  }
}
