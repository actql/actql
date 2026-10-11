///|
test "translate instr canonical arrays preserve omission and reject alternate shapes" {
  assert_tree(
    "\"translate(s,source,target)\"", "{\"translate\":[{\"field\":\"s\"},{\"field\":\"source\"},{\"field\":\"target\"}]}",
  )
  assert_tree(
    "{\"translate\":[{\"field\":\"s\"},{\"field\":\"source\"},{\"field\":\"target\"}]}",
    "{\"translate\":[{\"field\":\"s\"},{\"field\":\"source\"},{\"field\":\"target\"}]}",
  )
  assert_tree(
    "\"instr(s,t)\"", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"}]}",
  )
  assert_tree(
    "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"}]}", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"}]}",
  )
  assert_tree(
    "\"instr(s,t,p)\"", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"}]}",
  )
  assert_tree(
    "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"}]}", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"}]}",
  )
  assert_tree(
    "\"instr(s,t,p,o)\"", "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"},{\"field\":\"o\"}]}",
  )
  assert_tree(
    "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"},{\"field\":\"o\"}]}",
    "{\"instr\":[{\"field\":\"s\"},{\"field\":\"t\"},{\"field\":\"p\"},{\"field\":\"o\"}]}",
  )
  assert_true(
    admit(source_cursor("{\"translate\":[]}"), test_limits()) is Err(_),
  )
  assert_true(
    admit(source_cursor("{\"translate\":[{\"literal\":\"s\"}]}"), test_limits())
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor("{\"translate\":[{\"literal\":\"s\"},{\"literal\":\"a\"}]}"),
      test_limits(),
    )
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor(
        "{\"translate\":[{\"literal\":\"s\"},{\"literal\":\"a\"},{\"literal\":\"b\"},{\"literal\":\"c\"}]}",
      ),
      test_limits(),
    )
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor(
        "{\"translate\":{\"value\":{\"literal\":\"s\"},\"source\":{\"literal\":\"a\"},\"target\":{\"literal\":\"b\"}}}",
      ),
      test_limits(),
    )
    is Err(_),
  )
  assert_true(admit(source_cursor("{\"instr\":[]}"), test_limits()) is Err(_))
  assert_true(
    admit(source_cursor("{\"instr\":[{\"literal\":\"a\"}]}"), test_limits())
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor(
        "{\"instr\":[{\"literal\":\"a\"},{\"literal\":\"b\"},{\"literal\":1},{\"literal\":1},{\"literal\":1}]}",
      ),
      test_limits(),
    )
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor(
        "{\"instr\":{\"value\":{\"literal\":\"s\"},\"subvalue\":{\"literal\":\"a\"}}}",
      ),
      test_limits(),
    )
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor(
        "{\"TRANSLATE\":[{\"literal\":\"a\"},{\"literal\":\"a\"},{\"literal\":\"b\"}]}",
      ),
      test_limits(),
    )
    is Err(_),
  )
  assert_true(
    admit(
      source_cursor("{\"INSTR\":[{\"literal\":\"a\"},{\"literal\":\"b\"}]}"),
      test_limits(),
    )
    is Err(_),
  )
}
