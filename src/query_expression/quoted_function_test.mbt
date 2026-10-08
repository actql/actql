///|
test "quoted installed scalar names use the decoded name and existing expressions" {
  for
    (text, expected) in [
      ("`IFNULL`(NULL, 7)", "{\"coalesce\":[{\"literal\":null},{\"literal\":7}]}"),
      ("`iFnUlL`(NULL, 7)", "{\"coalesce\":[{\"literal\":null},{\"literal\":7}]}"),
      ("`\\x49FNULL`(NULL, 7)", "{\"coalesce\":[{\"literal\":null},{\"literal\":7}]}"),
      ("`IF`(TRUE, 1, 1 / 0)", "{\"if\":[{\"literal\":true},{\"literal\":1},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}"),
      ("`CONCAT`('a', NULL)", "{\"concat_strict\":[{\"literal\":\"a\"},{\"literal\":null}]}"),
      ("`CHAR_LENGTH`('abc')", "{\"len\":{\"literal\":\"abc\"}}"),
      ("`CEIL`(x)", "{\"negate\":{\"floor\":{\"subtract\":[{\"literal\":0},{\"field\":\"x\"}]}}}"),
      ("`ACTQL`.`CONCAT`('a', NULL)", "{\"concat\":[{\"literal\":\"a\"},{\"literal\":null}]}"),
    ] {
    assert_eq(emit(text), expected)
  }
}

///|
test "quotation grants neither a new function namespace nor different arity" {
  for
    text in ["`IFNULL`(1)", "`IFNULL`(1, 2, 3)", "`CHAR_LENGTH`()"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  for
    text in [
      "`UNKNOWN`(1)", "`ACTQL`.`IFNULL`(1, 2)", "`SAFE`.`IFNULL`(1, 2)",
      "`ACTQL.CONCAT`('a', 'b')",
    ] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
      msg=text,
    )
  }
}
