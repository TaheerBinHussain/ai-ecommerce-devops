const test = require("node:test");
const assert = require("node:assert");
const { loadBrowserScript } = require("./helpers");

const { products, money, escapeHTML } = loadBrowserScript("script.js", ["products", "money", "escapeHTML"]);

test("catalogue contains 12 products", () => {
  assert.strictEqual(products.length, 12);
});

test("every product has the fields the UI depends on", () => {
  for (const p of products) {
    assert.ok(Number.isInteger(p.id), `product without numeric id: ${p.name}`);
    assert.ok(p.name && p.category && p.image, `incomplete product ${p.id}`);
    assert.ok(typeof p.price === "number" && p.price > 0, `invalid price for ${p.name}`);
    assert.strictEqual(typeof p.stock, "boolean", `stock flag missing for ${p.name}`);
  }
});

test("product ids are unique", () => {
  const ids = products.map((p) => p.id);
  assert.strictEqual(new Set(ids).size, ids.length);
});

test("prices are formatted as Indian rupees", () => {
  assert.match(money(2999), /₹\s?2,999/);
  assert.match(money("bad"), /₹\s?0/);
});

test("escapeHTML neutralises markup (XSS guard)", () => {
  assert.strictEqual(escapeHTML('<img src=x onerror="a">'), "&lt;img src=x onerror=&quot;a&quot;&gt;");
});
