///|
// Private data-only bridge to the existing Common reader. These handles do
// not restore a Ledger or issue current-cut, capture, read or send authority.
#export_name("clientProgramReadModelOriginalResourceDocument")
pub fn client_program_read_model_original_resource_document(
  wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.ModelOriginalResourceDocument,
  @publication.PublicationContractIssue,
] {
  @publication.read_model_original_resource_document(
    wire, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramModelOriginalResourceOriginField")
pub fn client_program_model_original_resource_origin_field(
  document : @publication.ModelOriginalResourceDocument,
  field : String,
) -> String? {
  @publication.model_original_resource_origin_field(document, field)
}

///|
/// Existing private artifact DATA only; no custody/current-cut authority.
#export_name("clientProgramEncodeModelOriginalResourceDocument")
pub fn client_program_encode_model_original_resource_document(
  origin_wire : String,
  state_wire : String,
  cut_wire : String,
  phase : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication.PublicationContractIssue] {
  @publication.encode_model_original_resource_document(
    origin_wire, state_wire, cut_wire, phase, max_bytes, max_nodes, max_depth,
  )
}
