// Companion mode with an identity of the language's own (beside it,
// companion.identity.json): the package contributes no language and no
// grammar, its settings take the prefix `tally`, and the client is the
// same one, under those names.
module.exports = async (t) => {
  t.set("user", "server.path", "/opt/tally-lsp");
  await t.activate();
  await t.deactivate();
};
