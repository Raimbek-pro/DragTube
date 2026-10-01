// DragTube — content script (YouTube only)
// Hover a video and click the save button on its thumbnail, like YouTube's own "Watch later".
// Keys 4, 5 or 6 open the SwiftUI saved-videos sheet (DragTube app).

(() => {
  if (window.top !== window) return;            // main page only, not iframes/ads

  // When the extension reloads (e.g. a new build from Xcode), Safari injects a fresh copy of
  // this script into open tabs. The old copy can no longer reach the extension, so the new
  // copy tells it to remove its listeners and elements, then takes over.
  document.dispatchEvent(new CustomEvent("dragtube:takeover"));
  const lifetime = new AbortController();
  const signal = lifetime.signal;
  document.addEventListener("dragtube:takeover", () => {
    lifetime.abort();
    saveButton.remove();
    toast.remove();
  }, { once: true, signal });

  const send = (name, info = {}) => {
    try {
      safari.extension.dispatchMessage(name, info);
    } catch (error) {
      console.warn("[DragTube] extension unreachable — reload the page", error);
    }
  };

  // ---------- helpers ----------
  function videoIdFrom(url) {
    try {
      const u = new URL(url, location.origin);
      if (u.hostname === "youtu.be") return u.pathname.slice(1).split("/")[0] || null;
      if (!/(^|\.)youtube\.com$/.test(u.hostname)) return null;
      if (u.pathname === "/watch") return u.searchParams.get("v");
      const m = u.pathname.match(/^\/(shorts|embed|live)\/([\w-]{6,})/);
      return m ? m[2] : null;
    } catch {
      return null;
    }
  }

  // Every kind of video "card" YouTube uses (home grid, search, sidebar, playlists, Shorts,
  // and the hover preview that plays over a thumbnail)
  const CARD_SELECTOR = [
    "ytd-rich-item-renderer", "ytd-rich-grid-media", "ytd-video-renderer",
    "ytd-compact-video-renderer", "ytd-grid-video-renderer", "ytd-playlist-video-renderer",
    "ytd-playlist-panel-video-renderer", "ytd-reel-item-renderer", "yt-lockup-view-model",
    "ytm-shorts-lockup-view-model", "ytd-video-preview"
  ].join(", ");

  // Outermost card under the pointer (cards are nested, e.g. a lockup inside a grid item)
  function cardAt(node) {
    let card = node.closest(CARD_SELECTOR);
    for (let up = card?.parentElement?.closest(CARD_SELECTOR); up; up = up.parentElement?.closest(CARD_SELECTOR)) {
      card = up;
    }
    return card;
  }

  // The card's thumbnail: its biggest visible link to a video. The hover preview's link has
  // no height of its own (the player overflows it), so then the card's box is used instead.
  function thumbnailOf(card) {
    let best = null;
    let bestArea = -1;
    for (const a of card.querySelectorAll("a[href]")) {
      if (!a.offsetParent) continue;            // not displayed
      const id = videoIdFrom(a.href);
      if (!id) continue;
      const rect = a.getBoundingClientRect();
      if (rect.width * rect.height > bestArea) {
        best = { a, id, rect };
        bestArea = rect.width * rect.height;
      }
    }
    if (best && bestArea === 0) best.rect = card.getBoundingClientRect();
    return best;
  }

  // The hover preview has no clean title (its labels add the duration), so the title is read
  // from the video's own card. Empty when unknown: the app then fetches it from YouTube.
  function titleOf(card, id) {
    if (card.matches("ytd-video-preview")) {
      const link = [...document.querySelectorAll(`a[href*="${CSS.escape(id)}"]`)]
        .find(a => !a.closest("ytd-video-preview"));
      card = link && cardAt(link);
      if (!card) return "";
    }
    const title = card.querySelector("#video-title, h3");
    const candidates = [title?.getAttribute("title"), title?.textContent];
    for (const c of candidates) {
      const t = (c || "").replace(/\s+/g, " ").trim();
      if (t) return t.slice(0, 200);
    }
    return "";
  }

  function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // YouTube blocks innerHTML (Trusted Types), so the icon is built node by node
  const SVG = "http://www.w3.org/2000/svg";
  const ICON_SAVE = "M12 4v10m0 0-4-4m4 4 4-4M5 15v2.5A2.5 2.5 0 0 0 7.5 20h9a2.5 2.5 0 0 0 2.5-2.5V15";
  const ICON_SAVED = "M5 12.5l4.5 4.5L19 7.5";

  // ---------- save button (shown on the hovered video) ----------
  const saveButton = el("div", "dragtube-save");
  saveButton.setAttribute("role", "button");
  saveButton.setAttribute("aria-label", "Save to DragTube");
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  const iconPath = document.createElementNS(SVG, "path");
  svg.append(iconPath);
  const saveLabel = el("span", "dragtube-save-label");
  saveButton.append(svg, saveLabel);

  const toast = el("div", "dragtube-toast");

  const savedThisVisit = new Set();
  let hovered = null;       // { card, id }

  function setSaved(saved) {
    iconPath.setAttribute("d", saved ? ICON_SAVED : ICON_SAVE);
    saveLabel.textContent = saved ? "Saved" : "Save";
    saveButton.classList.toggle("dragtube-saved", saved);
  }

  // The button goes inside the card (in the thumbnail's positioned box), so YouTube still
  // counts the pointer as over the video and its hover preview keeps playing
  function showSaveButton(card) {
    const thumb = thumbnailOf(card);
    let box = thumb?.a.offsetParent;
    if (box && !card.contains(box)) box = getComputedStyle(card).position !== "static" ? card : null;
    if (!thumb || !box) return hideSaveButton();

    // The hover preview is a bit bigger than the thumbnail it covers. Pin the button to the
    // original thumbnail's corner so it doesn't jump when the preview starts playing.
    const anchor = card.matches("ytd-video-preview") ? originalThumbnailRect(thumb.id) ?? thumb.rect : thumb.rect;
    const boxRect = box.getBoundingClientRect();
    saveButton.style.left = `${anchor.left - boxRect.left - box.clientLeft + 8}px`;
    saveButton.style.top = `${anchor.top - boxRect.top - box.clientTop + 8}px`;
    setSaved(savedThisVisit.has(thumb.id));
    if (saveButton.parentNode !== box) box.append(saveButton);
    hovered = { card, id: thumb.id };
  }

  // Box of the biggest visible link to this video outside the hover preview (its thumbnail)
  function originalThumbnailRect(id) {
    let best = null;
    let bestArea = 0;
    for (const a of document.querySelectorAll(`a[href*="${CSS.escape(id)}"]`)) {
      if (!a.offsetParent || a.closest("ytd-video-preview")) continue;
      const rect = a.getBoundingClientRect();
      if (rect.width * rect.height > bestArea) {
        best = rect;
        bestArea = rect.width * rect.height;
      }
    }
    return best;
  }

  function hideSaveButton() {
    saveButton.remove();
    hovered = null;
  }

  function showToast(msg) {
    toast.textContent = msg;
    toast.classList.add("dragtube-show");
    clearTimeout(showToast.t);
    showToast.t = setTimeout(() => toast.classList.remove("dragtube-show"), 2200);
  }

  document.addEventListener("mouseover", e => {
    if (!(e.target instanceof Element) || saveButton.contains(e.target)) return;
    const card = cardAt(e.target);
    if (card && card === hovered?.card && saveButton.isConnected) return;
    if (card) showSaveButton(card); else hideSaveButton();
  }, { capture: true, signal });

  // Keep presses on the button away from YouTube (opening the video, the hover preview…)
  for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "dblclick"]) {
    saveButton.addEventListener(type, e => e.stopPropagation(), { signal });
  }

  saveButton.addEventListener("click", e => {
    e.preventDefault();                          // it sits inside a link to the video
    e.stopPropagation();
    if (!hovered) return;

    const { card, id } = hovered;
    const title = titleOf(card, id);
    send("save", { id, title });                 // Swift saves it

    savedThisVisit.add(id);
    setSaved(true);
    showToast(title ? `Saved “${title.slice(0, 60)}” — press 5 to view` : "Saved — press 5 to view");
  }, { signal });

  // ---------- 4 / 5 / 6 → SwiftUI saved-videos sheet ----------
  // On YouTube these keys normally jump to 40/50/60% of the video; DragTube takes them over.
  // Pressing one again while the sheet is open closes it.
  const SHEET_KEYS = new Set(["Digit4", "Digit5", "Digit6", "Numpad4", "Numpad5", "Numpad6"]);

  // Listen on window (capture) so YouTube's own shortcut handlers never see these keys
  window.addEventListener("keydown", e => {
    if (!SHEET_KEYS.has(e.code)) return;
    if (e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;

    const t = e.target;
    const typing = t instanceof HTMLElement &&
      (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
    if (typing) return;                         // search box, comments: type numbers normally

    e.preventDefault();
    e.stopImmediatePropagation();
    if (!e.repeat) send("openSheet");
  }, { capture: true, signal });

  // ---------- mount ----------
  function mount() {
    if (!document.body) return requestAnimationFrame(mount);
    document.body.append(toast);
  }
  mount();
})();
