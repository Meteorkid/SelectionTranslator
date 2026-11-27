let floatingButton = null;

function removeButton() {
  if (floatingButton) {
    floatingButton.remove();
    floatingButton = null;
  }
}

function buildContext(selectionText) {
  const anchor = window.getSelection()?.anchorNode;
  let node = anchor?.nodeType === Node.TEXT_NODE ? anchor.parentElement : anchor;
  let paragraph = "";

  while (node && node !== document.body) {
    if (node.innerText && node.innerText.trim().length >= selectionText.length) {
      paragraph = node.innerText.trim();
      break;
    }
    node = node.parentElement;
  }

  if (!paragraph) {
    paragraph = document.body?.innerText?.trim() || "";
  }

  const index = paragraph.indexOf(selectionText);
  if (index >= 0) {
    const before = paragraph.slice(Math.max(0, index - 900), index);
    const after = paragraph.slice(index + selectionText.length, index + selectionText.length + 900);
    return (before + selectionText + after).trim();
  }
  return paragraph.slice(0, 1800);
}

function buildDocumentContext() {
  const body = document.body?.innerText?.trim() || "";
  return body.slice(0, 6000);
}

function translateCurrentSelection() {
  const selection = window.getSelection();
  const text = selection?.toString().trim() || "";
  if (!text) return false;

  const context = buildContext(text).slice(0, 1800);
  const documentContext = buildDocumentContext();
  const url = new URL("selectiontranslator://translate");
  url.searchParams.set("text", text.slice(0, 8000));
  url.searchParams.set("context", context);
  url.searchParams.set("document", documentContext);
  const browserName = /Edg\//.test(navigator.userAgent) ? "Edge" : "Chrome";
  url.searchParams.set("app", browserName);
  url.searchParams.set("title", document.title || "");
  url.searchParams.set("source", "browser");

  removeButton();
  const target = url.toString();
  try {
    const sent = chrome.runtime.sendMessage({ type: "selectiontranslator-open", url: target });
    if (sent && typeof sent.catch === "function") {
      sent.catch(() => window.open(target, "_blank", "noopener,noreferrer"));
    }
  } catch (_) {
    window.open(target, "_blank", "noopener,noreferrer");
  }
  return true;
}

function showButton() {
  const selection = window.getSelection();
  const text = selection?.toString().trim() || "";
  if (!text || text.length > 8000) {
    removeButton();
    return;
  }

  const range = selection.rangeCount ? selection.getRangeAt(0) : null;
  const rect = range?.getBoundingClientRect();
  if (!rect) return;

  removeButton();
  const button = document.createElement("button");
  button.className = "selectiontranslator-fab";
  button.type = "button";
  button.title = "用 SelectionTranslator 翻译";
  button.textContent = "译";
  button.addEventListener("mousedown", (event) => event.preventDefault());
  button.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    translateCurrentSelection();
  });

  const x = Math.min(Math.max(rect.right + 10, 8), window.innerWidth - 44);
  const y = Math.min(Math.max(rect.bottom + 8, 8), window.innerHeight - 44);
  button.style.left = `${x}px`;
  button.style.top = `${y}px`;
  document.documentElement.appendChild(button);
  floatingButton = button;
}

document.addEventListener("mouseup", () => {
  window.setTimeout(showButton, 80);
});
document.addEventListener("mousedown", removeButton);
window.addEventListener("scroll", removeButton, { passive: true });
window.addEventListener("blur", removeButton);

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "selectiontranslator-translate") {
    sendResponse({ ok: translateCurrentSelection() });
  }
});
