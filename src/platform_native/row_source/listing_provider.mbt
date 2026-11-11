///|
/// Immutable implementation selection. The public listing declaration remains
/// distinct from the physical Text-row declaration; neither is reference or
/// read authority. The SAME capacity original belongs to the managed Plan.
/// The installing Source funds/retains this holder and its original issuer and
/// method before construction; no issuance or current callback runs here.
struct NativeRelationFileListingProvider {
  declaration : @rows.RowDeclaration
  resource : String
  physical : NativeRelationFilePreparedProvider
  fields : NativeRelationFileListingFields
  capacity : @execution.ExecutionCapacity
  now_ms : (() -> Int64)?
  issuer : @admitted.ReferenceIssuer
  issue_resource : (String) -> Result[
    @admitted.CheckedValue,
    NativeRelationFileIssue,
  ]
}

///|
/// Bind an optional original Host monotonic clock. A managed capture retains
/// its own start/last observations; sharing this immutable provider never
/// shares or resets another Read's timer. This port issues no read authority.
pub fn prepare_native_relation_file_listing_provider(
  declaration : @rows.RowDeclaration,
  resource : String,
  physical : NativeRelationFilePreparedProvider,
  fields : NativeRelationFileListingFields,
  issuer : @admitted.ReferenceIssuer,
  issue_resource : (String) -> Result[
    @admitted.CheckedValue,
    NativeRelationFileIssue,
  ],
  now_ms? : (() -> Int64)? = None,
) -> Result[NativeRelationFileListingProvider, NativeRelationFileIssue] {
  if !declaration.views.any(view => view.resource == resource) ||
    !file_listing_fields_valid(physical, fields) {
    return Err(InvalidInput)
  }
  guard file_listing_provider_capacity(
      physical,
      if physical.response_measured {
        Some(1)
      } else {
        None
      },
    )
    is Some(capacity) else {
    return Err(Capacity)
  }
  // The listing inventory already contains the physical typed projection.
  // Adding physical.capacity would charge that same projection twice.
  Ok({
    declaration,
    resource,
    physical,
    fields,
    capacity,
    issuer,
    now_ms,
    issue_resource,
  })
}

///|
pub fn NativeRelationFileListingProvider::capacity(
  self : Self,
) -> @execution.ExecutionCapacity {
  self.capacity
}

///|
fn file_listing_provider_capacity(
  physical : NativeRelationFilePreparedProvider,
  response_bytes : Int?,
) -> @execution.ExecutionCapacity? {
  let limits = physical.limits
  guard file_capture_response_backing_page(limits.page, response_bytes)
    is Some(page) else {
    return None
  }
  guard @rows.relation_document_raw_construction_inventory(page) is Some(raw) &&
    file_listing_construction_inventory(physical, response_bytes)
    is Some(listing) &&
    @execution.compose_preparation_representation([raw, listing])
    is Some(document) &&
    @execution.preparation_representation_cost(document) is Some(bytes) &&
    @files.native_filesystem_read_layout() is Some(layout) &&
    file_capture_transport_capacity(physical.selection, limits, layout)
    is Some(transport) &&
    @execution.checked_preparation_add_product(bytes, transport, 1L)
    is Some(total) &&
    @execution.execution_capacity(total, total) is Some(capacity) else {
    return None
  }
  Some(capacity)
}
