// server.root reaches the server absolute: a relative root is relative
// to the first workspace folder, and without a folder it is left out
// with a warning.
module.exports = async (t) => {
  t.folders(["app", "lib"]);
  t.set("workspace", "server.root", "src/main.tally");
  await t.activate();
  await t.change("workspace", "server.root", "/abs/main.tally");
  await t.change("workspace", "server.root", "");
  t.folders([]);
  await t.change("workspace", "server.root", "main.tally");
  await t.deactivate();
};
