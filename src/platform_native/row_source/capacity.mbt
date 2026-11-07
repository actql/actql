///|
// Logical representation census, not a native allocator/RSS measurement.
// H/R/S below mean headers/reference slots/scalar words. Charge simultaneous
// variants conservatively, including mutually exclusive failure paths:
//
// * Original acquisition selector: H1/R4/S1. The managed-input arm retains
//   acquisition/read/selected-capacity/provider; managed Query arms borrow
//   acquisition/read/provider (R3), within the same R4 peak; ordinary arms borrow one.
// * Capture holder: H1/R27/S8 (26 optional references plus borrowed limits;
//   offset, three progression flags, phase, advancing and two listing clocks).
//   Its Some wrappers: H26/R26/S26. Content's own child storage is additional.
// * Selection snapshot: record + two path arrays + optional key path Some,
//   H4/R(7 + path lengths)/S1. Strings/limits/declarations remain borrowed.
// * First failure chain: carrier, owner Some, outer issue, inner issue,
//   FileCaptureStop, two Result carriers, saved failure Some: H9/R10/S8,
//   including the managed read's extra typed acquisition-issue wrapper.
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
//   plus two tuple projections (source identity and capture progress), and
//   the managed start's Some(original Ledger): H11/R13/S11. Common's own variable parser/execution frontiers are quoted by
//   their existing inventories, not duplicated or replaced by this census.
//
// * Keyed document/page/retention entry, refusal and return products: H10/R14/S10.
//   Its original RowKeyedAcquisition/read/provider/issuer arm uses the same
//   four borrowed selector slots. Its separate raw-provider capacity is added
//   before reservation; checked keyed-row response storage remains RowRun-owned.
//
// The reservation retains this complete peak until final close. No phase/GC
// credit is claimed. Fixed VM stack frames belong to the installed baseline.
fn file_capture_metadata_capacity(
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
  prepared_provider? : NativeRelationFilePreparedProvider? = None,
  listing? : Bool = false,
) -> Int64? {
  let mapped = match prepared_provider {
    Some(_) => 0L
    None => {
      guard @rows.relation_document_mapping_construction_inventory(limits.page)
        is Some(mapping) &&
        @execution.preparation_representation_cost(mapping) is Some(bytes) else {
        return None
      }
      bytes
    }
  }
  guard @execution.checked_preparation_add_product(
      selection.items_path.length().to_int64(),
      selection.key_path.map(path => path.length().to_int64()).unwrap_or(0L),
      1L,
    )
    is Some(paths) &&
    @execution.checked_preparation_add_product(
      4L + 27L + 26L + 7L + 10L + 3L + 3L + 1L + 4L + 2L + 2L + 1L + 6L + 13L,
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
      1L +
      26L +
      4L +
      9L +
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
      11L +
      10L,
      reference_slots: references + 14L,
      scalar_words: 1L +
      8L +
      26L +
      1L +
      8L +
      3L +
      1L +
      2L +
      10L +
      5L +
      2L +
      2L +
      6L +
      11L +
      10L,
      // Two Root and two Reader diagnostics, each decoded with an additional
      // builder/copy allowance. Each byte produces at most one UTF16 unit.
      owned_utf16_units: diagnostics,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return None
  }
  let prepared_control = if prepared_provider is Some(_) {
    // The retained prepared-contract Option uses the existing holder slot.
    // Its initializer's one temporary mapping closure is additional here.
    @execution.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 1L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
  } else {
    0L
  }
  let listing_control = if listing {
    // Original issuer Some (H1/R1/W1), projection callback closing over the
    // SAME owner/provider (H1/R2), two typed error projections (H2/R2), and
    // the elapsed-call Option/frontier (H1/R3/W3). The Source owns its provider
    // record, original issuer and issuance construction separately.
    @execution.preparation_representation_cost({
      record_headers: 5L,
      reference_slots: 8L,
      scalar_words: 4L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
  } else {
    0L
  }
  let response_quote = if prepared_provider
    .map(provider => provider.response_measured)
    .unwrap_or(false) {
    // The original admitted Contract has at most n nodes. These are the same
    // five bounded quote walks documented by the caller preflight inventory,
    // now inside the retained reader before its charged-response grow. Their
    // cursor/array/result backing must precede that Resource callback too.
    let n = limits.page.max_nodes.to_int64()
    @execution.preparation_representation_cost({
      record_headers: 600L + 11L * n,
      reference_slots: 200L + 26L * n,
      scalar_words: 1400L + 11L * n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
  } else {
    0L
  }
  let controls = @execution.checked_preparation_add_product(
    controls, response_quote, 1L,
  ).unwrap()
  @execution.checked_preparation_add_product(mapped, controls, 1L).bind(total => {
    @execution.checked_preparation_add_product(total, prepared_control, 1L).bind(total => {
        @execution.checked_preparation_add_product(total, listing_control, 1L)
      },
    )
  })
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
  prepared_contract? : @rows.RelationDocumentPreparedContract? = None,
  response_bytes? : Int? = None,
) -> @execution.ExecutionCapacity? {
  let page = match
    file_capture_response_backing_page(limits.page, response_bytes) {
    Some(value) => value
    None => return None
  }
  guard file_capture_projection_backing_page(
      contract,
      limits.page,
      response_bytes,
    )
    is Some(projection_page) else {
    return None
  }
  let projection : @rows.RelationDocumentProjectionConstruction = {
    original: contract,
    items_path_depth: selection.items_path.length(),
    key_path_depth: selection.key_path.map(path => path.length()),
    writable_fields: 0,
  }
  let document = match prepared_contract {
    None =>
      @rows.relation_document_construction_inventory(limits.page, [projection])
    Some(_) => {
      guard @rows.relation_document_raw_construction_inventory(page)
        is Some(raw) &&
        @rows.relation_document_projection_construction_inventory(
          projection, projection_page,
        )
        is Some(projected) else {
        return None
      }
      @execution.compose_preparation_representation([raw, projected])
    }
  }
  guard document is Some(document) &&
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

///|
/// Select this actual file implementation's existing parser/transport quote
/// BEFORE the managed Source Plan is constructed. Reuse this SAME value in
/// that Plan and its Native reader; it is neither a Ledger nor read authority.
pub fn native_relation_file_provider_capacity(
  declaration : @rows.RowDeclaration,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Result[@execution.ExecutionCapacity, NativeRelationFileIssue] {
  if !file_capture_selected_input_valid(selection, limits) {
    return Err(InvalidInput)
  }
  let contract = match
    @rows.relation_document_projection_contract(
      declaration,
      selection.resource,
      selection.primary_identity,
      limits.page,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  match file_capture_provider_capacity(selection, limits, contract) {
    Some(value) => Ok(value)
    None => Err(Capacity)
  }
}

///|
/// Pure complete overlap for this exact relation-file acquisition. This quote
/// includes the original Row attempt, parser/transport, scratch and retained
/// metadata; it issues neither a Ledger nor permission to start. A coordinator
/// adds the simultaneous Compute inventory before claiming the original Run.
pub fn native_relation_file_capture_limits(
  declaration : @rows.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @rows.RowAcquisition,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Result[@resources.LedgerLimits, NativeRelationFileIssue] {
  if !native_relation_file_input_valid(selection, limits) ||
    @rows.row_acquisition_is_listing(acquisition) {
    return Err(InvalidInput)
  }
  match
    @rows.check_row_acquisition_original(acquisition, declaration, requirement) {
    Err(issue) => return Err(Row(issue))
    Ok(_) => ()
  }
  // Borrow only the declared resource. row_source_target also copies all
  // selected fields, which this quote does not consume and which have not yet
  // passed the mapping construction bounds below. Preserve its exact missing
  // view refusal without allocating that unused array before validation.
  let source_ref = @planning.query_requirement_source(requirement).0
  let resource = match @rows.row_declaration_view(declaration, source_ref) {
    Some(view) => view.resource
    None => return Err(Row(@rows.Source(UndeclaredSource)))
  }
  if resource != selection.resource {
    return Err(ForeignOriginal)
  }
  let contract = match
    @rows.relation_document_projection_contract(
      declaration,
      resource,
      selection.primary_identity,
      limits.page,
    ) {
    Err(issue) => return Err(Mapping(issue))
    Ok(value) => value
  }
  guard file_capture_metadata_capacity(selection, limits) is Some(metadata) &&
    file_capture_provider_capacity(selection, limits, contract)
    is Some(provider) &&
    @rows.row_acquisition_provider_capacity(acquisition, Some(provider))
    is Some(combined) &&
    @execution.checked_preparation_add_product(
      metadata,
      @execution.execution_capacity_retained_bytes(combined),
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      metadata,
      @execution.execution_capacity_execution_bytes(combined),
      1L,
    )
    is Some(executing) &&
    @execution.checked_preparation_add_product(
      executing,
      limits.page.max_bytes.to_int64(),
      1L,
    )
    is Some(executing) else {
    return Err(Capacity)
  }
  Ok({
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: limits.page.max_bytes.to_int64(),
    retained_bytes: retained,
    execution_bytes: executing,
  })
}

///|
/// Quote the same physical file owner for a complete checked Source input.
/// Original input bounds/contract provenance remain with that acquisition.
pub fn native_relation_file_input_capture_limits(
  declaration : @rows.RowDeclaration,
  acquisition : @rows.RowInputAcquisition,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Result[@resources.LedgerLimits, NativeRelationFileIssue] {
  if !native_relation_file_input_valid(selection, limits) ||
    @rows.row_input_acquisition_is_listing(acquisition) {
    return Err(InvalidInput)
  }
  match
    @rows.check_row_input_acquisition_declaration(acquisition, declaration) {
    Err(issue) => return Err(Row(issue))
    Ok(_) => ()
  }
  let source_ref = @rows.row_input_acquisition_facts(acquisition).source_ref
  let resource = match @rows.row_declaration_view(declaration, source_ref) {
    Some(view) => view.resource
    None => return Err(Row(@rows.Source(UndeclaredSource)))
  }
  if resource != selection.resource {
    return Err(ForeignOriginal)
  }
  let contract = match
    @rows.relation_document_projection_contract(
      declaration,
      resource,
      selection.primary_identity,
      limits.page,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  guard file_capture_metadata_capacity(selection, limits) is Some(metadata) &&
    file_capture_provider_capacity(selection, limits, contract)
    is Some(provider) &&
    @rows.row_input_acquisition_capacity(acquisition, Some(provider))
    is Some(combined) &&
    @execution.checked_preparation_add_product(
      metadata,
      @execution.execution_capacity_retained_bytes(combined),
      1L,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      metadata,
      @execution.execution_capacity_execution_bytes(combined),
      1L,
    )
    is Some(executing) &&
    @execution.checked_preparation_add_product(
      executing,
      limits.page.max_bytes.to_int64(),
      1L,
    )
    is Some(executing) else {
    return Err(Capacity)
  }
  Ok({
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: limits.page.max_bytes.to_int64(),
    retained_bytes: retained,
    execution_bytes: executing,
  })
}

///|
// An actual charged input byte count bounds parser/typed text backing in the
// SAME units. Keep every node/depth/row policy and all transport ceilings. The
// parser below still receives the original limits; no refusal is relaxed.
fn file_capture_response_backing_page(
  page : @rows.RowPageLimits,
  response_bytes : Int?,
) -> @rows.RowPageLimits? {
  match response_bytes {
    None => Some(page)
    Some(bytes) =>
      if bytes < 0 || bytes > page.max_bytes {
        None
      } else {
        // Empty malformed input still needs its original bounded refusal frame.
        Some({ ..page, max_bytes: Int::max(1, bytes), })
      }
  }
}

///|
// Only the original closed Text-row profile has a direct cumulative input
// text bound. Other Contracts retain their full original projection envelope.
// Do not infer Decimal rendering, reference envelopes or nested output sizes
// from received byte length. NFC uses its existing generated output bound;
// six bytes per UTF16 unit covers JSON escaping, with raw structural overhead.
fn file_capture_projection_backing_page(
  contract : @contract.Contract,
  page : @rows.RowPageLimits,
  response_bytes : Int?,
) -> @rows.RowPageLimits? {
  guard response_bytes is Some(bytes) else { return Some(page) }
  if bytes < 0 || bytes > page.max_bytes {
    return None
  }
  guard contract.shape is @contract.Object(fields) else { return Some(page) }
  for index in 0..<@contract.field_count(fields) {
    if !(@contract.field_at(fields, index).unwrap().contract.shape
      is @contract.Text(_)) {
      return Some(page)
    }
  }
  guard @canonical.nfc_lf_retained_output_units(bytes.to_int64())
    is Some(normalized) &&
    @execution.checked_preparation_add_product(bytes.to_int64(), normalized, 6L)
    is Some(bound) else {
    return None
  }
  Some({
    ..page,
    max_bytes: Int64::min(page.max_bytes.to_int64(), Int64::max(1L, bound)).to_int(),
  })
}

///|
// One original Native holder/reservation for both constructor entry and its
// charged response continuation. Never recompute a different owner or release
// earlier outputs: grow uses this absolute simultaneous extent monotonically.
fn file_capture_construction_capacity(
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
  original : NativeRelationFileAcquisition,
  prepared_provider : NativeRelationFilePreparedProvider?,
  content : NativeRelationFileContentInput?,
  response_bytes : Int?,
) -> (Int64, Int64)? {
  let listing = match original {
    ManagedFileListingAcquisition(_, _, _, _)
    | ManagedFileQueryListingAcquisition(_, _, _) => true
    _ => false
  }
  let response_bound = if prepared_provider
    .map(provider => provider.response_measured)
    .unwrap_or(false) {
    Some(Int::max(1, response_bytes.unwrap_or(1)))
  } else {
    None
  }
  let metadata_bytes = match
    file_capture_metadata_capacity(
      selection,
      limits,
      prepared_provider~,
      listing~,
    ) {
    Some(value) => value
    None => return None
  }
  // Keyed RowRun funds its checked response; this same owner separately
  // retains the actual raw physical file/decoder provider until final close.
  let (metadata_retained, metadata_execution) = match original {
    ManagedFileKeyedAcquisition(_, _, provider, _) => {
      let capacity = if provider.response_measured {
        match
          file_capture_provider_capacity(
            provider.selection,
            provider.limits,
            @rows.relation_document_prepared_contract(
              provider.prepared_contract,
            ),
            prepared_contract=Some(provider.prepared_contract),
            response_bytes=response_bound,
          ) {
          Some(value) => value
          None => return None
        }
      } else {
        provider.capacity
      }
      guard @execution.checked_preparation_add_product(
          metadata_bytes,
          @execution.execution_capacity_retained_bytes(capacity),
          1L,
        )
        is Some(retained) &&
        @execution.checked_preparation_add_product(
          metadata_bytes,
          @execution.execution_capacity_execution_bytes(capacity),
          1L,
        )
        is Some(execution) else {
        return None
      }
      (retained, execution)
    }
    _ => (metadata_bytes, metadata_bytes)
  }
  let (metadata_retained, metadata_execution) = match content {
    None => (metadata_retained, metadata_execution)
    Some(input) => {
      guard native_relation_file_content_capacity(
          input,
          prepared_provider,
          response_bytes=response_bound,
        )
        is Some((retained, execution)) &&
        @execution.checked_preparation_add_product(
          metadata_retained, retained, 1L,
        )
        is Some(retained) &&
        @execution.checked_preparation_add_product(
          metadata_execution, execution, 1L,
        )
        is Some(execution) else {
        return None
      }
      (retained, execution)
    }
  }
  Some((metadata_retained, metadata_execution))
}
