import type {WireEffectfulStaticPlanView, WirePlanView, WireStaticExplanationView} from
  '../../packages/client-wire/interactive-control.generated.js';

type Fixture<Value> = {-readonly [Key in keyof Value]: Fixture<Value[Key]>};
type EffectPlan = Fixture<WireEffectfulStaticPlanView>;

export declare const computationPlan: Fixture<WirePlanView>;
export declare const effectfulStaticPlan: EffectPlan;
export declare const commandMember: EffectPlan['effect_set']['members'][number];
export declare const positiveEffectfulPlans: readonly EffectPlan[];
export declare const negativeEffectfulPlans: readonly unknown[];
export declare function effectfulStaticExplanationFixture():
  Fixture<WireStaticExplanationView> & {plan: EffectPlan};
