// server.modules, the files of module names an import names, reaches the
// server with each file absolute: a relative one is relative to the first
// workspace folder, and one that is no file name is left out.
module.exports = async (t) => {
  t.folders(["app", "lib"]);
  t.set("user", "server.modules", { std: "zig/std.zig", core: "/abs/core.tally", none: "" });
  await t.activate();
  await t.change("workspace", "server.modules", {});
  await t.deactivate();
};
