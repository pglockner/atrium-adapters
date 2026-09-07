# Computer client for a host code executor

Define the function below in the host's executor, or extract this code block and import it as an ES module. Map `call` to the six actual atrium computer tools and `emit` to the host's image/text output functions. This helper has no native input access of its own. Errors carry the original result and never trigger input retries.

```js
/*
Map computerTools to the host's actual discovered tool functions, then:
const computer = createComputer({
  call: (name, args) => computerTools[name](args),
  emit: block => block.type === "image" ? image(block) : text(block.text),
  target: { app: "Contacts" }, output: { maxLongEdge: 1568 }
});
await computer.observe(); // Inspect the output before choosing input.
// Methods: act(tool, options), do(steps, options), verify(expect, options),
// zoom(corners), end(). In a new executor, target {pid, windowId: win}.
*/
export function createComputer({ call, emit, target = {}, output = {} }) {
  if (typeof call !== "function" || typeof emit !== "function") {
    throw new TypeError("Provide call(name, args) and emit(contentBlock) functions.");
  }
  let observation;
  let busy = false;
  let bound = { ...target };

  async function run(verb, args = {}) {
    if (busy) throw new Error("Await the current computer call before starting another.");
    busy = true;
    try {
      const result = await call(`computer_${verb}`, {
        ...output, ...args, ...(verb === "end" ? {} : bound),
      });
      const content = result.content ?? [];
      // Emit evidence before throwing so a partial action never loses its image.
      for (const block of content) await emit(block);
      let data = result.structuredContent;
      if (!data) {
        for (const block of content) {
          if (block.type !== "text") continue;
          try { data = JSON.parse(block.text); } catch { /* Older hosts may omit structured results. */ }
        }
      }
      const next = verb === "observe" ? data : data?.after ?? data?.finalObservation;
      if (next?.pid != null && next?.win != null) {
        bound = { pid: next.pid, windowId: next.win };
        observation = next;
      } else if (["observe", "act", "do", "zoom", "end"].includes(verb)) {
        observation = undefined;
      }
      const failedVerification = verb === "verify" && data?.status !== "satisfied";
      if (result.isError || data?.status === "error" || data?.effect === "mismatch" || failedVerification) {
        const message = failedVerification ? `Verification was ${data?.status ?? "unavailable"}.` : data?.message;
        const error = new Error(message ?? (content.filter(block => block.type === "text").map(block => block.text).join("\n") || "Computer call failed."));
        error.result = result;
        error.data = data;
        throw error;
      }
      if (verb === "end") bound = { ...target };
      return data ?? result;
    } catch (error) {
      // A transport/emit failure can happen after input landed. Never replay it.
      observation = undefined;
      throw error;
    } finally {
      busy = false;
    }
  }

  return Object.freeze({
    get observation() { return observation; },
    observe: (options) => run("observe", options),
    act: (tool, args = {}) => run("act", { ...args, tool }),
    do: (steps, options = {}) => run("do", { ...options, steps }),
    verify: (expect, options = {}) => run("verify", { ...options, expect }),
    zoom: (corners) => run("zoom", corners),
    end: () => run("end"),
  });
}
```
