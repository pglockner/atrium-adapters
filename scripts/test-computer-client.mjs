import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";

const reference = readFileSync(new URL("../skills/atrium/references/computer-client.md", import.meta.url), "utf8");
const source = reference.match(/```js\n([\s\S]*?)\n```/)?.[1];
assert.ok(source, "the shipped client reference must contain its executable library");
const { createComputer } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

test("binds a discovered window and preserves image blocks through subsequent actions", async () => {
  const calls = [];
  const emitted = [];
  const image = { type: "image", data: "pixels", _meta: { "codex/imageDetail": "original" } };
  const after = { pid: 10, win: 20, readyForAction: true };
  const computer = createComputer({ target: { app: "Calculator" }, output: { maxLongEdge: 1280 }, emit: block => emitted.push(block), call: async (name, args) => {
    calls.push({ name, args });
    return { content: [image], structuredContent: name === "computer_observe" ? after : { after } };
  } });
  await computer.observe();
  await computer.act("click", { x: 40, y: 60 });
  assert.deepEqual(calls[1], { name: "computer_act", args: { maxLongEdge: 1280, tool: "click", x: 40, y: 60, pid: 10, windowId: 20 } });
  assert.equal(computer.observation, after);
  assert.deepEqual(emitted, [image, image]);
});

test("emits a partial failure and throws without replaying input or running later steps", async () => {
  const calls = [];
  const emitted = [];
  const result = { isError: true, content: [{ type: "image", data: "after" }], structuredContent: { status: "error", message: "refused", completed: 1, after: { pid: 1, win: 2 } } };
  const computer = createComputer({ emit: block => emitted.push(block), call: async name => { calls.push(name); return result; } });
  await assert.rejects(async () => {
    await computer.do([{ click: { ref: "e2" } }]);
    await computer.act("click", { ref: "e3" });
  }, error => error.data.completed === 1 && error.result === result);
  assert.deepEqual(calls, ["computer_do"]);
  assert.deepEqual(emitted, result.content);
  assert.equal(computer.observation, undefined);
});

test("refuses overlapping operations instead of racing a window observation", async () => {
  let release;
  const computer = createComputer({ emit: () => {}, call: () => new Promise(resolve => { release = resolve; }) });
  const first = computer.observe();
  await assert.rejects(computer.act("click"), /Await the current/);
  release({ content: [{ type: "text", text: '{"pid":1,"win":2}' }] });
  await first;
  assert.equal(computer.observation.pid, 1);
});

test("a failed image delivery never retries an action", async () => {
  let calls = 0;
  const computer = createComputer({ emit: () => { throw new Error("output disconnected"); }, call: async () => { calls++; return { content: [{ type: "image", data: "after" }] }; } });
  await assert.rejects(computer.act("click"), /output disconnected/);
  assert.equal(calls, 1);
  assert.equal(computer.observation, undefined);
});

for (const status of ["unknown", "unsatisfied"]) {
  test(`verification ${status} halts composed input`, async () => {
    const calls = [];
    const computer = createComputer({ emit: () => {}, call: async name => { calls.push(name); return { content: [], structuredContent: { status } }; } });
    await assert.rejects(async () => {
      await computer.verify([{ text_contains: "Saved" }]);
      await computer.act("click", { label: "Next" });
    }, new RegExp(status));
    assert.deepEqual(calls, ["computer_verify"]);
  });
}

test("a mismatched value readback halts composed input", async () => {
  const computer = createComputer({ emit: () => {}, call: async () => ({ content: [], structuredContent: { status: "ok", effect: "mismatch" } }) });
  await assert.rejects(computer.act("set_value", { label: "Name", args: { value: "Ada" } }), error => error.data.effect === "mismatch");
});
