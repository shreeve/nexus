// A server that does not start: the client is disposed, the user is told
// how to set the server, and a later change starts a new client.
module.exports = async (t) => {
  t.failStart("spawn tally-lsp ENOENT");
  await t.activate();
  await t.change("user", "server.path", "/opt/tally-lsp");
  await t.deactivate();
};
