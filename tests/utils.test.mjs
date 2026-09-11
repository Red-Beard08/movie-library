import test from "node:test";
import assert from "node:assert/strict";

const normalize = value => value.trim().replace(/\s+/g, " ").toLocaleLowerCase();
const safe = value => value.trim().replace(/[\\/:*?"<>|#[\]]/g, "-").replace(/\s+/g, " ").slice(0, 76) || "Untitled";
const parseRuntime = value => { const match = value.match(/\d+/); return match ? Number(match[0]) : null; };
test("normalizes duplicate titles", () => assert.equal(normalize("  The   Matrix "), "the matrix"));
test("creates safe portable filenames", () => assert.equal(safe("A/B: C?"), "A-B- C-"));
test("converts OMDb runtime to minutes", () => assert.equal(parseRuntime("136 min"), 136));
test("handles unknown runtime", () => assert.equal(parseRuntime("N/A"), null));
