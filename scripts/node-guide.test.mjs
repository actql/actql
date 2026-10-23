import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import ts from 'typescript';

const guide = readFileSync(new URL('../docs/guides/node.md', import.meta.url), 'utf8');
const blocks = [...guide.matchAll(/```ts\n([\s\S]*?)\n```/gu)].map((match, index) =>
  ts.createSourceFile(`node-guide-${index}.mts`, match[1], ts.ScriptTarget.Latest, true));

function calls(method) {
  const found = [];
  const visit = node => {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
        node.expression.name.text === method) found.push(node);
    ts.forEachChild(node, visit);
  };
  blocks.forEach(visit);
  return found;
}

function properties(node, label) {
  assert.ok(node && ts.isObjectLiteralExpression(node), `${label} must be explicit`);
  return new Map(node.properties.map(property => {
    assert.ok(ts.isPropertyAssignment(property), `${label} must not infer properties`);
    assert.ok(ts.isIdentifier(property.name) || ts.isStringLiteral(property.name));
    return [property.name.text, property.initializer];
  }));
}

function declaredParameters(parameters, options) {
  const declarations = properties(options.get('parameterDeclarations'), 'parameterDeclarations');
  for (const [name, value] of parameters) {
    const declaration = properties(declarations.get(name), `declaration for ${name}`);
    const type = declaration.get('type');
    assert.ok(type && ts.isStringLiteral(type), `${name} needs an explicit type`);
    assert.ok(ts.isStringLiteral(value), 'This guide control uses a literal string parameter');
    assert.equal(type.text, 'string');
  }
}

test('Node guide short-query parameters include explicit declarations', () => {
  const selected = calls('sql').filter(call => call.arguments.length >= 2);
  assert.equal(selected.length, 1, 'Keep the current short-query example in this control');
  const [query] = selected;
  assert.ok(ts.isStringLiteral(query.arguments[0]));
  assert.equal(query.arguments[0].text, 'SELECT @owner AS owner',
    'The first query must not require an unconfigured external source');
  declaredParameters(properties(query.arguments[1], 'query parameters'),
    properties(query.arguments[2], 'query options'));
});

test('Node guide startSource parameters include explicit declarations', () => {
  const selected = calls('startSource').map(call => properties(call.arguments[1], 'startSource options'))
    .filter(options => options.has('parameters'));
  assert.equal(selected.length, 1, 'Keep the current Program example in this control');
  const [options] = selected;
  declaredParameters(properties(options.get('parameters'), 'Program parameters'), options);
});

test('Node guide retains decide target semantics without claiming current support', () => {
  const section = guide.split('### Deciding from code')[1]?.split('\n## ')[0];
  assert.ok(section, 'Keep the target decision section');
  const beforeExample = section.split('```ts')[0];
  assert.match(beforeExample, /v0\.1 target/u);
  assert.match(beforeExample, /current Node Client does not yet expose the\s+`decide` connection option/u);
  assert.match(beforeExample, /not a currently type-checking or runnable/u);
  assert.match(section, /decide: async \(decision\)/u);
  assert.match(section, /'permit' : 'defer'/u);
  assert.doesNotMatch(guide.split('## A short query')[0], /everything shown is typed/u);
});
