// InGe+ — Responsive contextual Dock. No APK/build needed.
// Run: node tests/dock/contextual_large_screen_static.cjs
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("node:assert/strict");
const home = fs.readFileSync(path.join(__dirname, "..", "..", "qml", "Mobile", "HomeScreen.qml"), "utf8");
const check = (name, expected) => { assert.ok(expected, name); console.log("PASS", name); };

check("Qt Quick Screen attached properties imported", home.includes("import QtQuick.Window"));
check("tablet / unfolded foldable only; not desktop and never home Dock",
      /expandedContextDock:\s*Qt\.platform\.os\s*===\s*"android"/.test(home)
      && /Math\.min\(Screen\.width, Screen\.height\) >= 600/.test(home)
      && /&& dockMode === "subapp"/.test(home));
check("context dock and + share a centered, width-limited group",
      home.includes("Math.min(420 * u, Math.max(0, width - 2 * gutter))")
      && home.includes("(home.width - home.expandedDockGroupWidth) / 2")
      && home.includes("dock.x + dock.width + home.expandedDockPlusGap"));
check("phones retain original Dock positioning and standard cell sizing",
      home.includes(": plusButton.x - 24 * home.u - width")
      && home.includes(": home.width - home.gutter - width")
      && home.includes(": dockIconSize + 20 * u")
      && home.includes("(expandedContextDock ? 58 : 64) * u"));
check("expanded dock uses compact icons and plus control",
      home.includes("expandedDockPlusWidth: 62 * u")
      && home.includes("expandedContextDock ? 32 * u")
      && home.includes("width: home.expandedContextDock ? home.expandedDockPlusWidth : 68 * home.u"));
check("button actions and contextual model untouched",
      home.includes("home.dockSlotTap(modelData, pressGeneration")
      && home.includes("home.openAdd()")
      && home.includes("dockDisplayedSlots = dockSlots"));

function expanded(os, screenW, screenH, mode) {
  return os === "android" && screenW > 0 && screenH > 0
    && Math.min(screenW, screenH) >= 600 && mode === "subapp";
}
for (const [label, os, w, h, mode, expectation] of [
  ["phone portrait", "android", 390, 844, "subapp", false],
  ["phone landscape", "android", 844, 390, "subapp", false],
  ["folded foldable cover", "android", 430, 932, "subapp", false],
  ["unfolded foldable", "android", 820, 900, "subapp", true],
  ["tablet portrait", "android", 800, 1280, "subapp", true],
  ["tablet landscape", "android", 1280, 800, "subapp", true],
  ["tablet home preset", "android", 1280, 800, "home", false],
  ["desktop wide monitor", "windows", 1280, 800, "subapp", false],
]) {
  assert.equal(expanded(os, w, h, mode), expectation, label);
}
console.log("PASS 8 viewport/form-factor fixtures");

function layout(width, u, gutter, slotCount) {
  const total = Math.min(420*u, Math.max(0, width - 2*gutter));
  const gap = 12*u, plus = 62*u;
  const cell = (total - plus - gap - 16*u - Math.max(0,slotCount-1)) / Math.max(1,slotCount);
  const capsule = Math.max(1,slotCount)*cell + Math.max(0,slotCount-1) + 16*u;
  const x = (width-total)/2, plusX=x+capsule+gap;
  return {total, cell, capsule, x, plusX, right:plusX+plus, center:(x+plusX+plus)/2};
}
for (const [label,width,u,gutter,slots] of [
  ["foldable",820,1.333,24,4],
  ["tablet landscape",1280,1.333,24,4],
  ["tablet narrow multiwindow",420,1.077,19,4],
  ["tablet navigation without slots",800,1.333,24,1],
]) {
  const v=layout(width,u,gutter,slots);
  assert.ok(v.cell > 0, label + " positive cell width");
  assert.ok(v.x >= gutter-0.001, label + " left safe margin");
  assert.ok(v.right <= width-gutter+0.001, label + " right safe margin");
  assert.ok(Math.abs(v.center-width/2)<0.001, label + " centered");
}
console.log("PASS 4 responsive geometry fixtures");
