///|
test "reshaped columns flow into Result projection and ordering without proving publication" {
  let row = @contract.read_author(
    cursor(
      "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"p\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}}}",
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 10000, },
  ).unwrap()
  let p = @pipeline.check(
    cursor(
      "[{\"json_pick\":{\"column\":\"p\",\"path\":[\"items\"],\"output\":\"items\"}},{\"unnest\":{\"column\":\"items\",\"as\":\"v\",\"with_index\":true,\"outer\":true},\"as\":\"expanded\"}]",
    ),
    [("rows", @schema.from_object(row).unwrap())],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_nodes: 1000,
      max_tokens: 0,
      max_text_bytes: 10000,
      max_depth: 20,
    },
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"expanded\",\"fields\":[\"v\",\"v_index\"],\"order_by\":[{\"v_index\":\"asc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let result = @relation_results.lookup(results, "out").unwrap()
  assert_eq(@relation_results.fields(result), ["v", "v_index"])
  assert_true(
    @schema.lookup(@relation_results.output_schema(result), Unqualified("v")).unwrap().nullable,
  )
  assert_true(!@relation_results.pending_validations(result).is_empty())
}
