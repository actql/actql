///|
/// Diagnostic-only read of the existing token. It does not release or recharge it.
pub fn native_holding_custody_details(
  ledger : Ledger,
  holding : Holding,
) -> String {
  "\"serial\":" +
  holding.serial.to_string() +
  ",\"reservationSerial\":" +
  holding.reservation_serial.to_string() +
  ",\"bytes\":" +
  holding.bytes.to_string() +
  ",\"ownerMatches\":" +
  physical_equal(ledger, holding.owner).to_string() +
  ",\"available\":" +
  holding_available(ledger, holding).to_string()
}
