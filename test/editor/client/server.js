// Which server runs: the user setting, else the bundled bin/tally-lsp,
// else tally-lsp on PATH. A workspace's setting is never run, trusted or
// not.
module.exports = async (t) => {
  t.bundle();
  t.set("workspace", "server.path", "/workspace/says/run-me");
  await t.activate();
  t.note("a workspace's server.path is never the server, trusted or not");
  await t.change("workspace", "server.path", "/workspace/says/run-me-too");
  t.trust(false);
  await t.change("workspace", "server.path", "/untrusted/run-me");
  t.note("the user's own setting is the server");
  await t.change("user", "server.path", "/opt/tally/bin/tally-lsp");
  t.trust(true);
  await t.change("user", "server.path", "");
  await t.deactivate();
};
