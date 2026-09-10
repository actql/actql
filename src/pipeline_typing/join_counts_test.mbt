///|
test "join and interval join transfer counts from their selected operand occurrences" {
  for temporal in [false, true] {
    for kind in ["inner", "left", "full", "semi", "anti"] {
      if temporal && kind == "full" {
        continue
      }
      for a in [0, 1, 3] {
        for z in [0, 1, 3] {
          let body = if temporal {
            "\"interval_join\":{\"with\":\"right\",\"kind\":\"" +
            kind +
            "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}}"
          } else {
            "\"join\":{\"with\":\"right\",\"kind\":\"" +
            kind +
            "\",\"on\":\"id\"}"
          }
          let p = @pipeline_typing.check_carriers(
            cursor(
              "[" +
              count_values(a, "left") +
              "," +
              count_values(z, "right") +
              ",{" +
              body +
              ",\"from\":\"left\"}]",
            ),
            [],
            None,
            None,
            limits(),
          ).unwrap()
          let upper = match kind {
            "inner" => a * z
            "left" => a * (if z == 0 { 1 } else { z })
            "full" => if a * z > a + z { a * z } else { a + z }
            "semi" => if z == 0 { 0 } else { a }
            _ => a
          }
          let exact = upper == 0 ||
            (kind == "left" && z <= 1) ||
            (kind == "anti" && z == 0) ||
            (kind == "full" && (a == 0 || z == 0))
          assert_count(p, 2, upper.to_int64(), exact)
        }
      }
    }
  }
}
