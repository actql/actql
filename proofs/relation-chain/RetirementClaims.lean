-- Exact consumer propositions for the early-retirement contract. In particular,
-- release of execution custody must preserve private completed-output references.
example (s : RelationChain.State) (done : Bool) (h : RelationChain.Accounted s) :
    RelationChain.Accounted (RelationChainRetirement.retireCore s done) :=
  RelationChainRetirement.retire_core_accounted s done h

example (s : RelationChain.State) (done : Bool) (h : RelationChain.Responsible s) :
    RelationChain.Responsible (RelationChainRetirement.retireCore s done) :=
  RelationChainRetirement.retire_core_responsible s done h

example (s : RelationChainRetirement.State) (done : Bool) :
    (RelationChainRetirement.retire s done).core.computes = s.core.computes ∧
    (RelationChainRetirement.retire s done).core.started = s.core.started ∧
    (RelationChainRetirement.retire s done).core.reported = s.core.reported :=
  RelationChainRetirement.retire_no_compute s done

example (s : RelationChainRetirement.State) (done : Bool) :
    (RelationChainRetirement.retire s done).outputs = s.outputs :=
  RelationChainRetirement.retire_preserves_outputs s done

example (s : RelationChainRetirement.State) : RelationChainRetirement.retire s false = s :=
  RelationChainRetirement.pending_cleanup_identity s

example (s : RelationChainRetirement.State) (id : Nat) (ready : s.pending = true)
    (single : s.core.owed = [id]) :
    (RelationChainRetirement.retire s true).core.owed = [] ∧
    (RelationChainRetirement.retire s true).core.released = id :: s.core.released ∧
    RelationChainRetirement.retire (RelationChainRetirement.retire s true) true =
      RelationChainRetirement.retire s true :=
  RelationChainRetirement.successful_retirement_once s id ready single

example (s : RelationChainRetirement.State) (work : Nat) :
    (RelationChainRetirement.complete s work).pending = true ∧
    (RelationChainRetirement.complete s work).core.owed = s.core.owed ∧
    (RelationChainRetirement.complete s work).outputs = s.outputs ++ [s.core.started - 1] :=
  RelationChainRetirement.completed_output_before_reclamation s work

example (s : RelationChainRetirement.State) (owed : s.core.owed ≠ []) :
    ¬ RelationChainRetirement.CanHandoff s :=
  RelationChainRetirement.owed_child_blocks_handoff s owed

example (s : RelationChainRetirement.State) :
    (RelationChainRetirement.cancelPending s).core.owed = s.core.owed ∧
    (RelationChainRetirement.cancelPending s).outputs = s.outputs ∧
    (RelationChainRetirement.cancelPending s).core.computes = s.core.computes :=
  RelationChainRetirement.cancellation_preserves_custody s

example (s t : RelationChainRetirement.State) (step : RelationChainRetirement.Step s t)
    (h : RelationChain.Accounted s.core) : RelationChain.Accounted t.core :=
  RelationChainRetirement.step_accounted step h

example (s t : RelationChainRetirement.State) (step : RelationChainRetirement.Step s t)
    (h : RelationChain.Responsible s.core) : RelationChain.Responsible t.core :=
  RelationChainRetirement.step_responsible step h

example (s t : RelationChainRetirement.State) (step : RelationChainRetirement.Step s t)
    (h : s.core.owed.length ≤ 1) : t.core.owed.length ≤ 1 :=
  RelationChainRetirement.step_single_execution step h

example (s t : RelationChainRetirement.State) (run : RelationChainRetirement.Run s t)
    (h : RelationChainRetirement.Invariant s) : RelationChainRetirement.Invariant t :=
  RelationChainRetirement.finite_run_invariant run h

example (budget : Nat) : RelationChainRetirement.Invariant (RelationChainRetirement.initial budget) :=
  RelationChainRetirement.initial_invariant budget

example (s t : RelationChainRetirement.State) (step : RelationChainRetirement.Step s t)
    (terminal : s.core.terminal = true) :
    t.core.terminal = true ∧ t.core.computes = s.core.computes ∧ t.core.started = s.core.started :=
  RelationChainRetirement.step_terminal_no_compute step terminal

example (s t : RelationChainRetirement.State) (run : RelationChainRetirement.Run s t)
    (terminal : s.core.terminal = true) :
    t.core.computes = s.core.computes ∧ t.core.started = s.core.started :=
  RelationChainRetirement.terminal_run_no_compute run terminal

example (s t : RelationChainRetirement.State) (step : RelationChainRetirement.Step s t) :
    t.core.budget = s.core.budget := RelationChainRetirement.step_budget step

example (s t : RelationChainRetirement.State) (run : RelationChainRetirement.Run s t) :
    t.core.budget = s.core.budget := RelationChainRetirement.finite_run_budget run

example (budget : Nat) (t : RelationChainRetirement.State)
    (run : RelationChainRetirement.Run (RelationChainRetirement.initial budget) t) :
    t.core.reported = t.core.childWork + t.core.handoffWork ∧ t.core.reported ≤ budget :=
  RelationChainRetirement.chain_accounting budget t run
