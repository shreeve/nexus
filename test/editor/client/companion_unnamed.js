// Companion mode with no `provider` in its identity and no extension
// that contributes the language: the message says so without a name.
module.exports = async (t) => {
  t.languages(["plaintext"]);
  t.documents([]);
  await t.activate();
  await t.deactivate();
};
