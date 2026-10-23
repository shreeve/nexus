// Restarts: a change to another extension's setting restarts nothing;
// changes that come together start one client; a change while a client
// starts waits for it, so two clients never start at once; the output
// channel is created once.
module.exports = async (t) => {
  await t.activate();
  await t.elsewhere("editor.fontSize");
  t.note("two changes together: one restart");
  const first = t.change("user", "server.path", "/opt/one");
  const second = t.change("user", "server.root", "/b.tally");
  await Promise.all([first, second]);
  t.note("a change while a client starts: the next restart waits for it");
  const release = t.hold();
  await t.change("user", "server.path", "/opt/two");
  const later = t.change("user", "server.path", "/opt/three");
  await t.settle();
  release();
  await later;
  await t.settle();
  await t.deactivate();
};
