///|
/// Borrow the exact checked input contract. Equal separately admitted contracts
/// cannot supply CheckedValues to this acquisition's original input buffer.
pub fn row_acquisition_column_contract(
  value : RowAcquisition,
  index : Int,
) -> @contract.Contract? {
  @schema.field_at(value.preparation.schema, index).map(field => field.contract)
}

///|
/// Borrow the exact WholeInput carrier contract, never an equal re-admission.
pub fn row_input_acquisition_column_contract(
  value : RowInputAcquisition,
  index : Int,
) -> @contract.Contract? {
  @schema.field_at(value.preparation.schema, index).map(field => field.contract)
}
