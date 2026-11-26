const api = globalThis.browser ?? globalThis.chrome;

api.runtime.onMessage.addListener((message) => {
  if (message?.type !== "selectiontranslator-open" || !message.url) return;
  return api.tabs.create({ url: message.url }).then(
    () => ({ ok: true }),
    () => ({ ok: false })
  );
});
