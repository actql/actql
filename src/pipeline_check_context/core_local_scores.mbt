///|
fn core_contract_local_scores(
  b : CoreContractBuilder,
  stage : Int,
  index : Int,
  snapshot : @snapshot.Snapshot,
) -> Unit raise CoreContractStop {
  core_contract_charge(b)
  let remaining = b.limits.max_work - b.work
  let (cid, size, count) = try {
    let writer = @encode.hashing_writer(
      (b.hash_limits.max_bytes - b.hash_bytes).min(remaining),
      (b.hash_limits.max_nodes - b.hash_nodes).min(remaining),
      b.hash_limits.max_depth,
    )
    @snapshot.emit_score_projection(snapshot, writer)
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
    StageLocalInputScores(stage, index),
    LocalInputScores("sha256:" + cid),
  )
}
