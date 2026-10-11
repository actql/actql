///|
test "Unicode scalar calls retain unary trees and normalize octet alias" {
  for
    (name, tag) in [
      ("byte_length", "byte_length"),
      ("octet_length", "byte_length"),
      ("unicode", "unicode"),
      ("chr", "chr"),
    ] {
    assert_tree(name + "(value)", "{\"" + tag + "\":{\"field\":\"value\"}}")
    for args in ["", "1,2", "NULL,1"] {
      assert_true(parse(name + "(" + args + ")", test_limits()) is Err(_))
    }
  }
  assert_tree(
    "chr(unicode('😀'))", "{\"chr\":{\"unicode\":{\"literal\":\"😀\"}}}",
  )
}
