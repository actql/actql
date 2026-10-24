///|
/// Constructor-boundary plan rule, not a second reservation calculator.
/// The fixed caller establishes that the preceding constructor has returned;
/// all surviving dependencies remain in cumulative R. Keep the prior E debit
/// rather than refunding it, and grow only if this complete next phase needs
/// more. Fixed projector controls may coexist with either constructor phase.
fn closed_values_execution_peak(
  prior_reserved : Int64,phase_scratch : Int64,controls : Int64,
) -> Int64? {
  if prior_reserved<0L || phase_scratch<0L || controls<0L ||
    phase_scratch>9223372036854775807L-controls {return None}
  Some(Int64::max(prior_reserved,phase_scratch+controls))
}
