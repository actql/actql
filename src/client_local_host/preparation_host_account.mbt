///|
// Installed fixed DATA, priced by the same representation tariff before the
// new read/borrow control records are constructed. No input-byte fee/cap.
let host_account_read_controls : Int64 = {
  let (h, r, w) = @resources.preparation_account_read_control_slots()
  @execution.preparation_representation_cost({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
pub fn[I] prepare_host_initialization_account_read(
  owner : ClientHostInitializationPreparation[I],
) -> Result[@resources.PreparationAccountRead, ClientHostInitializationIssue] {
  guard owner.phase == Open && owner.input is Some(input) else {
    return Err(WrongPhase)
  }
  @resources.prepare_account_read(
    owner.capacity,
    input,
    host_account_read_controls,
  ).map_err(issue => Capacity(issue))
}

///|
pub fn[I, P] prepare_installed_account_read(
  owner : @resources.PreparationCapacity[I, P],
  input : I,
) -> Result[
  @resources.PreparationAccountRead,
  @resources.PreparationCapacityIssue,
] {
  @resources.prepare_account_read(owner, input, host_account_read_controls)
}
