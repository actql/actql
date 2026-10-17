///|
test "project model registry keeps exact Quickstart task provider and original bytes" {
  let wire = (
    #|{ "version":"actql-model-tasks/0.1", "tasks":{"model-task:churn-risk.v1":"./model-tasks/churn-risk.v1.yaml"}, "providers":{"openai":{"type":"openai","api_key_env":"OPENAI_API_KEY"}}, "default_provider":"openai" }
  )
  let registry = admit_client_project_model_registry(wire).unwrap()
  assert_eq(registry.original_wire(), wire)
  assert_eq(registry.task_count(), 1)
  assert_eq(
    registry.task_at(0),
    Some(("model-task:churn-risk.v1", "./model-tasks/churn-risk.v1.yaml")),
  )
  assert_eq(registry.provider_count(), 1)
  assert_eq(
    registry.provider_at(0),
    Some(("openai", "openai", Some("OPENAI_API_KEY"))),
  )
  assert_eq(registry.selected_default_provider(), Some("openai"))
  assert_eq(registry.task_at(-1), None)
  assert_eq(registry.task_at(1), None)
  assert_eq(registry.provider_at(-1), None)
  assert_eq(registry.provider_at(1), None)
}

///|
test "project registry keeps declaration order paths and unselected implementations without authority" {
  let registry = admit_client_project_model_registry(
    (
      #|{"version":"actql-model-tasks/0.1","tasks":{"z":"../z.yaml","a":"a.json"},"providers":{"second":{"type":"future-installed-type"},"first":{"type":"openai","api_key_env":"KEY"}}}
    ),
  ).unwrap()
  assert_eq(registry.task_at(0), Some(("z", "../z.yaml")))
  assert_eq(registry.task_at(1), Some(("a", "a.json")))
  assert_eq(registry.provider_at(0), Some(("second", "future-installed-type", None)))
  assert_eq(registry.provider_at(1), Some(("first", "openai", Some("KEY"))))
  assert_eq(registry.selected_default_provider(), None)
  // Nonempty DATA must not become a source-free/no-model execution profile.
  assert_true(
    admit_client_source_free_project_bindings(None, Some(registry.original_wire()))
    is Err(BindingsUnavailable),
  )
}

///|
test "project model registry admits empty declarations but never an unresolved default" {
  let registry = admit_client_project_model_registry(
    "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{}}",
  ).unwrap()
  assert_eq(registry.task_count(), 0)
  assert_eq(registry.provider_count(), 0)
  assert_eq(registry.selected_default_provider(), None)
  assert_true(
    admit_client_project_model_registry(
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"default_provider\":\"missing\"}",
    )
    is Err(InvalidBindings),
  )
}

///|
test "project registries retain independent original choices without replacing prior snapshots" {
  let first = admit_client_project_model_registry(
    (
      #|{"version":"actql-model-tasks/0.1","tasks":{"model-task:risk.v1":"old.yaml"},"providers":{"first":{"type":"openai","api_key_env":"FIRST_KEY"}},"default_provider":"first"}
    ),
  ).unwrap()
  let second = admit_client_project_model_registry(
    (
      #|{"version":"actql-model-tasks/0.1","tasks":{"model-task:risk.v1":"new.yaml"},"providers":{"second":{"type":"anthropic","api_key_env":"SECOND_KEY"}},"default_provider":"second"}
    ),
  ).unwrap()
  assert_eq(first.task_at(0), Some(("model-task:risk.v1", "old.yaml")))
  assert_eq(second.task_at(0), Some(("model-task:risk.v1", "new.yaml")))
  assert_eq(first.selected_default_provider(), Some("first"))
  assert_eq(second.selected_default_provider(), Some("second"))
  assert_true(first.original_wire() != second.original_wire())
  // A selector/name in one registry must not resolve the other's provider.
  assert_true(
    admit_client_project_model_registry(
      (
        #|{"version":"actql-model-tasks/0.1","tasks":{},"providers":{"second":{"type":"anthropic"}},"default_provider":"first"}
      ),
    )
    is Err(InvalidBindings),
  )
}

///|
test "project registry rejects malformed unused entries and credential or authority substitution" {
  for
    body in [
      "{}", "null", "[]", "{\"type\":null}", "{\"type\":\"\"}", "{\"type\":\"openai\",\"api_key_env\":null}",
      "{\"type\":\"openai\",\"api_key_env\":\"\"}", "{\"type\":\"openai\",\"api_key\":\"not-a-secret\"}",
      "{\"type\":\"openai\",\"allow\":true}", "{\"type\":\"openai\",\"account_config\":{}}",
    ] {
    assert_true(
      admit_client_project_model_registry(
        "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{\"unused\":" +
        body +
        "}}",
      )
      is Err(InvalidBindings),
    )
  }
  for value in ["null", "false", "1", "{}", "[]", "\"\"", "\"x\\u0000y\""] {
    assert_true(
      admit_client_project_model_registry(
        "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{\"unused\":" +
        value +
        "},\"providers\":{}}",
      )
      is Err(InvalidBindings),
    )
  }
}

///|
test "project registry rejects duplicate declarations null maps and trailing or oversized input" {
  for
    wire in [
      "{}", "null", "[]", "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":null,\"providers\":{}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":[]}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"default_provider\":null}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"extra\":false}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{\"a\":\"a\",\"a\":\"b\"},\"providers\":{}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{\"p\":{\"type\":\"x\",\"type\":\"y\"}}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{},\"providers\":{}}",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{},\"providers\":{}}x",
      " ".repeat(65537),
    ] {
    assert_true(admit_client_project_model_registry(wire) is Err(InvalidBindings))
  }
}
