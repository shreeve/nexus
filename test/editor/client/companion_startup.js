// Companion mode, activated at start-up with no file of the language
// open: the language is known (its extension is installed), so nothing
// is said, and the server starts at the first of its files, once. A
// setting changed before then starts nothing; one changed after
// restarts it.
module.exports = async (t) => {
  t.documents(["plaintext"]);
  await t.activate();
  await t.change("user", "server.path", "/opt/tally-lsp");
  await t.open("plaintext");
  await t.open("tally");
  await t.open("tally");
  await t.change("user", "features", ["semanticTokens"]);
  await t.deactivate();
};
