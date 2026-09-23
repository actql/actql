///|
fn effect_program(replacement : String) -> Program raise {
  parsed(
    source().replace(old="    create: {create: {}}", new=replacement),
    format=Yaml,
  )
}

///|
fn effect_header_error(program : Program) -> EffectHeaderIssueKind raise {
  match collect_effect_headers(program, 16, 16) {
    Err(issue) => effect_header_issue_kind(issue)
    Ok(_) => fail("expected Effect header rejection")
  }
}

///|
test "Effect headers preserve every source occurrence and local policy" {
  let declarations =
    #|    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}, max_items: {$param: cap}}}
    #|    update: {update: {target: crm, mapping: mapping:crm.update.v1, from: {result: rows}, id: record_id, set: {state: {literal: ready}}, on_item_failure: continue}}
    #|    upsert: {upsert: {target: crm, mapping: mapping:crm.upsert.v1, from: {result: rows}, key: external_id, set: {state: {field: state}}}}
    #|    delete: {delete: {target: crm, mapping: mapping:crm.delete.v1, ids: [one]}}
    #|    command: {command: {from: {result: rows}, target: {field: resource}, contract: command:crm.invoke.v1, input: {}}}
    #|    store: {store: {target: crm, mapping: mapping:crm.store.v1, from: {result: rows}}}
  let program = effect_program(declarations)
  let inventory = collect_effect_headers(program, 6, 8).unwrap()
  assert_eq(effect_header_count(inventory), 6)
  assert_eq(effect_headers_work(inventory), 8)
  let first = effect_header_at(inventory, 0).unwrap()
  assert_eq(effect_header_stage(first), 0)
  assert_eq(effect_header_id(first), "create")
  assert_eq(effect_header_kind(first), "create")
  assert_eq(effect_header_source_result(first), None)
  assert_eq(effect_header_failure_policy(first), "halt")
  let second = effect_header_at(inventory, 1).unwrap()
  assert_eq(effect_header_id(second), "update")
  assert_eq(effect_header_source_result(second), Some("rows"))
  assert_eq(effect_header_failure_policy(second), "continue")
  assert_eq(effect_header_contract_ref(second), "mapping:crm.update.v1")
  assert_eq(effect_header_id(effect_header_at(inventory, 5).unwrap()), "store")
  assert_true(effect_header_at(inventory, 6) is None)
}

///|
test "Effect header collection is bounded before retaining another member" {
  let declarations =
    #|    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}}
    #|    update: {update: {target: crm, mapping: mapping:crm.update.v1, ids: [one], set: {state: {literal: ready}}}}
  let program = effect_program(declarations)
  assert_eq(
    effect_header_issue_kind(collect_effect_headers(program, 1, 3).unwrap_err()),
    BudgetExceeded,
  )
  assert_eq(
    effect_header_issue_kind(collect_effect_headers(program, 2, 1).unwrap_err()),
    BudgetExceeded,
  )
  let metadata = effect_program(
    "    create: {meta: {note: present}, create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}}",
  )
  assert_eq(
    effect_header_issue_kind(
      collect_effect_headers(metadata, 1, 1).unwrap_err(),
    ),
    BudgetExceeded,
  )
  assert_eq(
    effect_headers_work(collect_effect_headers(metadata, 1, 2).unwrap()),
    2,
  )
}

///|
test "Effect member identity retains its exact Stage occurrence" {
  let first = effect_program(
    "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}}",
  )
  let program = parsed(
    source()
    .replace(
      old="    create: {create: {}}",
      new="    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}}",
    )
    .replace(
      old="    children: {from: parents}",
      new="    children: {from: parents}\n  effects:\n    create: {create: {target: crm, mapping: mapping:crm.create.v1, from: {result: children}}}",
    ),
    format=Yaml,
  )
  assert_eq(
    effect_header_count(collect_effect_headers(first, 2, 2).unwrap()),
    1,
  )
  let inventory = collect_effect_headers(program, 2, 2).unwrap()
  assert_eq(effect_header_count(inventory), 2)
  assert_eq(effect_header_stage(effect_header_at(inventory, 0).unwrap()), 0)
  let second = effect_header_at(inventory, 1).unwrap()
  assert_eq(effect_header_stage(second), 1)
  assert_eq(effect_header_id(second), "create")
  assert_eq(effect_header_source_result(second), Some("children"))
}

///|
test "Effect headers reject malformed alternatives without granting execution" {
  let valid = "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}}"
  let null_literal = effect_program(
    "    create: {update: {target: crm, mapping: mapping:crm.update.v1, ids: [one], set: {state: {literal: null}}}}",
  )
  assert_eq(
    effect_header_count(collect_effect_headers(null_literal, 1, 2).unwrap()),
    1,
  )
  assert_eq(
    effect_header_issue_kind(
      collect_effect_headers(null_literal, 1, 1).unwrap_err(),
    ),
    BudgetExceeded,
  )
  let cases : Array[(String, EffectHeaderIssueKind)] = [
    (
      "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}, from: {result: rows}}}",
      InvalidSourceResult,
    ),
    (
      "    create: {create: {target: crm, mapping: mapping:crm.create.v1, from: {result: absent}}}",
      InvalidSourceResult,
    ),
    (
      "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}, on_item_failure: halt}}",
      InvalidFailurePolicy,
    ),
    (
      "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}, max_items: 0}}",
      InvalidMaxItems,
    ),
    (
      "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}, max_items: {$param: ''}}}",
      InvalidMaxItems,
    ),
    (
      "    create: {create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}, update: {}}",
      InvalidKind,
    ),
    (
      "    create: {meta: {actql_hidden: true}, create: {target: crm, mapping: mapping:crm.create.v1, payload: {}}}",
      InvalidDeclaration,
    ),
    (
      "    create: {update: {target: crm, mapping: mapping:crm.update.v1, ids: [one], set: {state: ready}}}",
      InvalidBody,
    ),
    (
      "    create: {update: {target: crm, mapping: mapping:crm.update.v1, ids: [one], set: {state: {literal: ready, field: source}}}}",
      InvalidBody,
    ),
    (
      "    create: {update: {target: crm, mapping: mapping:crm.update.v1, ids: [one], set: {state: {field: source}}}}",
      InvalidSourceResult,
    ),
    (
      "    create: {command: {from: {result: rows}, target: {field: resource}, contract: command:crm.invoke.v1, input: {value: true}}}",
      InvalidBody,
    ),
  ]
  assert_eq(
    effect_header_issue_kind(
      collect_effect_headers(effect_program(valid), -1, 1).unwrap_err(),
    ),
    InvalidLimits,
  )
  for (effect, expected) in cases {
    assert_eq(effect_header_error(effect_program(effect)), expected)
  }
}
