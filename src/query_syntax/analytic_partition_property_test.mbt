///|
test "analytic partition properties retain path tokens and exact source origins" {
  let text = "SELECT ROW_NUMBER() OVER (PARTITION BY t.payload.`bucket` ORDER BY id) AS pos FROM objects AS t"
  let query = parse_query(text, query_limits(), source_path="partition.sql").unwrap()
  match operation_at(query, 0) {
    Some(Analytic(projections)) => {
      let partition = projections[0].analytic.unwrap().window.partition_by[0]
      let node = expression_node(partition, expression_root(partition)).unwrap()
      assert_eq(
        node.kind,
        Reference([
          { value: "t", quoted: false, },
          { value: "payload", quoted: false, },
          { value: "bucket", quoted: true, },
        ]),
      )
      assert_eq(node.start, 39)
      assert_eq(node.end, 57)
      let span = @origin.span(expression_origin(partition, 0).unwrap())
      assert_eq(span.source_path, "partition.sql")
      assert_eq(span.start_column, 40)
      assert_eq(span.end_column, 58)
    }
    _ => fail("partition key must retain the source expression owner")
  }
}
