///|
// Authored ports exercise the private synchronous projection only. These
// metadata records are not filesystem originals or an operational supplier.
fn runtime_frame_selected(name : String) -> NativeLocalSelectedFile {
  let body = @utf8.encode(name)
  {
    name,
    generation: { device: 1, inode: 2, size: body.length().to_int64(), },
    body,
    content_cid: "sha256:" + "a".repeat(64),
  }
}

///|
test "Runtime frame reuses its exact scope read tuple and three selected originals" {
  let scopes = Ref(0)
  let decisions = Ref(0)
  let selections = Ref(0)
  let polls = Ref(0)
  let originals = ["environment.json", "run.json", "runtime.json"].map(
    runtime_frame_selected,
  )
  let source : NativeLocalRuntimeBindingAccess = {
    scope: (principal, connection) => {
      scopes.val += 1
      Ok(principal + "/" + connection)
    },
    read_allowed: (principal, connection) => {
      decisions.val += 1
      principal == "operator" && connection == "cli"
    },
    selected: name => {
      selections.val += 1
      match originals.iter().find_first(file => file.name == name) {
        Some(file) => Ok(file)
        None => Err(CustodyLost)
      }
    },
  }
  let checks = with_local_runtime_binding_frame(
    source,
    () => {
      polls.val += 1
      true
    },
    access => {
      let checks : Array[Bool] = []
      for _ in 0..<3 {
        checks.push(
          (access.scope)("operator", "cli") is Ok(scope) &&
          scope == "operator/cli",
        )
      }
      checks.push((access.read_allowed)("operator", "cli"))
      checks.push((access.read_allowed)("operator", "cli"))
      for _ in 0..<2 {
        for original in originals {
          checks.push(
            (access.selected)(original.name) is Ok(selected) &&
            selected.name == original.name &&
            selected.generation == original.generation &&
            selected.body == original.body &&
            selected.content_cid == original.content_cid,
          )
        }
      }
      checks
    },
  )
  assert_eq(checks, Array::make(11, true))
  assert_eq(scopes.val, 1)
  assert_eq(decisions.val, 1)
  assert_eq(selections.val, 3)
  assert_eq(polls.val, 11)
}

///|
test "Runtime frame cannot export an Allow to another tuple or the next operation" {
  let allowed = Ref(true)
  let calls = Ref(0)
  let source : NativeLocalRuntimeBindingAccess = {
    scope: (_, _) => Ok("scope"),
    read_allowed: (principal, connection) => {
      calls.val += 1
      allowed.val && principal == "operator" && connection == "cli"
    },
    selected: _ => Err(CustodyLost),
  }
  let (checks, escaped) = with_local_runtime_binding_frame(source, () => true, access => {
    (
      [
        (access.read_allowed)("operator", "cli"),
        (access.read_allowed)("operator", "cli"),
        !(access.read_allowed)("foreign", "cli"),
        !(access.read_allowed)("foreign", "cli"),
      ],
      access,
    )
  })
  assert_eq(checks, Array::make(4, true))
  assert_eq(calls.val, 2)
  assert_false((escaped.read_allowed)("operator", "cli"))
  assert_true((escaped.scope)("operator", "cli") is Err(CustodyLost))
  assert_true((escaped.selected)("runtime.json") is Err(CustodyLost))
  assert_eq(calls.val, 2)
  allowed.val = false
  let denied = with_local_runtime_binding_frame(source, () => true, access => {
    [
      (access.read_allowed)("operator", "cli"),
      (access.read_allowed)("operator", "cli"),
    ]
  })
  assert_eq(denied, [false, false])
  assert_eq(calls.val, 3)
}

///|
test "Runtime frame loses all retained facts on current failure and does not revive" {
  let current = Ref(true)
  let scopes = Ref(0)
  let decisions = Ref(0)
  let selections = Ref(0)
  let source : NativeLocalRuntimeBindingAccess = {
    scope: (_, _) => {
      scopes.val += 1
      Err(Encoding)
    },
    read_allowed: (_, _) => {
      decisions.val += 1
      true
    },
    selected: _ => {
      selections.val += 1
      Err(CustodyLost)
    },
  }
  let checks = with_local_runtime_binding_frame(source, () => current.val, access => {
    let checks : Array[Bool] = []
    // Failed immutable admissions are retained too; no second acquisition or
    // implicit retry is hidden behind the pure comparison loop.
    checks.push((access.scope)("operator", "cli") is Err(Encoding))
    checks.push((access.scope)("operator", "cli") is Err(Encoding))
    checks.push((access.read_allowed)("operator", "cli"))
    checks.push((access.selected)("missing") is Err(CustodyLost))
    checks.push((access.selected)("missing") is Err(CustodyLost))
    current.val = false
    checks.push((access.scope)("operator", "cli") is Err(CustodyLost))
    checks.push(!(access.read_allowed)("operator", "cli"))
    checks.push((access.selected)("missing") is Err(CustodyLost))
    current.val = true
    checks.push(!(access.read_allowed)("operator", "cli"))
    checks
  })
  assert_eq(checks, Array::make(9, true))
  assert_eq(scopes.val, 1)
  assert_eq(decisions.val, 1)
  assert_eq(selections.val, 1)
}
