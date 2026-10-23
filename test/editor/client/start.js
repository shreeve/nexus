// The defaults: no settings and no bundled server. The client runs
// `tally-lsp` from PATH for the language's files and unsaved documents,
// in one output channel, and stops on deactivation.
module.exports = async (t) => {
  await t.activate();
  await t.deactivate();
};
