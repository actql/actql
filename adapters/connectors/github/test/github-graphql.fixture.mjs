// An independent GitHub GraphQL responder for the provider-neutral HTTPS
// fixture. It answers the connector's fixed documents from a
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
const textConnection = (field, all, first = 100, after = null, pageSize = 100) => {
  const start = after === null ? 0 : decode(after) + 1;
  const values = all.slice(start, start + Math.min(first, pageSize));
  const key = field === 'assignees' ? 'login' : 'name';
  return {totalCount: all.length,
    pageInfo: {hasNextPage: start + values.length < all.length,
      endCursor: values.length === 0 ? null : encode(start + values.length - 1)},
    nodes: values.map(value => ({[key]: value}))};
};

export const graphqlIssue = (issue, fieldPageSize = 100) => ({number: issue.number,
  id: issue.id ?? `I_${issue.number}`, title: issue.title ?? `Issue ${issue.number}`,
  state: issue.state ?? 'OPEN', stateReason: issue.stateReason ?? null,
  body: issue.body ?? '',
  author: issue.author === undefined ? {login: 'octocat'} : issue.author,
  assignees: textConnection('assignees', issue.assignees ?? [], 100, null, fieldPageSize),
  labels: textConnection('labels', issue.labels ?? [], 100, null, fieldPageSize),
  url: issue.url ?? `https://github.com/octo/hello/issues/${issue.number}`,
  comments: {totalCount: issue.comments ?? 0},
  milestone: issue.milestone === undefined ? null : issue.milestone,
  createdAt: issue.createdAt ?? '2026-10-01T00:00:00Z',
  updatedAt: issue.updatedAt ?? '2026-10-02T00:00:00Z',
  closedAt: issue.closedAt ?? null});

// PullRequest has no Issue stateReason. Its own native fields are observed,
// including ref names when a corresponding Ref object no longer exists.
export const graphqlPullRequest = (pull, fieldPageSize = 100) => {
  const {stateReason, ...common} = graphqlIssue({...pull,
    id: pull.id ?? `PR_${pull.number}`,
    title: pull.title ?? `Pull request ${pull.number}`,
    url: pull.url ?? `https://github.com/octo/hello/pull/${pull.number}`}, fieldPageSize);
  return {__typename: 'PullRequest', ...common,
    baseRefName: pull.baseRefName ?? 'main', headRefName: pull.headRefName ?? 'original/head',
    isDraft: pull.isDraft ?? false, mergeable: pull.mergeable ?? 'UNKNOWN',
    mergedAt: pull.mergedAt ?? null, mergedBy: pull.mergedBy ?? null,
    reviewDecision: pull.reviewDecision ?? null};
};

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
    if (query.startsWith('query ActqlCommentSubjects(')) {
      if (state.commentSubjectsAnswer !== undefined) return state.commentSubjectsAnswer(query, variables);
      const repository = state.repositories.get(variables.id);
      if (repository === undefined) return {body: {data: {node: null}}};
      const pull = query.includes('pullRequests(first:');
      const all = repository[pull ? 'pullRequests' : 'issues'] ?? [];
      const start = variables.after === null ? 0 : decode(variables.after) + 1;
      const page = all.slice(start, start + Math.min(variables.first, state.pageSize ?? 100));
      return {body: {data: {node: {__typename: 'Repository',
        id: repository.answerId ?? variables.id, databaseId: repository.databaseId,
        nameWithOwner: repository.nameWithOwner,
        [pull ? 'pullRequests' : 'issues']: {
          pageInfo: {hasNextPage: start + page.length < all.length,
            endCursor: page.length === 0 ? null : encode(start + page.length - 1)},
          nodes: page.map(subject => ({__typename: pull ? 'PullRequest' : 'Issue',
            id: subject.id ?? `${pull ? 'PR' : 'I'}_${subject.number}`, number: subject.number,
            updatedAt: subject.updatedAt ?? '2026-10-02T00:00:00Z'}))}}}}};
    }
    if (query.startsWith('query ActqlIssueComments(')) {
      if (state.commentReadAnswer !== undefined) return state.commentReadAnswer(query, variables);
      const pull = query.includes('... on PullRequest {');
      for (const [repositoryId, repository] of state.repositories) {
        const subject = (repository[pull ? 'pullRequests' : 'issues'] ?? []).find(subject =>
          (subject.id ?? `${pull ? 'PR' : 'I'}_${subject.number}`) === variables.id);
        if (subject === undefined) continue;
        const originalRepository = {__typename: 'Repository', id: repository.answerId ?? repositoryId,
          databaseId: repository.databaseId, nameWithOwner: repository.nameWithOwner};
        const all = subject.commentRows ?? [];
        const start = variables.after === null ? 0 : decode(variables.after) + 1;
        const page = all.slice(start, start + Math.min(variables.first, state.commentPageSize ?? 100));
        return {body: {data: {node: {__typename: pull ? 'PullRequest' : 'Issue',
          id: variables.id, number: subject.number, updatedAt: subject.updatedAt ?? '2026-10-02T00:00:00Z',
          repository: originalRepository, comments: {
            pageInfo: {hasNextPage: start + page.length < all.length,
              endCursor: page.length === 0 ? null : encode(start + page.length - 1)},
            nodes: page.map(row => ({__typename: 'IssueComment',
              id: row.nodeId, fullDatabaseId: row.id, author: row.author,
              body: row.body, createdAt: row.createdAt, updatedAt: row.updatedAt,
              repository: originalRepository}))}}}}};
      }
      return {body: {data: {node: null}}};
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
    if (query.startsWith('query ActqlConfirmComment(')) {
      if (state.commentConfirmationAnswer !== undefined) return state.commentConfirmationAnswer(query, variables);
      const comment = state.comments?.find(item => `IC_${item.databaseId}` === variables.id);
      const subject = comment === undefined ? undefined : state.subjects?.get(comment.subjectId);
      const repository = subject === undefined ? undefined : state.repositories.get(subject.repository);
      if (comment === undefined || subject === undefined || repository === undefined) {
        return {body: {data: {node: null}}};
      }
      return {body: {data: {node: {__typename: 'IssueComment', id: variables.id,
        databaseId: comment.databaseId, body: comment.body,
        issue: {__typename: subject.type, id: comment.subjectId},
        repository: {__typename: 'Repository', id: subject.repository,
          databaseId: repository.databaseId, nameWithOwner: repository.nameWithOwner}}}}};
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
    const pullField = query.startsWith('query ActqlPullRequestAssignees(') ? 'assignees'
      : query.startsWith('query ActqlPullRequestLabels(') ? 'labels' : undefined;
    if (pullField !== undefined) {
      if (state.pullChildAnswer !== undefined) return state.pullChildAnswer(pullField, variables);
      const repository = state.repositories.get(variables.id);
      const pull = repository?.pullRequests?.find(value => value.number === variables.number);
      return {body: {data: {node: repository === undefined ? null : {
        __typename: 'Repository', id: repository.answerId ?? variables.id,
        databaseId: repository.databaseId, nameWithOwner: repository.nameWithOwner,
        pullRequest: pull === undefined ? null : {__typename: 'PullRequest', id: pull.id ?? `PR_${pull.number}`,
          number: pull.number, updatedAt: pull.updatedAt ?? '2026-10-02T00:00:00Z',
          [pullField]: textConnection(pullField, pull[pullField] ?? [], variables.first,
            variables.after, state.fieldPageSize ?? 100)}}}}};
    }
    if (query.startsWith('query ActqlPullRequests(')) {
      if (state.pullAnswer !== undefined) return state.pullAnswer(variables);
      const repository = state.repositories.get(variables.id);
      if (repository === undefined) return {body: {data: {node: null}, errors: [{type: 'NOT_FOUND'}]}};
      const states = variables.states ?? ['OPEN', 'CLOSED', 'MERGED'];
      const items = (repository.pullRequests ?? []).filter(pull => states.includes(pull.state ?? 'OPEN') &&
        (variables.labels ?? []).every(label => (pull.labels ?? []).includes(label)));
      const start = variables.after == null ? 0 : decode(variables.after) + 1;
      const size = Math.min(variables.first, state.pageSize ?? 100);
      const page = items.slice(start, start + size);
      return {body: {data: {node: {__typename: 'Repository',
        id: repository.answerId ?? variables.id, databaseId: repository.databaseId,
        nameWithOwner: repository.nameWithOwner,
        pullRequests: {pageInfo: {hasNextPage: start + page.length < items.length,
          endCursor: page.length === 0 ? null : encode(start + page.length - 1)},
        nodes: page.map(pull => graphqlPullRequest(pull, state.fieldPageSize ?? 100))}}}}};
    }
    const field = query.startsWith('query ActqlIssueAssignees(') ? 'assignees'
      : query.startsWith('query ActqlIssueLabels(') ? 'labels' : undefined;
    if (field !== undefined) {
      if (state.childAnswer !== undefined) return state.childAnswer(field, variables);
      const repository = state.repositories.get(variables.id);
      const issue = repository?.issues.find(value => value.number === variables.number);
      return {body: {data: {node: repository === undefined ? null : {
        __typename: 'Repository', id: repository.answerId ?? variables.id,
        databaseId: repository.databaseId, nameWithOwner: repository.nameWithOwner,
        issue: issue === undefined ? null : {id: issue.id ?? `I_${issue.number}`,
          number: issue.number, updatedAt: issue.updatedAt ?? '2026-10-02T00:00:00Z',
          [field]: textConnection(field, issue[field] ?? [], variables.first,
            variables.after, state.fieldPageSize ?? 100)}}}}};
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
      nodes: page.map(issue => graphqlIssue(issue, state.fieldPageSize ?? 100))}}}}};
  }};
}

// The requests a fixture saw for the Issue read, with their variables.
export const issueReads = fixture => fixture.seen()
  .filter(entry => entry.pathname === '/graphql')
  .map(entry => JSON.parse(entry.body))
  .filter(request => request.query.startsWith('query ActqlIssues('));

export const pullRequestReads = fixture => fixture.seen()
  .filter(entry => entry.pathname === '/graphql')
  .map(entry => JSON.parse(entry.body))
  .filter(request => request.query.startsWith('query ActqlPullRequests('));

// The comment mutations a fixture saw, with their variables.
export const commentSends = fixture => fixture.seen()
  .filter(entry => entry.pathname === '/graphql')
  .map(entry => JSON.parse(entry.body))
  .filter(request => request.query.startsWith('mutation ActqlAddComment('));
