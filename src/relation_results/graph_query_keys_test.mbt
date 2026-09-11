///|
test "Graph query identity completes Result order after projection" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"degree\":{\"direction\":\"both\"}},{\"select\":[{\"id\":\"node\"}],\"as\":\"out\"}]",
    ),
    [("g", graph)],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let r = @relation_results.check(
    p,
    cursor(
      "{\"out\":{\"from\":\"out\",\"fields\":[\"id\"],\"order_by\":[{\"id\":\"asc\"}]}}",
    ),
    limits(),
  ).unwrap()
  let order = resolve(r)
  let key = @relation_results.publication_key(order).unwrap()
  assert_eq(@evidence.key_origin(key), GraphQueryResult)
  assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("id"))
  assert_true(
    @evidence.key_graph_query_producer(key) is Some(GraphOperation(_)),
  )
  assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
}
