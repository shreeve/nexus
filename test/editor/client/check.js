// server.check reaches the server from the user's own settings alone, and
// only in a trusted workspace; granting trust restarts the server with it.
// server.checkTimeout and features reach it too, and a change to either
// restarts it.
module.exports = async (t) => {
  t.set("workspace", "server.check", ["workspace", "says", "${file}"]);
  t.set("user", "server.check", ["zig", "build-obj", "-fno-emit-bin", "${file}"]);
  t.trust(false);
  await t.activate();
  t.note("trusted, the user's check runs; a workspace's never");
  await t.grant();
  await t.change("workspace", "server.checkTimeout", 5000);
  await t.change("user", "features", ["semanticTokens", "folding", "check"]);
  await t.change("user", "server.check", []);
  await t.deactivate();
};
