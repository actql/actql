///|
/// Observations of the SAME already prepared serializer, not another schema
/// parser, receipt or capacity. Traversal frames are construction scratch.
pub(all) struct ResultDeliverySerializerExtent {
  schema : @json.CanonicalRepresentationExtent
  field_backing_slots : Int64
  field_text_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn result_delivery_serializer_extent(
  serializer : ResultDeliverySerializer,
) -> Result[ResultDeliverySerializerExtent, DeliverySerializationIssue] {
  let schema = match
    @json.representation_extent(
      serializer.schema,
      serializer.max_nodes,
      serializer.max_depth,
      serializer.max_wire_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(DeliverySerializationInvalidSchema)
  }
  let mut text = serializer.format.length().to_int64()
  for field in serializer.fields {
    text += field.length().to_int64()
  }
  Ok({
    schema,
    field_backing_slots: serializer.fields.capacity().to_int64(),
    field_text_utf16_units: text,
  })
}
