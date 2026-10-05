///|
/// Independent bounded decoder retention and execution scratch. These scalar
/// allowances confer no borrow, execution or physical holding authority.
pub(all) struct NativeRemoteStandardTransferSourceCapacity {
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
/// Declared capacity of the existing bounded row decoder and captured input.
/// This covers decoding/retention, not Source acquisition, a Native engine,
/// physical Transfer holdings or execution authority. The caller must reserve
/// it using the same limits passed to physical admission.
pub fn native_remote_standard_transfer_source_capacity(
  limits : NativeRemoteStandardTransferSourceLimits,
) -> NativeRemoteStandardTransferSourceCapacity? {
  let values = limits.values
  let wire = limits.wire
  for
    value in [
      limits.max_rows,
      limits.max_wire_bytes,
      limits.max_entries,
      limits.max_name_bytes,
      values.max_nodes,
      values.max_text_bytes,
      values.max_depth,
      values.max_work,
      wire.max_bytes,
      wire.max_nodes,
      wire.max_depth,
      wire.max_text_bytes,
    ] {
    if value < 0 {
      return None
    }
  }
  if limits.max_read_bytes <= 0 {
    return None
  }
  // Value limits apply cumulatively to admitted output, while wire limits
  // apply to one row. Bound both provisional and immutable row representations,
  // row/schema metadata, and owned names using the existing Native Host's
  // conservative 256-byte node and 8-byte text capacity units.
  let retained = 256L *
    (
      2L * values.max_nodes.to_int64() +
      3L * limits.max_rows.to_int64() +
      4L * limits.max_entries.to_int64()
    ) +
    8L *
    (
      2L * values.max_text_bytes.to_int64() +
      2L * limits.max_name_bytes.to_int64()
    )
  // One framed row and its parsing/conversion scratch coexist with the
  // retained output. No acquisition query, receipt scan or Broad residual runs.
  let execution = 256L *
    (
      3L * wire.max_nodes.to_int64() +
      2L * values.max_depth.to_int64() +
      2L * wire.max_depth.to_int64()
    ) +
    8L * (4L * wire.max_bytes.to_int64() + 2L * wire.max_text_bytes.to_int64()) +
    2L * limits.max_read_bytes.to_int64()
  Some({ retained_bytes: retained, execution_bytes: execution, })
}
