///|
// Logical representation census, not a native allocator/RSS measurement.
// H/R/S below mean headers/reference slots/scalar words. Charge simultaneous
// variants conservatively, including mutually exclusive failure paths:
//
// * Capture holder: H1/R24/S5 (23 optional references plus borrowed limits;
//   offset, three progression flags, phase). Its Some wrappers: H23/R23/S23.
// * Selection snapshot: record + two path arrays + optional key path Some,
//   H4/R(7 + path lengths)/S1. Strings/limits/declarations remain borrowed.
// * First failure chain: carrier, owner Some, outer issue, inner issue,
//   FileCaptureStop, two Result carriers, saved failure Some: H8/R9/S7.
// * Persistent verify/cleanup closures and one live mapping closure: H3/R3.
// * Filesystem managed values: observation H1/R3; generation H1/S3;
//   chunk H1/R1/S1; Root/Reader failures H2/R4 and their Some H2/R2/S2.
// * Buffers: receive array, exact Bytes, returned chunk Bytes, path UTF8 Bytes,
//   diagnostic Bytes, four decoded diagnostic strings/builders: H9. Their
//   bodies are counted separately below and in the provider transport quote.
// * Quote values: mapping/document inventories H2/S10, layout H1/S5,
//   projection geometry H1/R2/S2, singleton array H1/R1, capacity H1/S2;
//   six result Some wrappers H6/R6/S6. No borrowed Contract tree is copied.
// * Fixed call frontier: prepare/advance/close -> helper -> current owner ->
//   Common/FS entry. Count original and map_err Result at each of four levels,
//   plus two tuple projections (source identity and capture progress):
//   H10/R12/S10. Common's own variable parser/execution frontiers are quoted by
//   their existing inventories, not duplicated or replaced by this census.
//
// The reservation retains this complete peak until final close. No phase/GC
// credit is claimed. Fixed VM stack frames belong to the installed baseline.
fn file_capture_metadata_capacity(
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Int64? {
  guard @rows.relation_document_mapping_construction_inventory(limits.page)
    is Some(mapping) &&
    @execution.preparation_representation_cost(mapping) is Some(mapped) &&
    @execution.checked_preparation_add_product(
      selection.items_path.length().to_int64(),
      selection.key_path.map(path => path.length().to_int64()).unwrap_or(0L),
      1L,
    )
    is Some(paths) &&
    @execution.checked_preparation_add_product(
      24L + 23L + 7L + 9L + 3L + 3L + 1L + 4L + 2L + 2L + 1L + 6L + 12L,
      paths,
      1L,
    )
    is Some(references) &&
    @execution.checked_preparation_add_product(
      0L,
      limits.diagnostic_ceiling.to_int64(),
      8L,
    )
    is Some(diagnostics) &&
    @execution.preparation_representation_cost({
      record_headers: 1L +
      23L +
      4L +
      8L +
      3L +
      1L +
      1L +
      1L +
      2L +
      2L +
      9L +
      2L +
      1L +
      1L +
      1L +
      1L +
      6L +
      10L,
      reference_slots: references,
      scalar_words: 5L +
      23L +
      1L +
      7L +
      3L +
      1L +
      2L +
      10L +
      5L +
      2L +
      2L +
      6L +
      10L,
      // Two Root and two Reader diagnostics, each decoded with an additional
      // builder/copy allowance. Each byte produces at most one UTF16 unit.
      owned_utf16_units: diagnostics,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return None
  }
  @execution.checked_preparation_add_product(mapped, controls, 1L)
}

///|
// Every signed sizeof fact and every product/sum is checked independently.
// This helper is a quote only: a synthetic layout cannot issue a physical
// original, admit a Reader or reserve any capacity.
fn file_capture_transport_capacity(
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
  layout : @files.NativeFilesystemReadLayout,
) -> Int64? {
  guard layout.root_payload_bytes > 0L &&
    layout.reader_payload_bytes > 0L &&
    layout.observation_payload_bytes > 0L &&
    layout.acquisition_payload_bytes > 0L &&
    layout.external_object_overhead_bytes > 0L else {
    return None
  }
  guard @execution.checked_preparation_add_product(
      layout.root_payload_bytes,
      layout.reader_payload_bytes,
      1L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      layout.observation_payload_bytes,
      1L,
    )
    is Some(total) &&
    // Count both Root and Reader acquisition carriers, even though serialized.
    @execution.checked_preparation_add_product(
      total,
      layout.acquisition_payload_bytes,
      2L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      layout.external_object_overhead_bytes,
      5L,
    )
    is Some(total) &&
    // Four UTF8 bytes per UTF16 unit. Root opening overlaps encoded input,
    // terminated C path and retained custody path. Name has encoded+C copies.
    @execution.checked_preparation_add_product(
      total,
      selection.directory.length().to_int64(),
      12L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      selection.name.length().to_int64(),
      8L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(total, 4L, 1L) is Some(total) &&
    // Four retained C error/close_error buffers, one replacement overlap and
    // one returned diagnostic Bytes. UTF16 decoded storage is in metadata.
    @execution.checked_preparation_add_product(
      total,
      limits.diagnostic_ceiling.to_int64(),
      6L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(total, 6L, 1L) is Some(total) &&
    // Mutable receive storage coexists with the immutable original Bytes;
    // the Reader's C chunk coexists with the returned MoonBit chunk Bytes.
    @execution.checked_preparation_add_product(
      total,
      limits.page.max_bytes.to_int64(),
      2L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      limits.chunk_bytes.to_int64(),
      2L,
    )
    is Some(total) else {
    return None
  }
  Some(total)
}

///|
// Common owns parser/mapping/typed-projection geometry. Reserve the complete
// transport/document overlap before Root construction or receiving bytes, and
// retain it until original RowRun cleanup. These logical tariffs never replace
// the independently enforced physical Native domain backing.
fn file_capture_provider_capacity(
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
  contract : @contract.Contract,
) -> @execution.ExecutionCapacity? {
  guard @rows.relation_document_construction_inventory(limits.page, [
      {
        original: contract,
        items_path_depth: selection.items_path.length(),
        key_path_depth: selection.key_path.map(path => path.length()),
        writable_fields: 0,
      },
    ])
    is Some(document) &&
    @execution.preparation_representation_cost(document) is Some(document_bytes) &&
    @files.native_filesystem_read_layout() is Some(layout) &&
    file_capture_transport_capacity(selection, limits, layout)
    is Some(transport) &&
    @execution.checked_preparation_add_product(document_bytes, transport, 1L)
    is Some(total) else {
    return None
  }
  @execution.execution_capacity(total, total)
}
