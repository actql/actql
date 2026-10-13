///|
// Nominal original capture, not Source evidence reconstructed from a payload.
pub fn captured_source_matches_segment_input(
  source : CapturedInputSource,
  input : @execution.ProducerRead,
) -> Bool {
  (source.live)() &&
  @execution.producer_read_matches_completed_output(input, source.output)
}
