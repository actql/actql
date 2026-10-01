-- Consumer-side expected propositions. These declarations independently fix
-- scope and premises; a theorem name or a weakened signature is insufficient.
example (budget : Nat) (t : RelationChain.State)
    (trace : RelationChain.Run (RelationChain.initial budget) t) :
    t.reported = t.childWork + t.handoffWork ∧ t.reported ≤ budget :=
  RelationChain.chain_accounting budget t trace

example (budget : Nat) (t : RelationChain.State)
    (trace : RelationChain.Run (RelationChain.initial budget) t) :
    ∀ id, id < t.started → id ∈ t.owed ∨ id ∈ t.released :=
  RelationChain.chain_responsibility budget t trace

example (s : RelationChain.State) (started : Bool) :
    (RelationChain.handoff s started).used = s.used + 1 ∧
    RelationChain.remaining (RelationChain.handoff s started) = s.budget - (s.used + 1) :=
  RelationChain.handoff_budget_not_reset s started

example (s : RelationChain.State) :
    (RelationChain.handoff s false).owed = s.owed ∧
    (RelationChain.handoff s false).started = s.started ∧
    (RelationChain.handoff s false).computes = s.computes :=
  RelationChain.failed_handoff_keeps_responsibility s

example (s : RelationChain.State) (done : Bool) :
    (RelationChain.cleanup s done).started = s.started ∧
    (RelationChain.cleanup s done).computes = s.computes ∧
    (RelationChain.cleanup s done).reported = s.reported :=
  RelationChain.cleanup_does_not_compute s done

example (s : RelationChain.State) : RelationChain.cleanup s false = s :=
  RelationChain.pending_cleanup_keeps_responsibility s

example (s t : RelationChain.State) (step : RelationChain.Step s t)
    (terminal : s.terminal = true) : t.computes = s.computes ∧ t.started = s.started :=
  RelationChain.terminal_step_no_compute step terminal

example (s : RelationChain.State) :
    (RelationChain.stop s).computes = s.computes ∧
    (RelationChain.stop s).reported = s.reported ∧
    (RelationChain.stop s).owed = s.owed :=
  RelationChain.prompt_stop_does_not_compute s

example (budget : Nat) :
    (RelationChain.stop (RelationChain.initial budget)).terminal = true ∧
    (RelationChain.stop (RelationChain.initial budget)).owed ≠ [] :=
  RelationChain.terminal_is_not_reclaimed budget

example (children : List (List Nat))
    (h : ∀ reports ∈ children, BoundedSession.MonotoneReports 0 reports) :
    (children.map RelationChain.childCost).sum =
    (children.map (BoundedSession.finalWork 0)).sum :=
  RelationChain.finite_children_cost children h

example (s t : RelationChain.State) (trace : RelationChain.Run s t)
    (terminal : s.terminal = true) : t.computes = s.computes ∧ t.started = s.started :=
  RelationChain.terminal_run_no_compute trace terminal
