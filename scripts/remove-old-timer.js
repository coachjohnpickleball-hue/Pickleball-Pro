const fs = require("fs");
const path = require("path");

const files = [
  "public/index.html",
  "dist/index.html",
  "worker/src/app.html",
];

function removeBalancedDivById(html, id) {
  const starts = [
    `<div id="${id}"`,
    `<div id='${id}'`,
  ];

  let start = -1;
  for (const needle of starts) {
    start = html.indexOf(needle);
    if (start >= 0) break;
  }

  if (start < 0) return { html, removed: false };

  const tagRe = /<\/?div\b[^>]*>/gi;
  tagRe.lastIndex = start;

  let depth = 0;
  let m;

  while ((m = tagRe.exec(html))) {
    if (m[0].startsWith("</")) {
      depth--;
      if (depth === 0) {
        return {
          html: html.slice(0, start) + "\n" + html.slice(tagRe.lastIndex),
          removed: true,
        };
      }
    } else {
      depth++;
    }
  }

  return { html, removed: false };
}

function removeButtonById(html, id) {
  return html.replace(
    new RegExp(String.raw`\s*<button\b[^>]*id=["']${id}["'][\s\S]*?<\/button>\s*`, "gi"),
    "\n"
  );
}

function installKillSwitch(html) {
  const css = `
<style id="pp-remove-old-global-timer-css">
#global-round-timer,
#global-timer-menu-toggle,
#pb-floating-round-timer,
#pb-floating-timer-show {
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
}
</style>`;

  const js = `
<script id="pp-remove-old-global-timer-js">
(function(){
  function removeOldTimers(){
    try {
      ["global-round-timer","global-timer-menu-toggle","pb-floating-round-timer","pb-floating-timer-show","pb-round-timer-menu-item"].forEach(function(id){
        var el = document.getElementById(id);
        if(el) el.remove();
      });

      Array.from(document.querySelectorAll("*")).forEach(function(el){
        var id = String(el.id || "").toLowerCase();
        var text = String(el.textContent || "").trim();
        var style = window.getComputedStyle(el);

        if(id === "global-round-timer" || id === "pb-floating-round-timer") {
          el.remove();
          return;
        }

        if(style.position === "fixed" && /round timer/i.test(text)) {
          el.remove();
        }
      });

      [
        "pb_safe_floating_timer_v1",
        "pb_floating_timer_visible_v1",
        "pb_floating_timer_seconds_v1",
        "pb_round_timer_visible_clean_v1",
        "pb_round_timer_seconds_clean_v1"
      ].forEach(function(k){
        try { localStorage.removeItem(k); } catch(e) {}
      });

      window.grtToggleVisible = function(){ removeOldTimers(); };
      window.grtInitFloatingTimer = function(){ removeOldTimers(); };
      window.grtShow = function(){ removeOldTimers(); };
      window.grtHide = function(){ removeOldTimers(); };
    } catch(e) {}
  }

  if(document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", removeOldTimers);
  } else {
    removeOldTimers();
  }

  setTimeout(removeOldTimers, 100);
  setTimeout(removeOldTimers, 500);
  setTimeout(removeOldTimers, 1500);
  setTimeout(removeOldTimers, 3000);
  setInterval(removeOldTimers, 2000);

  try {
    new MutationObserver(removeOldTimers).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  } catch(e) {}
})();
</script>`;

  html = html.replace(/<style id=["']pp-remove-old-global-timer-css["'][\s\S]*?<\/style>/gi, "");
  html = html.replace(/<script id=["']pp-remove-old-global-timer-js["'][\s\S]*?<\/script>/gi, "");

  if (html.includes("</head>")) {
    html = html.replace("</head>", css + "\n</head>");
  } else {
    html = css + "\n" + html;
  }

  if (html.includes("</body>")) {
    html = html.replace("</body>", js + "\n</body>");
  } else {
    html += "\n" + js;
  }

  return html;
}

for (const file of files) {
  const full = path.resolve(file);
  if (!fs.existsSync(full)) continue;

  let html = fs.readFileSync(full, "utf8");
  const before = html;

  for (const id of ["global-round-timer", "pb-floating-round-timer"]) {
    let result;
    do {
      result = removeBalancedDivById(html, id);
      html = result.html;
    } while (result.removed);
  }

  html = removeButtonById(html, "global-timer-menu-toggle");
  html = removeButtonById(html, "pb-floating-timer-show");
  html = removeButtonById(html, "pb-round-timer-menu-item");

  html = html.replace(/\s*<button\b[^>]*>\s*⏱\s*Round Timer\s*<\/button>\s*/gi, "\n");

  html = installKillSwitch(html);

  fs.writeFileSync(full, html);

  console.log(`${file}: changed=${html !== before}`);
  console.log(`  global-round-timer count: ${(html.match(/global-round-timer/g) || []).length}`);
  console.log(`  kill-switch count: ${(html.match(/pp-remove-old-global-timer-js/g) || []).length}`);
}
