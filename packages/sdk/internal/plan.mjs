// Read-only static compiler projection through the existing wire validator.
import {contentCid} from '../checkpoints.mjs';
import {captureResponse, freezeInput} from './data.mjs';
import {fail} from './errors.mjs';
import {snapshotClientRequest, validClientBody, validWireEffectfulStaticPlanViewShape,
  validWirePlanViewShape, validWireStaticExplanationViewShape,
  withinResultDescriptionLimits} from '@actql/client-wire';

function matchesStaticExplanation(view, component, effectful) {
  const {facts, context: {binding}, plan} = view;
  const map = component.logical_map;
  return facts.program_definition_cid === map.program_definition_cid &&
    binding.program_definition_cid === map.program_definition_cid &&
    facts.compiled_plan_cid === component.compiled_plan_cid &&
    binding.compiled_plan_cid === component.compiled_plan_cid &&
    facts.logical_map_cid === map.self_cid && binding.logical_map_cid === map.self_cid &&
    facts.parameter_values_cid === binding.parameter_values_cid &&
    (!effectful || facts.parameter_values_cid === plan.parameter_values_cid &&
      binding.check_environment_cid === plan.check_environment_cid);
}

export function createPlan(connection, exchange, responseValue, withStaticPreparation, sourcePreparation) {
  const selected = {wire: connection};
  const read = (operation, input, originalOptions) => withStaticPreparation(
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
      let captured;
      const snapshot = (value, observe) => {
        if (value !== original || captured !== undefined) fail('InvalidHostSourceSnapshot');
        return captured = snapshotClientRequest(value, observe);
      };
      if (producer !== undefined) sourcePreparation.assertSourceSnapshotCurrent(producer.receipt);
      const value = producer === undefined ? snapshot(original)
        : sourcePreparation.captureSourceSnapshot(producer.receipt, original, snapshot);
      if (captured === undefined || value !== captured) fail('InvalidHostSourceSnapshot');
      if (producer !== undefined) sourcePreparation.assertSourceSnapshotCurrent(producer.receipt);
      const body = freezeInput(captured);
      if (producer !== undefined) {
        sourcePreparation.bindSourceSnapshot(producer.receipt, body);
        producer.body = body;
      }
      const staticRead = operation === 'static-explanation';
      if (!validClientBody(operation, {connection: selected.wire, ...body})) {
        fail(staticRead ? 'InvalidClientStaticExplanationRequest' : 'InvalidClientPlanRequest');
      }
      const response = await exchange(operation, body, options.signal, undefined, undefined, producer);
      const view = captureResponse(await responseValue(response));
      if (staticRead && (!withinResultDescriptionLimits(view, body) || !validWireStaticExplanationViewShape(view))) {
        fail('InvalidClientHostStaticExplanationView');
      }
      const plan = staticRead ? view.plan : view;
      const effectful = validWireEffectfulStaticPlanViewShape(plan);
      if (!effectful && !validWirePlanViewShape(plan)) fail('InvalidClientHostPlanView');
      const component = effectful ? plan.computation.plan_view : plan;
      const map = component.logical_map;
      const {self_cid: observed, ...preimage} = map;
      if (map.compiled_plan_cid !== component.compiled_plan_cid ||
          effectful && map.program_definition_cid !== plan.program_definition_cid ||
          await contentCid(preimage) !== observed) fail('InvalidClientHostPlanView');
      if (staticRead && !matchesStaticExplanation(view, component, effectful)) {
        fail('InvalidClientHostStaticExplanationView');
      }
      return freezeInput(view);
    });
  return {
    plan: (input, options) => read('plan', input, options),
    explain: (input, options) => read('static-explanation', input, options),
  };
}
