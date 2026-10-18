///|
test "graph property set order retains original UTC wire values and exact finer order" {
  let item = @contract.primitive(TimestampType, nullable=false)
  let contract = @contract.array_contract(item, nullable=false).unwrap()
  let early = "1970-01-01T00:00:00.123Z"
  let fine = "1970-01-01T00:00:00.123000001Z"
  let late = "1970-01-01T00:00:00.124Z"
  let left = union_property_test_value(
    contract,
    "[\"" + late + "\",\"" + early + "\",\"" + late + "\"]",
  )
  let right = union_property_test_value(
    contract,
    "[\"" + fine + "\",\"" + early + "\"]",
  )
  for quantum in [1, 64] {
    let (result, _) = union_property_test_finish(
      union_property_test_cursor(
        left,
        Some(right),
        contract,
        @graph_type.UnionSetUnion,
      ),
      quantum,
    )
    assert_eq(
      union_property_test_wire(result),
      "[\"" + early + "\",\"" + fine + "\",\"" + late + "\"]",
    )
    let old = union_property_test_value(
      contract,
      "[\"" + late + "\",\"" + early + "\"]",
    )
    let (result, _) = union_property_test_finish(
      union_property_test_cursor(
        old,
        Some(old),
        contract,
        @graph_type.UnionSetUnion,
      ),
      quantum,
    )
    assert_eq(
      union_property_test_wire(result),
      "[\"" + early + "\",\"" + late + "\"]",
    )
  }
}
