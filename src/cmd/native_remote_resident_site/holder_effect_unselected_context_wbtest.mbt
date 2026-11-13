///|
/// Production decision seam with authored ports. These counters prove skipped
/// context work and exact value forwarding, not physical cleanup or authority.
test "unselected holder operator builds no original contexts and leaves exact release routing available" {
  let contexts = Ref(0)
  let decisions = Ref(0)
  let absent : Ref[Int]? = None
  for _ in 0..<3 {
    assert_false(
      holder_effect_installed_evidence(
        () => absent,
        () => {
          contexts.val += 1
          Some(Ref(1))
        },
        (_, _) => {
          decisions.val += 1
          true
        },
      ),
    )
  }
  assert_eq(contexts.val, 0)
  assert_eq(decisions.val, 0)
  let request = holder_custody_test_request("consumer", "unselected-release")
  let task = new_holder_task_custody(request, None, None, None)
  let identity = @remote.dispatch_request_identity(request)
  let tasks : Map[String, HolderTaskCustody] = Map([(identity, task)])
  let routed = Ref(0)
  let same_task = Ref(false)
  assert_true(
    handle_holder_release_frame(tasks, [identity], identity, original => {
      same_task.val = physical_equal(original, task)
      routed.val += 1
    }),
  )
  assert_eq(routed.val, 1)
  assert_true(same_task.val)
  assert_true(task.release_requested)
  assert_false(task.released)
}

///|
test "selected holder operator forwards original context through the existing current authorization decision" {
  let installed = Ref(1)
  let original = Ref(2)
  let contexts = Ref(0)
  let decisions = Ref(0)
  let forwarded = Ref(false)
  assert_true(
    holder_effect_installed_evidence(
      () => Some(installed),
      () => {
        contexts.val += 1
        Some(original)
      },
      (same_installation, same_original) => {
        forwarded.val = physical_equal(same_installation, installed) &&
          physical_equal(same_original, original)
        holder_effect_current_decision(
          evidence_subject(),
          "sha256:" + "a".repeat(64),
          Read,
          _ => {
            decisions.val += 1
            Some({
              configuration: evidence_account(),
              delegated_action: None,
              current: () => true,
            })
          },
          current_original=() => physical_equal(same_original, original),
        )
      },
    ),
  )
  assert_eq(contexts.val, 1)
  assert_eq(decisions.val, 1)
  assert_true(forwarded.val)
}

///|
test "selected holder operator preserves missing foreign and revoked context refusals without retry" {
  let installed = Ref(1)
  let original = Ref(2)
  let contexts = Ref(0)
  let decisions = Ref(0)
  let missing : Ref[Int]? = None
  assert_false(
    holder_effect_installed_evidence(
      () => Some(installed),
      () => {
        contexts.val += 1
        missing
      },
      (_, _) => {
        decisions.val += 1
        true
      },
    ),
  )
  assert_eq(contexts.val, 1)
  assert_eq(decisions.val, 0)
  for foreign in [false, true] {
    let current = Ref(true)
    let observed = if foreign { Ref(2) } else { original }
    assert_false(
      holder_effect_installed_evidence(
        () => Some(installed),
        () => {
          contexts.val += 1
          Some(observed)
        },
        (_, same_original) => {
          holder_effect_current_decision(
            evidence_subject(),
            "sha256:" + "a".repeat(64),
            Read,
            _ => {
              decisions.val += 1
              if !foreign {
                current.val = false
              }
              Some({
                configuration: evidence_account(),
                delegated_action: None,
                current: () => current.val,
              })
            },
            current_original=() => physical_equal(same_original, original),
          )
        },
      ),
    )
  }
  assert_eq(contexts.val, 3)
  assert_eq(decisions.val, 2)
}

///|
test "holder operator retirement during original context work still refuses at the existing selection fence" {
  let operator = Ref(Some(Ref(1)))
  let selections = Ref(0)
  let contexts = Ref(0)
  let decisions = Ref(0)
  assert_false(
    holder_effect_installed_evidence(
      () => {
        selections.val += 1
        operator.val
      },
      () => {
        contexts.val += 1
        operator.val = None
        Some(Ref(2))
      },
      (_, _) => {
        decisions.val += 1
        true
      },
    ),
  )
  assert_eq(selections.val, 2)
  assert_eq(contexts.val, 1)
  assert_eq(decisions.val, 0)
}
