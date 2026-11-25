///|
fn generated_jsonl_test_input() -> (
  @publication.ContentByteEncoder,
  Array[@admitted.CheckedValue],
) {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let schema = @schema.from_presence_fields(
    [(@schema.Unqualified("id"), number, @schema.Required)],
    max_fields=1,
    max_name_bytes=64,
  ).unwrap()
  let profile = @publication.prepare_content_serialization_profile(
    ContentJsonl,
    schema,
    ["id"],
    "{\"name\":\"two.jsonl\"}",
    {
      max_fields: 1,
      max_name_bytes: 64,
      max_work: 1000,
      max_options_bytes: 128,
      max_options_nodes: 16,
      max_options_depth: 4,
    },
  ).unwrap()
  let encoder = @publication.start_content_byte_encoder(
    profile,
    max_rows=2,
    max_bytes=64,
    max_value_nodes=16,
    max_value_depth=4,
    max_frames=16,
  ).unwrap()
  let rows = [1.0, 2.0].map(id => {
    @admitted.checked_number_value(id, number).unwrap()
  })
  @publication.bind_content_byte_input(encoder, rows.length(), () => true).unwrap()
  (encoder, rows)
}
