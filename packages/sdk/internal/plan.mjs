// Read-only static compiler projection through the existing wire validator.
import {contentCid} from '../checkpoints.mjs';
import {captureResponse, freezeInput} from './data.mjs';
import {fail} from './errors.mjs';
import {snapshotClientRequest, validClientBody, validWireEffectfulStaticPlanViewShape,
  validWirePlanViewShape} from '@actql/client-wire';

export function createPlan(connection, exchange, responseValue) {
  const selected = {wire: connection};
  return {
    plan: async (input, options = {}) => {
      const kind = options.kind ?? (typeof input === 'string' ? 'aql' : 'program');
      const body = snapshotClientRequest({kind,
        input: kind === 'aql' ? {text: input, format: options.format ?? 'aql-text',
          ...(options.parameterDeclarations === undefined ? {} :
            {parameterDeclarations: options.parameterDeclarations})} : input,
        parameters: options.parameters ?? null,
        maxWireBytes: options.maxWireBytes ?? 65536,
        maxNodes: options.maxNodes ?? 10000, maxDepth: options.maxDepth ?? 64});
      if (!validClientBody('plan', {connection: selected.wire, ...body})) {
        fail('InvalidClientPlanRequest');
      }
      const response = await exchange('plan', body, options.signal);
      const view = captureResponse(await responseValue(response));
      const effectful = validWireEffectfulStaticPlanViewShape(view);
      if (!effectful && !validWirePlanViewShape(view)) fail('InvalidClientHostPlanView');
      const component = effectful ? view.computation.plan_view : view;
      const map = component.logical_map;
      const {self_cid: observed, ...preimage} = map;
      if (map.compiled_plan_cid !== component.compiled_plan_cid ||
          effectful && map.program_definition_cid !== view.program_definition_cid ||
          await contentCid(preimage) !== observed) fail('InvalidClientHostPlanView');
      return freezeInput(view);
    },
  };
}
