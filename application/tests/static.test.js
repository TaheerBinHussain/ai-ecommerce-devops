const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { SRC } = require("./helpers");

const pages = ["index.html", "products.html", "payment.html"];

test("all storefront pages exist", () => {
  for (const page of pages) {
    assert.ok(fs.existsSync(path.join(SRC, page)), `${page} is missing`);
  }
});

test("every local href/src referenced by a page exists", () => {
  for (const page of pages) {
    const html = fs.readFileSync(path.join(SRC, page), "utf8");
    const refs = [...html.matchAll(/(?:href|src)="([^"]+)"/g)].map((m) => m[1]);
    for (const ref of refs) {
      if (/^(https?:|mailto:|tel:|#|javascript:)/.test(ref)) continue;
      const file = ref.split(/[?#]/)[0];
      if (!file) continue;
      assert.ok(fs.existsSync(path.join(SRC, file)), `${page} references missing file ${ref}`);
    }
  }
});

test("all JavaScript files are syntactically valid", () => {
  for (const file of fs.readdirSync(SRC).filter((f) => f.endsWith(".js"))) {
    const code = fs.readFileSync(path.join(SRC, file), "utf8");
    assert.doesNotThrow(() => new vm.Script(code, { filename: file }), `${file} has a syntax error`);
  }
});

test("every page declares a title and viewport for mobile", () => {
  for (const page of pages) {
    const html = fs.readFileSync(path.join(SRC, page), "utf8");
    assert.match(html, /<title>[^<]+<\/title>/, `${page} has no <title>`);
    assert.match(html, /name="viewport"/, `${page} has no viewport meta`);
  }
});
