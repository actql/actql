example : ∀ (r : List IncrementalEvidence.Requirement)
    (a : List IncrementalEvidence.Application),
    IncrementalEvidence.check r a = true → IncrementalEvidence.ValidPlan r a :=
  IncrementalEvidence.checker_sound

example : ∀ (r : List IncrementalEvidence.Requirement)
    (a : List IncrementalEvidence.Application),
    IncrementalEvidence.ValidPlan r a → IncrementalEvidence.check r a = true :=
  IncrementalEvidence.checker_complete

example : ∀ (r : IncrementalEvidence.Requirement) (a : IncrementalEvidence.Application),
    IncrementalEvidence.ValidApplication r a →
    a.kind = r.kind ∧ a.target = r.target ∧ a.scope = r.scope ∧ a.premises = r.premises :=
  IncrementalEvidence.scope_and_kind_preserved

example : ∀ (r : List IncrementalEvidence.Requirement)
    (a : List IncrementalEvidence.Application),
    IncrementalEvidence.ValidPlan r a →
    r.map IncrementalEvidence.Requirement.action = a.map IncrementalEvidence.Application.action :=
  IncrementalEvidence.required_obligations_preserved

example : ∀ {S I E : Type} (p : S → I) (f : I → E) (o c : S),
    p o = p c → f (p o) = f (p c) :=
  IncrementalEvidence.identical_inputs_preserve_observation
