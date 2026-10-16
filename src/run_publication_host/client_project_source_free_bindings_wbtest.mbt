///|
let empty_project_connectors = "{\"version\":\"actql-connectors/0.1\",\"connections\":{}}"

///|
let empty_project_model_tasks = "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{}}"

///|
test "plain project declaration admission preserves each actual selected file fact" {
  for connectors in [None, Some(empty_project_connectors)] {
    for model_tasks in [None, Some(empty_project_model_tasks)] {
      let admitted = admit_client_source_free_project_bindings(
        connectors, model_tasks,
      ).unwrap()
      assert_eq(admitted.has_connectors_file(), connectors is Some(_))
      assert_eq(admitted.has_model_tasks_file(), model_tasks is Some(_))
    }
  }
}

///|
test "nonempty connector declarations are unavailable rather than ignored source-free inventory" {
  let original = "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"salesforce\":{\"connector\":\"salesforce\"}}}"
  assert_true(
    admit_client_source_free_project_bindings(
      Some(original),
      Some(empty_project_model_tasks),
    )
    is Err(BindingsUnavailable),
  )
}

///|
test "tasks providers and selected default provider never silently become a no-model profile" {
  for
    selected in [
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{\"t\":\"task.yaml\"},\"providers\":{}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{\"p\":{\"type\":\"openai\"}}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"default_provider\":\"p\"}",
    ] {
    assert_true(
      admit_client_source_free_project_bindings(
        Some(empty_project_connectors),
        Some(selected),
      )
      is Err(BindingsUnavailable),
    )
  }
}

///|
test "empty declarations remain closed required versioned objects" {
  for
    bad in [
      "{}", "null", "[]", "{\"version\":\"unsupported\",\"connections\":{}}", "{\"version\":\"actql-connectors/0.1\"}",
      "{\"version\":\"actql-connectors/0.1\",\"connections\":null}", "{\"version\":\"actql-connectors/0.1\",\"connections\":[],\"extra\":true}",
    ] {
    assert_true(
      admit_client_source_free_project_bindings(Some(bad), None)
      is Err(InvalidBindings),
    )
  }
  for
    bad in [
      "{}", "null", "[]", "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":null}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"default_provider\":null}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"extra\":true}",
    ] {
    assert_true(
      admit_client_source_free_project_bindings(None, Some(bad))
      is Err(InvalidBindings),
    )
  }
}

///|
test "duplicate declarations cannot be hidden by empty selected projections" {
  assert_true(
    admit_client_source_free_project_bindings(
      Some(
        "{\"version\":\"actql-connectors/0.1\",\"connections\":{\"x\":{},\"x\":{}},\"connections\":{}}",
      ),
      None,
    )
    is Err(InvalidBindings),
  )
  assert_true(
    admit_client_source_free_project_bindings(
      None,
      Some(
        "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"providers\":{}}",
      ),
    )
    is Err(InvalidBindings),
  )
}

///|
test "malformed or oversized declaration bytes never produce source-free facts" {
  assert_true(
    admit_client_source_free_project_bindings(
      Some(empty_project_connectors + "x"),
      None,
    )
    is Err(InvalidBindings),
  )
  assert_true(
    admit_client_source_free_project_bindings(None, Some(" ".repeat(65537)))
    is Err(InvalidBindings),
  )
  assert_true(
    admit_client_source_free_project_bindings(
      Some("[".repeat(17) + "]".repeat(17)),
      None,
    )
    is Err(InvalidBindings),
  )
}
