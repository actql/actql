///|
/// Independent consumer counters: identities are retained occurrences, while
/// producer-read entries include metadata comparison work. With every original
/// schema width <= F, P and C are each <= F; use the unsampled checked upper
/// envelope F+P+F*(P+C). Name traversal visits at most F candidate schemas plus
/// the receiving schema. Unknown carrier shapes retain their previous policy.
fn client_local_dispatch_bounds(
  inventory : ClientLocalSchemaProofInventory?,
  graph : @strategy.CheckedDAG?,
) -> (Int,Int) {
  guard inventory is Some(proof) && graph is Some(original) else {return (100,10000)}
  let fields=proof.fields.to_int64()
  let identities=@strategy.graph_result_count(original).to_int64()+1L
  let entries=Int64::max(identities,2L*fields+2L*fields*fields)
  let names=proof.names.to_int64()*(fields+1L)
  if entries>2147483647L || names>2147483647L {return (100,10000)}
  (Int::max(1,entries.to_int()),names.to_int())
}
