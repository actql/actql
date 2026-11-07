///|
// Original immutable preflight DATA retained by the installing caller. This
// owns no Ledger, read permission or physical resource. Reusing it avoids
// parsing the same declared schema and quoting the same provider at read time.
struct NativeRelationFilePreparedProvider {
  declaration : @rows.RowDeclaration
  selection : NativeRelationFileSelection
  limits : NativeRelationFileLimits
  prepared_contract : @rows.RelationDocumentPreparedContract
  capacity : @execution.ExecutionCapacity
}

///|
pub fn prepare_native_relation_file_provider(
  declaration : @rows.RowDeclaration,
  selection : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Result[NativeRelationFilePreparedProvider, NativeRelationFileIssue] {
  if !file_capture_selected_input_valid(selection, limits) {
    return Err(InvalidInput)
  }
  let prepared_contract = match
    @rows.prepare_relation_document_contract(
      declaration,
      selection.resource,
      selection.primary_identity,
      limits.page,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  let contract = @rows.relation_document_prepared_contract(prepared_contract)
  guard file_capture_provider_capacity(
      selection,
      limits,
      contract,
      prepared_contract=Some(prepared_contract),
    )
    is Some(capacity) else {
    return Err(Capacity)
  }
  let selection = {
    ..selection,
    items_path: selection.items_path.copy(),
    key_path: selection.key_path.map(path => path.copy()),
  }
  Ok({ declaration, selection, limits, prepared_contract, capacity, })
}

///|
/// The SAME immutable allowance goes into the original managed Plan. This
/// projection grants neither backing nor a read and invokes no current callback.
pub fn NativeRelationFilePreparedProvider::capacity(
  self : Self,
) -> @execution.ExecutionCapacity {
  self.capacity
}

///|
fn file_capture_provider_matches(
  original : NativeRelationFilePreparedProvider,
  selected : NativeRelationFileSelection,
  limits : NativeRelationFileLimits,
) -> Bool {
  // Limits are immutable public DATA, not a nominal issuer. Compare the
  // retained quantities; the Plan still requires its SAME capacity original.
  original.limits.page.max_bytes == limits.page.max_bytes &&
  original.limits.page.max_nodes == limits.page.max_nodes &&
  original.limits.page.max_depth == limits.page.max_depth &&
  original.limits.page.max_rows == limits.page.max_rows &&
  original.limits.max_work == limits.max_work &&
  original.limits.chunk_bytes == limits.chunk_bytes &&
  original.limits.diagnostic_ceiling == limits.diagnostic_ceiling &&
  original.selection.directory == selected.directory &&
  original.selection.name == selected.name &&
  original.selection.resource == selected.resource &&
  original.selection.primary_identity == selected.primary_identity &&
  original.selection.items_path == selected.items_path &&
  original.selection.key_path == selected.key_path
}

///|
// One original typed projection inventory for listing and keyed Content DATA.
// This borrows the admitted Contract; it does not rebuild or authorize it.
fn file_provider_projection_inventory(
  provider : NativeRelationFilePreparedProvider,
) -> @execution.PreparationRepresentationUnits? {
  let selection = provider.selection
  @rows.relation_document_projection_construction_inventory(
    {
      original: @rows.relation_document_prepared_contract(
        provider.prepared_contract,
      ),
      items_path_depth: selection.items_path.length(),
      key_path_depth: selection.key_path.map(path => path.length()),
      writable_fields: 0,
    },
    provider.limits.page,
  )
}
