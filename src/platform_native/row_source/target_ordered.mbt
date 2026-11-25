///|
/// The same physical child and write lock as the scalar path. The identity
/// borrows the approved canonical tuple wire until the child returns.
pub fn prepare_native_relation_file_ordered_target_io(
  provider : NativeRelationFilePreparedProvider,
  writable : Array[String],
  key_wire : String,
  mutation : NativeRelationFileTargetMutation,
  before_response : (Int) -> Bool,
  predecessor? : NativeRelationFileReplacementAck? = None,
) -> Result[NativeRelationFileTargetIO, NativeRelationFileIssue] {
  guard provider.ordered_key is Some(key) else { return Err(InvalidInput) }
  prepare_native_relation_file_target_io_original(
    provider,
    writable,
    key_wire,
    mutation,
    predecessor~,
    before_response=Some(before_response),
    staged_update=mutation.writes(),
    ordered_key=Some(key),
  )
}

///|
/// Size the same staged child. Only the original File observation supplies a
/// measured response length. The second result is write allocation placement.
pub fn native_relation_file_ordered_target_construction(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
  key_wire : String,
  mutation : NativeRelationFileTargetMutation,
  response_bytes : Int?,
) -> (@execution.ExecutionCapacity, Int64)? {
  guard provider.ordered_key is Some(key) else { return None }
  let size = response_bytes.unwrap_or(0)
  if writable_fields < 0 ||
    !file_capture_text(key_wire, provider.limits.page.max_bytes) {
    return None
  }
  let original = match mutation {
    ObserveTarget | ObserveOptionalTarget =>
      native_relation_file_target_read_io_capacity(
        provider,
        writable_fields,
        response_bytes=Some(size),
        ordered_wire_utf16=Some(key_wire.length()),
      ).map(capacity => (capacity, 0L))
    ObserveDeleteTarget =>
      native_relation_file_delete_target_read_io_capacity(
        provider,
        response_bytes=Some(size),
        ordered_wire_utf16=Some(key_wire.length()),
      ).map(capacity => (capacity, 0L))
    UpdateTarget(_, changes, _) =>
      native_relation_file_target_update_construction(
        provider, writable_fields, size, changes,
      )
    DeleteTarget(_, _) =>
      native_relation_file_target_delete_construction(provider, size)
    InsertTarget(mapped, _) =>
      native_relation_file_target_insert_construction_original(
        provider,
        response_bytes,
        Some(mapped),
        Some(key),
      )
  }
  guard original is Some((capacity, placement)) else { return None }
  if response_bytes is None || !mutation.writes() {
    return original
  }
  guard ordered_target_key_capacity(key, key_wire.length())
    is Some((extra, key_placement)) &&
    @execution.add_execution_capacity(capacity, extra) is Some(combined) else {
    return None
  }
  Some((combined, Int64::max(placement, key_placement)))
}

///|
fn ordered_target_key_capacity(
  key : @rows.RelationDocumentPreparedKey,
  wire_utf16 : Int,
) -> (@execution.ExecutionCapacity, Int64)? {
  guard @rows.relation_target_key_wire_workspace_inventory(key, wire_utf16)
    is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(cost) &&
    @execution.execution_capacity(cost, cost) is Some(capacity) &&
    target_update_native_placement(units, 0L) is Some(placement) else {
    return None
  }
  Some((capacity, placement))
}
