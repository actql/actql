import type {ExplanationStoryModel, PlanReadModel, StaticExplanationReadModel} from '@actql/explorer-ui/read-model';

type Step = ExplanationStoryModel['occurrences'][number];
type Context = StaticExplanationReadModel['context'];
type Edge = Pick<ExplanationStoryModel['dependencies'][number], 'sourcePortId' | 'sourceStepId' | 'targetStepId'>;

export type StoryGroup = Readonly<{
  id: string;
  kind: 'source' | 'join' | 'model' | 'filter' | 'result' | 'effect' | 'operation';
  members: readonly Step[];
  primary?: Step;
  item?: Context[number];
}>;

type Card = Omit<StoryGroup, 'members'> & {members: Step[]};

export function storyCardGroups(story: ExplanationStoryModel, context: Context,
  sourceSteps: ReadonlyMap<number, {step: Step}>, stageResultLinks: PlanReadModel['stageResultLinks']): readonly StoryGroup[] {
  const steps = new Map(story.occurrences.map(step => [step.stepId, step]));
  const incoming = new Map<string, Edge[]>(), outgoing = new Map<string, Edge[]>();
  function add(map: Map<string, Edge[]>, value: Edge, id: string) {
    const edges = map.get(id);
    if (edges) edges.push(value);
    else map.set(id, [value]);
  }
  for (const edge of story.dependencies) {
    add(incoming, edge, edge.targetStepId);
    add(outgoing, edge, edge.sourceStepId);
  }
  for (const {producer, consumer} of stageResultLinks ?? []) {
    const edge = {sourcePortId: producer.port_id, sourceStepId: producer.step_id, targetStepId: consumer.step_id};
    add(incoming, edge, edge.targetStepId);
    add(outgoing, edge, edge.sourceStepId);
  }
  const cards: Card[] = [], owners = new Map<string, Card>();
  const models = new Map<string, Extract<Context[number]['origin'], {kind: 'model_task'}>>();
  const attach = (card: Card, step: Step) => {
    owners.set(step.stepId, card);
    card.members.push(step);
  };
  const create = (kind: Card['kind'], id: string, primary?: Step, item?: Context[number]) => {
    const card: Card = {kind, id, members: [],
      ...(primary === undefined ? {} : {primary}), ...(item === undefined ? {} : {item})};
    cards.push(card);
    if (primary) attach(card, primary);
    return card;
  };
  function producer(stepId: string, portId: string) {
    const step = steps.get(stepId);
    return step?.ports.some(port => port.role === 'output' && port.port_id === portId) ? step : undefined;
  }
  let sourceIndex = 0;
  for (const [index, item] of context.entries()) {
    const origin = item.origin;
    if (origin.kind === 'source') {
      create('source', 'context:' + index, sourceSteps.get(sourceIndex++)?.step, item);
    } else if (origin.kind === 'model_task' && origin.producer.state === 'projected') {
      const {step_id, port_id} = origin.producer;
      const original = producer(step_id, port_id);
      if (original?.operator === 'infer' && !owners.has(step_id)) {
        create('model', 'context:' + index, original, item);
        models.set(step_id, origin);
      } else create('model', 'context:' + index, undefined, item);
    } else if (origin.kind === 'model_task') {
      create('model', 'context:' + index, undefined, item);
    } else if (origin.kind === 'result' && origin.producer.state === 'projected') {
      const original = producer(origin.producer.step_id, origin.producer.port_id);
      if (original && !owners.has(original.stepId)) create('result', 'context:' + index, original, item);
      else create('result', 'context:' + index, undefined, item);
    } else if (origin.kind === 'result' || origin.kind === 'effect_set') {
      create(origin.kind === 'result' ? 'result' : 'effect', 'context:' + index, undefined, item);
    }
  }
  const matchesModelInput = (step: Step) => {
    const pair = incoming.get(step.stepId);
    if (pair?.length !== 2) return false;
    return pair.some((candidate, index) => {
      const model = models.get(candidate.sourceStepId);
      if (model?.producer.state !== 'projected' || candidate.sourcePortId !== model.producer.port_id) return false;
      const inputs = incoming.get(candidate.sourceStepId), other = pair[1 - index];
      const input = inputs?.[0];
      return inputs?.length === 1 && input !== undefined && other !== undefined &&
        input.sourceStepId === other.sourceStepId && input.sourcePortId === other.sourcePortId;
    });
  };
  const internal = new Set<string>();
  for (const step of story.occurrences) {
    if (owners.has(step.stepId)) continue;
    if (step.operator === 'join' && !matchesModelInput(step)) {
      const otherJoins = new Set((incoming.get(step.stepId) ?? []).map(edge => owners.get(edge.sourceStepId))
        .filter(card => card?.kind === 'join'));
      const joined = otherJoins.size === 1 ? [...otherJoins][0] : undefined;
      if (joined) attach(joined, step);
      else create('join', step.stepId, step);
    } else if (step.operator === 'filter') {
      create('filter', step.stepId, step);
    } else if (step.operator === 'join' || step.explanation.meaning.kind === 'projection' ||
        ['assert_rows', 'derive', 'input_output', 'values'].includes(step.operator ?? 'input_output')) {
      internal.add(step.stepId);
    } else {
      create('operation', step.stepId, step);
    }
  }
  // Resolve against the original boundary cards. Folding some internal
  // operations must not make those operations become new boundaries.
  const boundaries = new Map(owners);
  function nearest(id: string, edges: ReadonlyMap<string, Edge[]>, reverse = false) {
    const checked = new Set([id]);
    let pending = [id];
    while (pending.length) {
      const next: string[] = [], reached = new Set<Card>();
      for (const current of pending) {
        for (const edge of edges.get(current) ?? []) {
          const adjacent = reverse ? edge.sourceStepId : edge.targetStepId;
          if (checked.has(adjacent)) continue;
          checked.add(adjacent);
          const card = boundaries.get(adjacent);
          if (card) reached.add(card);
          else next.push(adjacent);
        }
      }
      if (reached.size > 0) return {card: reached.size === 1 ? [...reached][0] : undefined};
      pending = next;
    }
    return undefined;
  }
  for (const id of internal) {
    const downstream = nearest(id, outgoing);
    // A downstream branch of a known Result is still presented under that
    // Result when its separate publication target is unprojected.
    const prior = downstream === undefined ? nearest(id, incoming, true)?.card : undefined;
    const parent = downstream?.card ?? (prior?.kind === 'result' ? prior : undefined);
    const step = steps.get(id)!;
    if (parent) attach(parent, step);
    else create('operation', id, step);
  }
  const order = new Map(story.occurrences.map((step, i) => [step.stepId, i]));
  for (const card of cards) card.members.sort((a,b) => order.get(a.stepId)! - order.get(b.stepId)!);
  // Keep Source declarations first and effects last. Between them, use the
  // checked boundary position rather than the first folded dependency.
  return cards.sort((a,b) => {
    const place = (card: Card) => card.kind === 'source' ? -1 : card.primary ? order.get(card.primary.stepId)! :
      card.kind === 'effect' ? Number.POSITIVE_INFINITY : story.occurrences.length;
    const x = place(a), y = place(b);
    return x === y ? 0 : x - y;
  });
}
