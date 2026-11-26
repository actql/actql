///|
test "project model registry keeps exact Quickstart task provider and original bytes" {
  let wire =
    #|{ "version":"actql-model-tasks/0.1", "tasks":{"model-task:churn-risk.v1":"./model-tasks/churn-risk.v1.yaml"}, "providers":{"openai":{"type":"openai","api_key_env":"OPENAI_API_KEY"}}, "default_provider":"openai" }
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
  assert_eq(
    registry.provider_at(0),
    Some(("second", "future-installed-type", None)),
  )
  assert_eq(registry.provider_at(1), Some(("first", "openai", Some("KEY"))))
  assert_eq(registry.selected_default_provider(), None)
  // Nonempty DATA must not become a source-free/no-model execution profile.
  assert_true(
    admit_client_source_free_project_bindings(
      None,
      Some(registry.original_wire()),
    )
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
      "{}",
      "null",
      "[]",
      "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":{}}",
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
    assert_true(
      admit_client_project_model_registry(wire) is Err(InvalidBindings),
    )
  }
}

///|
test "funded Project registry refuses one short and retains its original ledger allowance" {
  let wire =
    #|{"version":"actql-model-tasks/0.1","tasks":{"z":"z.yaml","a":"a.json"},"providers":{"mock":{"type":"mock","api_key_env":"KEY"}},"default_provider":"mock"}
  let (expected, _) = client_project_model_registry_admission_inventory(wire).unwrap()
  let amount = @execution.preparation_representation_cost(expected).unwrap()
  let limits : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: amount,
    execution_bytes: amount,
  }
  let short_ledger = @resources.create_ledger({
    ..limits,
    retained_bytes: amount - 1L,
  }).unwrap()
  let refused = admit_funded_client_project_model_registry(
    wire,
    units => {
      let quoted = @execution.preparation_representation_cost(units).unwrap()
      @resources.reserve_capacity(short_ledger, quoted, quoted).map(_ => ())
    },
    _ => @resources.InvalidCharge,
  )
  assert_true(refused is Err(RetentionLimit))
  assert_eq(@resources.ledger_usage(short_ledger).live_reservations, 0)

  let original_ledger = @resources.create_ledger(limits).unwrap()
  let held : Ref[@resources.CapacityReservation?] = Ref(None)
  {
    let original = admit_funded_client_project_model_registry(
      wire,
      units => {
        let quoted = @execution.preparation_representation_cost(units).unwrap()
        @resources.reserve_capacity(original_ledger, quoted, quoted).map(token => {
          held.val = Some(token)
        })
      },
      _ => @resources.InvalidCharge,
    ).unwrap()
    assert_eq(original.original_wire(), wire)
    assert_eq(original.task_at(0), Some(("z", "z.yaml")))
    assert_eq(original.task_at(1), Some(("a", "a.json")))
    assert_eq(original.provider_at(0), Some(("mock", "mock", Some("KEY"))))
    assert_eq(original.selected_default_provider(), Some("mock"))
    assert_true(
      @resources.capacity_reservation_matches(
        original_ledger,
        held.val.unwrap(),
        amount,
        amount,
      ),
    )
  }
  @resources.settle_capacity(original_ledger, held.val.unwrap()).unwrap()
  assert_eq(@resources.ledger_usage(original_ledger).live_reservations, 0)
}

///|
test "funded Project registry keeps original large geometry and exact preparation refusal" {
  let wire = "{\"version\":\"actql-model-tasks/0.1\",\"tasks\":" +
    project_geometry_locators(5000) +
    ",\"providers\":{}}"
  let (units, _) = client_project_model_registry_admission_inventory(wire).unwrap()
  assert_true(units.owned_wire_bytes > 65536L)
  let admitted = Ref(0)
  let original = admit_funded_client_project_model_registry(
    wire,
    observed => {
      if observed != units {
        return Err("different quote")
      }
      admitted.val += 1
      Ok(())
    },
    _ => "binding refusal",
  ).unwrap()
  assert_eq(admitted.val, 1)
  assert_eq(original.task_at(4999), Some(("original-4999", "./original.yaml")))
  assert_eq(original.task_at(5000), None)

  assert_true(
    admit_funded_client_project_model_registry(
      "{\"tasks\":null}",
      _ => Err("original funding refusal"),
      _ => "binding refusal",
    )
    is Err("original funding refusal"),
  )
  assert_true(
    admit_funded_client_project_model_registry(
      "{\"tasks\":null}",
      _ => Ok(()),
      _ => "binding refusal",
    )
    is Err("binding refusal"),
  )
}

///|
test "funded Project registry returns only typed parser scratch after successful construction" {
  let wire =
    #|{"version":"actql-model-tasks/0.1","tasks":{"z":"z.yaml"},"providers":{"mock":{"type":"mock","api_key_env":"KEY"}},"default_provider":"mock"}
  let (peak, scratch) = client_project_model_registry_admission_inventory(wire).unwrap()
  let amount = @execution.preparation_representation_cost(peak).unwrap()
  assert_true(scratch > 0L && scratch < amount)
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: amount,
    execution_bytes: amount,
  }).unwrap()
  let token : Ref[@resources.CapacityReservation?] = Ref(None)
  let retained = amount - scratch
  let registry = admit_funded_client_project_model_registry(
    wire,
    units => {
      if units != peak {
        return Err(@resources.InvalidCharge)
      }
      @resources.reserve_capacity(ledger, amount, amount).map(capacity => {
        token.val = Some(capacity)
      })
    },
    _ => @resources.InvalidCharge,
    settle=Some(returned => {
      let original = token.val.unwrap()
      if returned != scratch ||
        !@resources.capacity_reservation_matches(
          ledger, original, amount, amount,
        ) {
        return Err(@resources.InvalidCharge)
      }
      @resources.shrink_capacity_reservation(
        ledger, original, retained, retained,
      )
    }),
  ).unwrap()
  assert_eq(registry.original_wire(), wire)
  assert_eq(registry.task_at(0), Some(("z", "z.yaml")))
  assert_eq(registry.provider_at(0), Some(("mock", "mock", Some("KEY"))))
  assert_eq(registry.selected_default_provider(), Some("mock"))
  assert_true(
    @resources.capacity_reservation_matches(
      ledger,
      token.val.unwrap(),
      retained,
      retained,
    ),
  )
  @resources.settle_capacity(ledger, token.val.unwrap()).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)

  assert_true(
    admit_funded_client_project_model_registry(
      "{\"tasks\":null}",
      _ => Ok(()),
      _ => "original registry refusal",
      settle=Some(_ => Err("unexpected registry settlement")),
    )
    is Err("original registry refusal"),
  )
}
