///|
// Observe the SAME writer's charged value nodes after its original scope
// unwinds, including typed encoding failure. This is a known encoding-work
// dimension, not bytes, CPU time, complete compiler work or completion proof.
// The two original Plan writers each debit at most Int::max nodes, so a fresh
// per-invocation Int64 output cannot overflow. No output or digest is exposed.
fn retain_client_plan_encoding_nodes(
  output : Ref[Int64]?,
  writer : @encode.Writer,
) -> Unit {
  if output is Some(original) {
    original.val += @encode.observed_writer_usage(writer).1.to_int64()
  }
}
