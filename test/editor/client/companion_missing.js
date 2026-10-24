// Companion mode with no extension that contributes the language (the
// one it goes beside, its identity's `provider`, is not installed): VS
// Code knows no `tally`, so no file is ever one. At start-up the
// extension says so, naming that extension and how to do without it,
// and starts no server; a setting changed then starts none either.
module.exports = async (t) => {
  t.languages(["plaintext", "typescript"]);
  t.documents([]);
  await t.activate();
  await t.open("typescript");
  await t.change("user", "server.path", "/opt/tally-lsp");
  await t.deactivate();
};
