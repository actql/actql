///|
/// Fixed managed operation scratch of the original MeasureOutput path.
/// The Writer/frame/sink/finish owner, borrowed input, emitter continuation and
/// opaque runtime stack are excluded. No hash, text buffer or output wire.
pub(all) struct MeasurementOperationConstruction {
  collections : @shape.CollectionConstructionExtent
  owned_utf16_units : Int64
  max_string_utf16_units : Int64
  max_record_references : Int
  max_record_words : Int
} derive(Eq, Debug)

///|
pub fn measurement_operation_construction_extent() -> MeasurementOperationConstruction {
  {
    // OrderedKeyEmitCursor(3R3W), StringEmitCursor(3R2W), last/pop Option
    // carriers(2R2W), typed failure(1W), two one-unit escape Strings and the
    // finite Double decimal String (same pinned <=25-unit owner bound used
    // by hash/text writer inventories). Sequential alternatives co-count.
    collections: { record_headers: 8L, reference_slots: 8L, scalar_words: 8L, },
    owned_utf16_units: 2L + 25L,
    max_string_utf16_units: 25L,
    max_record_references: 3,
    max_record_words: 3,
  }
}
