///|
fn carrier_preflight(
  b : Budget,
  source : @decode.Cursor,
  value : @carrier.Carrier,
) -> Unit raise Stop {
  let original = begin_carrier_preflight_read(b, source, value)
  while original.state is Pending {
    advance_carrier_preflight_read(original)
  }
  match original.state {
    Complete => clear_carrier_preflight_read(original)
    Rejected(issue) => {
      clear_carrier_preflight_read(original)
      raise Stop(issue)
    }
    _ =>
      abort(
        "original Carrier preflight was retired during its synchronous call",
      )
  }
}
