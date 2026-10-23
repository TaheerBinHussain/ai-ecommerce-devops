// Loads a browser script into a sandbox with a minimal DOM stub so its
// top-level declarations (product catalogue, helpers) can be unit tested.
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const SRC = path.join(__dirname, "..", "src");

function loadBrowserScript(file, exportNames) {
  const store = new Map();
  const noop = () => {};
  const element = () => null;
  const context = {
    console,
    Intl,
    document: {
      querySelector: element,
      querySelectorAll: () => [],
      addEventListener: noop,
      getElementById: element
    },
    window: { scrollTo: noop, location: { search: "", href: "" } },
    location: { search: "", href: "" },
    URLSearchParams,
    localStorage: {
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => store.set(k, String(v)),
      removeItem: (k) => store.delete(k)
    },
    setTimeout,
    clearTimeout
  };
  vm.createContext(context);
  const code = fs.readFileSync(path.join(SRC, file), "utf8");
  // const/let declarations are not attached to the context, so expose them explicitly.
  const exporter = `;globalThis.__exports = { ${exportNames.join(", ")} };`;
  vm.runInContext(code + exporter, context, { filename: file });
  return context.__exports;
}

module.exports = { SRC, loadBrowserScript };
