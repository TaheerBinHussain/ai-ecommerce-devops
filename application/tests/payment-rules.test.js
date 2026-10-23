// The checkout validation rules from payment.js, checked against the
// requirements listed in the application README.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { SRC } = require("./helpers");

const code = fs.readFileSync(path.join(SRC, "payment.js"), "utf8");

function rule(source) {
  assert.ok(code.includes(source), `payment.js no longer contains rule ${source}`);
  return new RegExp(source.slice(1, -1));
}

test("phone must be exactly 10 digits", () => {
  const r = rule("/^\\d{10}$/");
  assert.ok(r.test("9876543210"));
  assert.ok(!r.test("98765"));
  assert.ok(!r.test("98765432101"));
});

test("PIN must be exactly 6 digits", () => {
  const r = rule("/^\\d{6}$/");
  assert.ok(r.test("560001"));
  assert.ok(!r.test("5600"));
});

test("card number must be 16 digits and CVV 3 digits", () => {
  assert.ok(rule("/^\\d{16}$/").test("4111111111111111"));
  assert.ok(!rule("/^\\d{3}$/").test("12"));
});

test("card expiry must be MM/YY", () => {
  const r = rule("/^(0[1-9]|1[0-2])\\/\\d{2}$/");
  assert.ok(r.test("09/28"));
  assert.ok(!r.test("13/28"));
});

test("UPI id must look like name@bank", () => {
  const r = rule("/^[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}$/");
  assert.ok(r.test("nexvion@okaxis"));
  assert.ok(!r.test("nexvion"));
});
