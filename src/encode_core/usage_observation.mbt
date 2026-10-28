///|
/// Original charged writer cells, including a closed/refused writer. No output,
/// digest, completion, publication or permission can be obtained from this DATA.
/// Observing does not reopen, finish, rewind or alter the original writer.
pub fn observed_writer_usage(writer : Writer) -> (Int, Int, Int) {
  (
    writer.max_bytes - writer.remaining_bytes,
    writer.max_nodes - writer.remaining_nodes,
    writer.peak_depth,
  )
}
