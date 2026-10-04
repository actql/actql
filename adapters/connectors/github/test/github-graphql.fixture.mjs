// An independent GitHub GraphQL responder for the provider-neutral HTTPS
// fixture. It answers only the connector's two fixed documents, from a
// repository table keyed by global node ID and resolved by name separately,
// so a test can make a name point at another repository, make a node answer
// for another repository, remove a repository, or change an ID's spelling.
// It also answers the comment subject check and the `addComment` mutation
// from a subject table, recording each created comment.
// Expected rows are written by hand in each test; nothing here is derived
// from the product.
const encode = index => Buffer.from(`cursor:${index}`).toString('base64');
const decode = cursor => {
  const text = Buffer.from(cursor, 'base64').toString('utf8');
  return text.startsWith('cursor:') ? Number(text.slice(7)) : NaN;
};

// One GraphQL Issue node from a test Issue.
export const graphqlIssue = issue => ({number: issue.number,
  id: issue.id ?? `I_${issue.number}`, title: issue.title ?? `Issue ${issue.number}`,
  state: issue.state ?? 'OPEN', body: issue.body ?? '',
  author: issue.author === undefined ? {login: 'octocat'} : issue.author,
  comments: {totalCount: issue.comments ?? 0},
  createdAt: issue.createdAt ?? '2026-10-01T00:00:00Z',
  updatedAt: issue.updatedAt ?? '2026-10-02T00:00:00Z',
  closedAt: issue.closedAt ?? null});

// `world()` returns the current provider state:
// {repositories: Map(nodeId -> {databaseId, nameWithOwner, issues}),
//  names: Map(nameWithOwner -> nodeId), pageSize, answer?(variables),
//  subjects?: Map(nodeId -> {type, repository, number}),
//  commentReply?(variables), comments?: [{subjectId, body, databaseId}]}.
// `answer`, when present, overrides the node response for misbehaviour.
export function graphqlRoute(world) {
  return {method: 'POST', pathname: '/graphql', handle(exchange) {
    let request;
    try { request = JSON.parse(exchange.body); }
    catch { return {status: 400, body: {message: 'Problems parsing JSON'}}; }
    const state = world();
    const {query, variables = {}} = request;
    if (typeof query !== 'string') return {status: 400, body: {}};
    if (query.startsWith('query ActqlRepository(')) {
      const nodeId = state.names.get(`${variables.owner}/${variables.name}`);
      const repository = nodeId === undefined ? undefined
        : state.repositories.get(nodeId);
      return {body: {data: {repository: repository === undefined ? null : {
        __typename: 'Repository', id: nodeId,
        databaseId: repository.databaseId,
        nameWithOwner: repository.nameWithOwner}}}};
    }
    if (query.startsWith('query ActqlCommentSubject(')) {
      const subject = state.subjects?.get(variables.id);
      if (subject === undefined) {
        return {body: {data: {node: null}, errors: [{type: 'NOT_FOUND',
          message: `Could not resolve to a node with the global id of '${variables.id}'`}]}};
      }
      const repository = state.repositories.get(subject.repository);
      return {body: {data: {node: subject.type === 'Issue' ||
        subject.type === 'PullRequest' ? {__typename: subject.type,
        id: variables.id, number: subject.number,
        repository: {__typename: 'Repository', id: subject.repository,
          databaseId: repository.databaseId,
          nameWithOwner: repository.nameWithOwner}}
        : {__typename: subject.type}}}};
    }
    if (query.startsWith('mutation ActqlAddComment(')) {
      if (state.commentReply !== undefined) {
        return state.commentReply(variables);
      }
      const subject = state.subjects?.get(variables.subjectId);
      if (subject === undefined) {
        return {body: {data: {addComment: null}, errors: [{type: 'NOT_FOUND',
          message: 'Could not resolve to a node'}]}};
      }
      // GitHub accepts a comment on an Issue or a pull request alike.
      state.comments ??= [];
      const databaseId = 1000 + state.comments.length;
      state.comments.push({subjectId: variables.subjectId,
        body: variables.body, databaseId});
      return {body: {data: {addComment: {
        commentEdge: {node: {id: `IC_${databaseId}`, databaseId}},
        subject: {__typename: subject.type, id: variables.subjectId}}}}};
    }
    if (!query.startsWith('query ActqlIssues(')) {
      return {body: {errors: [{type: 'UNEXPECTED_DOCUMENT',
        message: 'not one of the connector documents'}]}};
    }
    if (state.answer !== undefined) return state.answer(variables);
    const repository = state.repositories.get(variables.id);
    if (repository === undefined) {
      return {body: {data: {node: null}, errors: [{type: 'NOT_FOUND',
        message: `Could not resolve to a node with the global id of '${variables.id}'`}]}};
    }
    const states = variables.states ?? ['OPEN', 'CLOSED'];
    const items = repository.issues.filter(issue =>
      states.includes(issue.state ?? 'OPEN'));
    const start = variables.after == null ? 0 : decode(variables.after) + 1;
    const size = Math.min(variables.first, state.pageSize ?? 100);
    const page = items.slice(start, start + size);
    const last = start + page.length - 1;
    return {body: {data: {node: {__typename: 'Repository',
      id: repository.answerId ?? variables.id,
      databaseId: repository.databaseId,
      nameWithOwner: repository.nameWithOwner,
      issues: {pageInfo: {hasNextPage: start + page.length < items.length,
        endCursor: page.length === 0 ? null : encode(last)},
      nodes: page.map(graphqlIssue)}}}}};
  }};
}

// The requests a fixture saw for the Issue read, with their variables.
export const issueReads = fixture => fixture.seen()
  .filter(entry => entry.pathname === '/graphql')
  .map(entry => JSON.parse(entry.body))
  .filter(request => request.query.startsWith('query ActqlIssues('));

// The comment mutations a fixture saw, with their variables.
export const commentSends = fixture => fixture.seen()
  .filter(entry => entry.pathname === '/graphql')
  .map(entry => JSON.parse(entry.body))
  .filter(request => request.query.startsWith('mutation ActqlAddComment('));
