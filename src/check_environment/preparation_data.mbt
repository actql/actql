///|
pub(all) struct EnvironmentPreparationData {
  members : Int64
  max_fields : Int64
  max_name_utf16 : Int64
  inspection_work : Int64
}

///|
/// O(1) retained admission and normalized-Carrier dimensions, never a schema
/// verdict. No Program/member/subtree traversal, parse, hash or readmission.
/// Scalar literal/prompt length and outer member count never become a width.
pub fn preparation_data_geometry(
  original : WireEnvironment,
  contracts : SourceRequestContracts,
) -> EnvironmentPreparationData {
  let retained = @decode.admission_preparation_data(original.root)
  {
    members: original.members.to_int64(),
    max_fields: contracts.carriers.preparation_max_fields.to_int64(),
    max_name_utf16: retained.max_key_utf16.to_int64(),
    inspection_work: 0L,
  }
}
