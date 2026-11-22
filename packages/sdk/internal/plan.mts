// Read-only static compiler projection through the existing wire validator.
import type {Client} from '../index.d.ts';
import type {WireConnection, WirePlanView, WireEffectfulStaticPlanView, WireStaticExplanationView} from '@actql/client-wire';

interface StaticProducer {
  readonly receipt: unknown;
  body?: unknown;
}
interface StaticPreparation {
  assertSourceSnapshotCurrent(receipt: unknown): void;
  captureSourceSnapshot(receipt: unknown, original: unknown,
    snapshot: (value: unknown, observe?: Parameters<typeof snapshotClientRequest>[1]) => unknown): unknown;
  bindSourceSnapshot(receipt: unknown, body: unknown): unknown;
}
import {contentCid} from '../checkpoints.mjs';
import {captureResponse, freezeInput} from './data.mjs';
import {fail} from './errors.mjs';
import {snapshotClientRequest, validClientBody, validWireEffectfulStaticPlanViewShape,
  validWirePlanViewShape, validWireStaticExplanationViewShape,
  withinResultDescriptionLimits} from '@actql/client-wire';

type StaticOperation = 'plan' | 'static-explanation';
type StaticInput = Parameters<Client['plan']>[0];
type StaticOptions = Parameters<Client['plan']>[1];
type StaticView<Operation extends StaticOperation> = Operation extends 'plan'
  ? Awaited<ReturnType<Client['plan']>> : WireStaticExplanationView;

function matchesStaticExplanation(view: WireStaticExplanationView, component: WirePlanView, effectful: boolean) {
  const {facts, context: {binding}, plan} = view;
  const map = component.logical_map;
  return facts.program_definition_cid === map.program_definition_cid &&
    binding.program_definition_cid === map.program_definition_cid &&
    facts.compiled_plan_cid === component.compiled_plan_cid &&
    binding.compiled_plan_cid === component.compiled_plan_cid &&
    facts.logical_map_cid === map.self_cid && binding.logical_map_cid === map.self_cid &&
    facts.parameter_values_cid === binding.parameter_values_cid &&
    (!effectful || facts.parameter_values_cid === (plan as WireEffectfulStaticPlanView).parameter_values_cid &&
      binding.check_environment_cid === (plan as WireEffectfulStaticPlanView).check_environment_cid);
}

export function createPlan(connection: WireConnection,
  exchange: (operation: StaticOperation, body: Record<string, unknown>, signal?: AbortSignal,
    submitContext?: undefined, cancellationContext?: undefined, producer?: StaticProducer) => Promise<unknown>,
  responseValue: (response: unknown) => unknown | Promise<unknown>,
  withStaticPreparation: <T>(kind: 'aql' | 'program', input: unknown, options: unknown,
    read: (producer?: StaticProducer) => Promise<T>) => Promise<T>,
  sourcePreparation?: StaticPreparation): Pick<Client, 'plan' | 'explain'> {
  const selected = {wire: connection};
  const read = <Operation extends StaticOperation>(operation: Operation, input: StaticInput,
    originalOptions: StaticOptions): Promise<StaticView<Operation>> => withStaticPreparation(
      typeof input === 'string' ? 'aql' : 'program', input, originalOptions, async producer => {
      const options = originalOptions === undefined ? {} : originalOptions;
      const kind = options.kind ?? (typeof input === 'string' ? 'aql' : 'program');
      const original = {kind,
        input: kind === 'aql' ? {text: input, format: options.format ?? 'aql-text',
          ...(options.parameterDeclarations === undefined ? {} :
            {parameterDeclarations: options.parameterDeclarations})} : input,
        parameters: options.parameters ?? null,
        maxWireBytes: options.maxWireBytes ?? 65536,
        maxNodes: options.maxNodes ?? 10000, maxDepth: options.maxDepth ?? 64};
      let captured: unknown;
      const snapshot = (value: unknown, observe?: Parameters<typeof snapshotClientRequest>[1]) => {
        if (value !== original || captured !== undefined) fail('InvalidHostSourceSnapshot');
        return captured = snapshotClientRequest(value, observe);
      };
      if (producer !== undefined) sourcePreparation!.assertSourceSnapshotCurrent(producer.receipt);
      const value = producer === undefined ? snapshot(original)
        : sourcePreparation!.captureSourceSnapshot(producer.receipt, original, snapshot);
      if (captured === undefined || value !== captured) fail('InvalidHostSourceSnapshot');
      if (producer !== undefined) sourcePreparation!.assertSourceSnapshotCurrent(producer.receipt);
      // This is the original unchecked JSON snapshot; the wire guard below
      // still admits the complete actual body before any exchange.
      const body = freezeInput(captured) as Record<string, unknown> & Parameters<typeof withinResultDescriptionLimits>[1];
      if (producer !== undefined) {
        sourcePreparation!.bindSourceSnapshot(producer.receipt, body);
        producer.body = body;
      }
      const staticRead = operation === 'static-explanation';
      if (!validClientBody(operation, {connection: selected.wire, ...body})) {
        fail(staticRead ? 'InvalidClientStaticExplanationRequest' : 'InvalidClientPlanRequest');
      }
      const response = await exchange(operation, body, options.signal, undefined, undefined, producer);
      const view: unknown = captureResponse(await responseValue(response));
      if (staticRead && (!withinResultDescriptionLimits(view, body) || !validWireStaticExplanationViewShape(view))) {
        fail('InvalidClientHostStaticExplanationView');
      }
      const plan = staticRead ? (view as WireStaticExplanationView).plan : view;
      const effectful = validWireEffectfulStaticPlanViewShape(plan);
      if (!effectful && !validWirePlanViewShape(plan)) fail('InvalidClientHostPlanView');
      const component = effectful ? plan.computation.plan_view : plan;
      const map = component.logical_map;
      const {self_cid: observed, ...preimage} = map;
      if (map.compiled_plan_cid !== component.compiled_plan_cid ||
          effectful && map.program_definition_cid !== plan.program_definition_cid ||
          await contentCid(preimage) !== observed) fail('InvalidClientHostPlanView');
      if (staticRead && !matchesStaticExplanation(view as WireStaticExplanationView, component, effectful)) {
        fail('InvalidClientHostStaticExplanationView');
      }
      return freezeInput(view) as StaticView<Operation>;
    });
  return {
    plan: (input, options) => read('plan', input, options),
    explain: (input, options) => read('static-explanation', input, options),
  };
}
