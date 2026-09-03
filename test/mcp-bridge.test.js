'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  buildToolDefinitions,
  getToolParams,
  handleRequest,
} = require('../mcp-bridge');

const javaSource = fs.readFileSync(
  path.join(__dirname, '..', 'src', 'main', 'java', 'com', 'burpmcp', 'McpHttpServer.java'),
  'utf8'
);

function advertisedJavaTools() {
  const start = javaSource.indexOf('private String getToolList()');
  const end = javaSource.indexOf('private void addCorsHeaders', start);
  return [...javaSource.slice(start, end).matchAll(/\\"([a-z0-9_]+)\\"/g)].map(match => match[1]);
}

test('the JSON-RPC handler is async and initializes successfully', async () => {
  const pending = handleRequest({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} });
  assert.equal(typeof pending.then, 'function');

  const response = await pending;
  assert.equal(response.id, 1);
  assert.equal(response.result.serverInfo.name, 'burpsuite-mcp');
});

test('audited parameterized tools publish their argument schemas', () => {
  const expectedKeys = {
    highlight: ['color', 'index'],
    annotate: ['index', 'note'],
    compare: ['index1', 'index2'],
    add_issue: ['confidence', 'detail', 'name', 'remediation', 'severity', 'url'],
    scan: ['mode', 'url'],
  };

  for (const [tool, expected] of Object.entries(expectedKeys)) {
    assert.deepEqual(Object.keys(getToolParams(tool)).sort(), expected);
  }
});

test('audited no-argument tools publish valid empty object schemas', () => {
  const tools = [
    'proxy_clear',
    'export_config',
    'burp_version',
    'remove_http_handler',
    'remove_proxy_rule',
    'save_project',
  ];

  for (const tool of tools) assert.deepEqual(getToolParams(tool), {});
});

test('tool definitions use the burp prefix and declared schemas', () => {
  const [definition] = buildToolDefinitions(['add_issue']);
  assert.equal(definition.name, 'burp_add_issue');
  assert.equal(definition.inputSchema.type, 'object');
  assert.ok(definition.inputSchema.properties.remediation);
});

test('every advertised parameterized Java tool has a bridge schema', () => {
  const noArgumentTools = new Set([
    'proxy_clear',
    'collaborator_poll',
    'export_config',
    'save_project',
    'burp_version',
    'remove_http_handler',
    'remove_proxy_rule',
    'extensions_list',
    'session_remove_rule',
    'session_list_rules',
    'websocket_list',
  ]);
  const tools = advertisedJavaTools();

  assert.equal(tools.length, 78);
  const missing = tools.filter(tool => (
    Object.keys(getToolParams(tool)).length === 0 && !noArgumentTools.has(tool)
  ));
  assert.deepEqual(missing, []);
});

test('deprecated compatibility tools are absent from Java dispatch', () => {
  const deprecated = [
    'proxy_listeners',
    'proxy_match_replace',
    'intercept_modify',
    'export_cert',
    'websocket_send',
  ];

  for (const tool of deprecated) {
    assert.doesNotMatch(javaSource, new RegExp(`case "${tool}"`));
    assert.ok(!advertisedJavaTools().includes(tool));
  }
});
