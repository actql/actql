///|
// One reservation per complete generated artifact, including embedded copies.
// Hashing, encoding and admission share that reservation; their individual caps
// remain in force. This is preparation accounting, not a CPU or heap meter.
priv struct ValuesMetadataBudget {
  mut bytes : Int
  mut nodes : Int
  mut used_bytes : Int
  mut used_nodes : Int
}

///|
let values_metadata_cid : String = "sha256:" + "0".repeat(64)

///|
fn values_metadata_bytes(
  budget : ValuesMetadataBudget?,
  limits : @wire.LimitLimits,
) -> Int {
  match budget {
    Some(b) => b.bytes.min(limits.max_bytes)
    None => limits.max_bytes
  }
}

///|
fn values_metadata_nodes(
  budget : ValuesMetadataBudget?,
  limits : @wire.LimitLimits,
) -> Int {
  match budget {
    Some(b) => b.nodes.min(limits.max_nodes)
    None => limits.max_nodes
  }
}

///|
fn reserve_values_metadata(
  budget : ValuesMetadataBudget?,
  limits : @wire.LimitLimits,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  guard budget is Some(budget) else { return }
  let out = @encode.measuring_writer(
    limits.max_bytes.min(budget.bytes),
    limits.max_nodes.min(budget.nodes),
    limits.max_depth,
  )
  emit(out)
  let (bytes, nodes, _) = @encode.finish_measurement_usage(out)
  budget.bytes -= bytes
  budget.nodes -= nodes
  budget.used_bytes += bytes
  budget.used_nodes += nodes
}
