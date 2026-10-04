///|
fn core_contract_local_type(
  b : CoreContractBuilder,
  stage : Int,
  index : Int,
  stage_name : String,
  input_name : String,
  schema : @schema.Schema,
) -> Unit raise CoreContractStop {
  core_contract_charge(b)
  let remaining = b.limits.max_work - b.work
  let bytes = b.hash_limits.max_bytes - b.hash_bytes
  let nodes = b.hash_limits.max_nodes - b.hash_nodes
  let reference = match
    @local_ref.create(
      stage_name,
      input_name,
      max_bytes=if bytes < remaining { bytes } else { remaining },
    ) {
    Ok(v) => v
    Err(@local_ref.LimitExceeded) => raise CoreContractStop(BudgetExceeded)
    Err(_) => raise CoreContractStop(LocalTypeEncoding(stage, index))
  }
  let (cid, size, count) = try {
    let writer = @encode.hashing_writer(
      if bytes < remaining {
        bytes
      } else {
        remaining
      },
      if nodes < remaining {
        nodes
      } else {
        remaining
      },
      b.hash_limits.max_depth,
    )
    @snapshot.emit_schema_type_projection(reference, schema, writer)
    @encode.finish_hash_usage(writer)
  } catch {
    @encode.OutputLimit => raise CoreContractStop(BudgetExceeded)
    _ => raise CoreContractStop(LocalTypeEncoding(stage, index))
  }
  if size > remaining || count > remaining - size {
    raise CoreContractStop(BudgetExceeded)
  }
  b.work += size + count
  b.hash_bytes += size
  b.hash_nodes += count
  core_contract_root(
    b,
    StageLocalInputType(stage, index),
    LocalInputType("sha256:" + cid),
  )
}
