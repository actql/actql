///|
// These are the public Slack predicate's original logical contracts. The
// literal is authored numeric syntax, never a re-labelled Text/Decimal value.
test "public Slack reply-count predicate admits its exact integer zero" {
  assert_type(
    "{\"and\":[{\"is_null\":{\"field\":\"thread_ts\"}},{\"eq\":[{\"field\":\"reply_count\"},{\"literal\":0}]}]}",
    "{\"thread_ts\":{\"type\":\"string\",\"nullable\":true},\"reply_count\":{\"type\":\"int64\",\"nullable\":true}}",
    "null", "{\"type\":\"boolean\",\"nullable\":true}",
  )
}

///|
test "existing int64 contracts use their exact author-orderable comparison" {
  assert_type(
    "{\"lt\":[{\"field\":\"a\"},{\"field\":\"b\"}]}", "{\"a\":{\"type\":\"int64\",\"nullable\":false},\"b\":{\"type\":\"int64\",\"nullable\":false}}",
    "null", "{\"type\":\"boolean\",\"nullable\":false}",
  )
}
