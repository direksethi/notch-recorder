interface ChromeWindow {
  webkit?: { messageHandlers?: { chrome?: { postMessage: (body: unknown) => void } } }
}

const interactive = "button, a, input, textarea, select, [role='button'], [role='menu'], [contenteditable='true']"

/**
 * The web view fills the whole window, title bar included, so empty space in
 * any `[data-titlebar]` region asks the native side to drag or zoom the
 * window, matching a standard title bar.
 */
export const installTitlebar = () => {
  const chrome = (window as ChromeWindow).webkit?.messageHandlers?.chrome
  if (!chrome) return
  document.addEventListener("mousedown", (e) => {
    if (e.button !== 0 || !(e.target instanceof Element)) return
    if (!e.target.closest("[data-titlebar]") || e.target.closest(interactive)) return
    e.preventDefault()
    chrome.postMessage(e.detail === 2 ? "zoom" : "drag")
  })
}
