///|
// Borrow the SAME active command Read synchronously. Preserve its original
// refusal in the existing command holder before Account unwinds its child.
fn LocalCommandPreparationOriginal::prepare_account_construction(
  self : LocalCommandPreparationOriginal,
  construction : @authorization.AccountConfigurationConstruction,
) -> Bool {
  let price = fn(units : @authorization.AccountConfigurationConstructionUnits) {
    @execution.preparation_representation_cost({
      record_headers: units.record_headers,
      reference_slots: units.reference_slots,
      scalar_words: units.scalar_words,
      owned_utf16_units: units.owned_utf16_units,
      owned_wire_bytes: units.owned_wire_bytes,
    })
  }
  guard price(construction.retained) is Some(r) &&
    price(construction.execution) is Some(e) else {
    self.retain_primary(CommandUnavailable)
    return false
  }
  match self.prepare_host_metadata(r, e) {
    Ok(_) => true
    Err(issue) => {
      self.retain_primary(issue)
      false
    }
  }
}
