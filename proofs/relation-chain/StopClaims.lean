-- Exact consumers distinguish productive admission from stop-inclusive reporting.
example (budget : Nat) (s : RelationChainStop.State)
    (run : RelationChainStop.Run (RelationChainStop.initial budget) s) :
    RelationChainStop.reported s = s.productive.childWork + s.productive.handoffWork + s.stopWork ∧
    s.productive.used ≤ budget := RelationChainStop.chain_accounting budget s run

example (s : RelationChainStop.State) (work : Nat) (done : Bool) :
    RelationChainStop.reported (RelationChainStop.stopPoll s work done) = RelationChainStop.reported s + work ∧
    (RelationChainStop.stopPoll s work done).productive.used = s.productive.used ∧
    (RelationChainStop.stopPoll s work done).productive.owed = s.productive.owed :=
  RelationChainStop.stop_poll_reporting s work done

example (budget : Nat) (s : RelationChainStop.State)
    (run : RelationChainStop.Run (RelationChainStop.initial budget) s) :
    RelationChain.Responsible s.productive :=
  RelationChainStop.run_responsible run (RelationChain.initial_responsible budget)

example (s t : RelationChainStop.State) (run : RelationChainStop.Run s t) :
    t.productive.budget = s.productive.budget := RelationChainStop.run_budget run

example (s : RelationChainStop.State) :
    (RelationChainStop.request s).productive.terminal = s.productive.terminal ∧
    RelationChainStop.reported (RelationChainStop.request s) = RelationChainStop.reported s ∧
    (RelationChainStop.request s).productive.owed = s.productive.owed :=
  RelationChainStop.request_not_stopped s

example (s : RelationChainStop.State) : RelationChainStop.reclaim s false = s :=
  RelationChainStop.pending_cleanup_keeps s

example (s t : RelationChainStop.State) (run : RelationChainStop.Run s t) (h : s.requested = true) :
    t.requested = true ∧ t.productive.computes = s.productive.computes ∧
    t.productive.started = s.productive.started := RelationChainStop.stopping_run_no_compute run h

example : RelationChainStop.reported RelationChainStop.stopped = 3 ∧
    RelationChainStop.stopped.productive.used = 1 ∧ RelationChainStop.stopped.productive.budget = 1 ∧
    RelationChainStop.stopped.productive.computes = 1 ∧ RelationChainStop.stopped.productive.started = 1 ∧
    RelationChainStop.stopped.productive.terminal = true ∧ RelationChainStop.stopped.productive.owed = [0] :=
  RelationChainStop.exhausted_witness

example : RelationChainStop.Run (RelationChainStop.initial 1) RelationChainStop.stopped :=
  RelationChainStop.exhausted_witness_run
