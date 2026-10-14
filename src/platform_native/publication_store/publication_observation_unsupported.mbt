///|
pub fn Store::observe_publication_payload_facts(
  _self : Store,
  _bindings : Array[@publication.PublicationContract],
  _binding_schema_wires : Array[String],
  _max_wire_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}
