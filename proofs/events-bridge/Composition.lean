namespace BridgeComposition

-- An observation is supplied explicitly. Equality never drops an error, and
-- composition requires both stages to preserve the chosen observations.
def observeResult {E A B : Type} (observe : A → B) : Except E A → Except E B
  | .error error => .error error
  | .ok value => .ok (observe value)

def composeResult {E A B : Type} (result : Except E A)
    (next : A → Except E B) : Except E B :=
  match result with
  | .error error => .error error
  | .ok value => next value

theorem observed_composition {E A B C X Y Z : Type}
    (input : A → X) (middle : B → Y) (output : C → Z)
    (first : A → Except E B) (second : B → Except E C)
    (firstObserved : X → Except E Y) (secondObserved : Y → Except E Z)
    (firstLaw : ∀ value, observeResult middle (first value) = firstObserved (input value))
    (secondLaw : ∀ value, observeResult output (second value) = secondObserved (middle value))
    (value : A) :
    observeResult output (composeResult (first value) second) =
      composeResult (firstObserved (input value)) secondObserved := by
  rw [← firstLaw value]
  cases first value with
  | error error => rfl
  | ok intermediate => exact secondLaw intermediate

theorem failure_short_circuits {E A B : Type} (error : E) (next : A → Except E B) :
    composeResult (.error error) next = .error error := rfl

theorem observed_failure {E A B : Type} (observe : A → B) (error : E) :
    observeResult observe (.error error) = .error error := rfl

theorem observe_identity {E A : Type} (result : Except E A) :
    observeResult id result = result := by
  cases result <;> rfl

theorem sequential_associativity {E A B C : Type} (result : Except E A)
    (second : A → Except E B) (third : B → Except E C) :
    composeResult (composeResult result second) third =
      composeResult result (fun value => composeResult (second value) third) := by
  cases result <;> rfl

-- Matching input/output types alone cannot discharge the intermediate premise.
theorem sequential_preconditions {E A B C : Type}
    (first : A → Except E B) (second : B → Except E C)
    (pre : A → Prop) (intermediate : B → Prop) (post : C → Prop)
    (firstLaw : ∀ a b, pre a → first a = .ok b → intermediate b)
    (secondLaw : ∀ b c, intermediate b → second b = .ok c → post c)
    (a : A) (c : C) (admitted : pre a)
    (completed : composeResult (first a) second = .ok c) : post c := by
  cases step : first a with
  | error error => simp [composeResult, step] at completed
  | ok b =>
    apply secondLaw b c (firstLaw a b admitted step)
    simpa [composeResult, step] using completed

end BridgeComposition
