// DragTube — content script (YouTube only)
// Shows the drop zone while you drag a video. Saving and the saved list are native Swift.
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
    zone.remove();
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

  function titleFromAnchor(a) {
    const card = a.closest(
      "ytd-rich-item-renderer, ytd-video-renderer, ytd-compact-video-renderer, " +
      "ytd-grid-video-renderer, ytd-playlist-video-renderer, ytd-reel-item-renderer, " +
      "yt-lockup-view-model, ytm-shorts-lockup-view-model, ytd-playlist-panel-video-renderer"
    );
    const candidates = [
      a.getAttribute("title"),
      card?.querySelector("#video-title")?.textContent,
      card?.querySelector("h3")?.textContent,
      a.getAttribute("aria-label"),
      a.textContent
    ];
    for (const c of candidates) {
      const t = (c || "").replace(/\s+/g, " ").trim();
      if (t) return t.slice(0, 200);
    }
    return "";
  }

  // Title of the video on the current watch page (for links to the page you're on)
  function currentPageTitle(id) {
    if (videoIdFrom(location.href) !== id) return "";
    const h = document.querySelector("ytd-watch-metadata h1, h1.ytd-watch-metadata, #title h1");
    return (h?.textContent || document.title.replace(/ - YouTube$/, "")).trim().slice(0, 200);
  }

  function urlFromDataTransfer(dt) {
    const raw = (dt.getData("text/uri-list") || dt.getData("text/plain") || "")
      .split("\n").map(s => s.trim()).find(s => s && !s.startsWith("#"));
    return raw || "";
  }

  function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // ---------- drop zone ----------
  const zone = el("div", "dragtube-zone");
  const inner = el("div", "dragtube-zone-inner");
  const icon = el("div", "dragtube-zone-icon", "＋");
  const label = el("div", "dragtube-zone-label", "Drop to save");
  const hint = el("div", "dragtube-zone-hint", "Press 5 to view");
  inner.append(icon, label, hint);
  zone.append(inner);

  const toast = el("div", "dragtube-toast");

  let dragged = null;       // video being dragged from this page
  let visible = false;
  let hideTimer = null;

  function showZone() {
    clearTimeout(hideTimer);
    zone.classList.remove("dragtube-done", "dragtube-error");
    icon.textContent = "＋";
    label.textContent = "Drop to save";
    zone.classList.add("dragtube-show");
    visible = true;
  }

  function hideZone(delay = 0) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      zone.classList.remove("dragtube-show", "dragtube-hover");
      visible = false;
    }, delay);
  }

  function showToast(msg) {
    toast.textContent = msg;
    toast.classList.add("dragtube-show");
    clearTimeout(showToast.t);
    showToast.t = setTimeout(() => toast.classList.remove("dragtube-show"), 2200);
  }

  // 1) Dragging any video link/thumbnail on YouTube
  document.addEventListener("dragstart", e => {
    const target = e.target instanceof Element ? e.target : e.target?.parentElement;
    const a = target?.closest?.("a[href]");
    let id = a ? videoIdFrom(a.href) : null;

    // Not a link? Maybe the dragged data itself is a YouTube URL
    if (!id && e.dataTransfer) id = videoIdFrom(urlFromDataTransfer(e.dataTransfer));
    if (!id) return;

    dragged = { id, title: (a && titleFromAnchor(a)) || currentPageTitle(id) };
    showZone();
  }, { capture: true, signal });

  // 2) Dragging from anywhere else: another tab, the address bar, Notes, Messages…
  document.addEventListener("dragenter", e => {
    if (visible) { clearTimeout(hideTimer); return; }
    const types = Array.from(e.dataTransfer?.types || []);
    if (types.includes("text/uri-list") || types.includes("text/plain")) showZone();
  }, { capture: true, signal });

  // While the pointer is still over the page, dragover keeps firing → keep the zone up
  document.addEventListener("dragover", () => {
    if (visible && !zone.classList.contains("dragtube-done")) clearTimeout(hideTimer);
  }, { capture: true, signal });

  // Pointer may have left the window during an outside drag; hide unless dragover cancels it
  document.addEventListener("dragleave", () => {
    if (!dragged && visible) hideZone(250);
  }, { capture: true, signal });

  document.addEventListener("dragend", () => {
    dragged = null;
    if (!zone.classList.contains("dragtube-done")) hideZone(120);
  }, { capture: true, signal });

  document.addEventListener("drop", () => {
    if (!zone.classList.contains("dragtube-done")) hideZone(120);
  }, { capture: true, signal });

  zone.addEventListener("dragenter", e => {
    e.preventDefault();
    clearTimeout(hideTimer);
    zone.classList.add("dragtube-hover");
  });

  zone.addEventListener("dragover", e => {
    e.preventDefault();
    clearTimeout(hideTimer);
    e.dataTransfer.dropEffect = "copy";
  });

  zone.addEventListener("dragleave", e => {
    if (!zone.contains(e.relatedTarget)) zone.classList.remove("dragtube-hover");
  });

  zone.addEventListener("drop", e => {
    e.preventDefault();
    e.stopPropagation();
    zone.classList.remove("dragtube-hover");

    let item = dragged;
    if (!item) {
      const id = videoIdFrom(urlFromDataTransfer(e.dataTransfer));
      if (id) item = { id, title: currentPageTitle(id) };
    }
    dragged = null;

    if (!item) {
      zone.classList.add("dragtube-error");
      icon.textContent = "✕";
      label.textContent = "Not a YouTube video";
      hideZone(1000);
      return;
    }

    send("save", { id: item.id, title: item.title || "" });   // Swift saves it

    zone.classList.add("dragtube-done");
    icon.textContent = "✓";
    label.textContent = "Saved!";
    showToast(item.title ? `Saved “${item.title.slice(0, 60)}” — press 5 to view` : "Saved — press 5 to view");
    hideZone(900);
  });

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
    document.body.append(zone, toast);
  }
  mount();
})();
