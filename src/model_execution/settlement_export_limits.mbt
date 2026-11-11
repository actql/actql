///|
/// The existing ordinary call-settlement codec policy. Both Native and the
/// existing bridge supply their admitted output/work bounds; this projection
/// issues no capacity, persistence acknowledgement or Model permission.
pub fn model_call_settlement_export_limits(
  max_bytes : Int,
  max_work : Int,
) -> ModelCaptureExportLimits {
  {
    max_bytes,
    max_nodes: 100000,
    max_depth: 100,
    max_chunk_bytes: 16384,
    max_work,
  }
}
