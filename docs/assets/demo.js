// Live demo window on the home page.
// CSDemo.mount(el, { onUpdate }) fills el with a clickable Cursor window under a CursorStack strip.
// start() begins the background agents; call it once the demo is on screen.
window.CSDemo = (() => {
  const empty = () => `<p class="csd-msg bot" style="color:#8a8a8a">No chat running in this window.</p>`;
  const projects = () => [
    { id: "web", state: "idle", file: "checkout.tsx",
      tree: ["src/", "app/", "checkout.tsx", "cart.tsx", "lib/", "tax.ts", "package.json"], on: 2, mods: [2, 5],
      code: [
        '<span class="k">import</span> { <span class="v">useCart</span> } <span class="k">from</span> <span class="s">"@/lib/cart"</span>',
        '',
        '<span class="k">export default function</span> <span class="f">Checkout</span>() {',
        '  <span class="k">const</span> { <span class="v">items</span>, <span class="v">total</span> } = <span class="f">useCart</span>()',
        '+  <span class="k">const</span> <span class="v">tax</span> = <span class="f">estimateTax</span>(<span class="v">total</span>, <span class="v">region</span>)',
        '  <span class="k">return</span> &lt;<span class="t">Summary</span> <span class="v">items</span>={<span class="v">items</span>} <span class="v">tax</span>={<span class="v">tax</span>} /&gt;',
        '}'],
      chat: () => `<p class="csd-msg me">Add tax estimate to the checkout summary</p><p class="csd-msg bot">Done. <code>Summary</code> now takes a <code>tax</code> prop.</p><div class="csd-step">Edited checkout.tsx</div><div class="csd-step">Created lib/tax.ts</div>` },
    { id: "billing-api", state: "working", claude: true, file: "invoices.go",
      tree: ["cmd/", "internal/", "invoices.go", "ledger.go", "migrations/", "0042_due_dates.sql", "go.mod"], on: 2, mods: [2, 5],
      code: [
        '<span class="k">func</span> (<span class="v">s</span> *<span class="t">Service</span>) <span class="f">Overdue</span>(<span class="v">ctx</span> <span class="t">context.Context</span>) ([]<span class="t">Invoice</span>, <span class="t">error</span>) {',
        '-  <span class="v">rows</span>, <span class="v">err</span> := <span class="v">s</span>.<span class="v">db</span>.<span class="f">Query</span>(<span class="v">ctx</span>, <span class="v">qOverdueAll</span>)',
        '+  <span class="v">rows</span>, <span class="v">err</span> := <span class="v">s</span>.<span class="v">db</span>.<span class="f">Query</span>(<span class="v">ctx</span>, <span class="v">qOverdue</span>, <span class="v">time</span>.<span class="f">Now</span>())',
        '  <span class="k">if</span> <span class="v">err</span> != <span class="k">nil</span> {',
        '    <span class="k">return nil</span>, <span class="v">err</span>',
        '  }',
        '  <span class="k">defer</span> <span class="v">rows</span>.<span class="f">Close</span>()',
        '  <span class="c">// scan into Invoice</span>'],
      chat: (s) => s === "attention"
        ? `<p class="csd-msg me">Make overdue invoices respect due_date</p><div class="csd-step">Wrote 0042_due_dates.sql</div><div class="csd-ask">Migration 0042 is ready. Run it against the dev database?<div class="row"><button class="yes" data-clear>Run it</button><button class="no" data-clear>Not yet</button></div></div>`
        : `<p class="csd-msg me">Make overdue invoices respect due_date</p><div class="csd-step">Edited invoices.go</div><div class="csd-step live">Writing migration <span class="csd-typing"><i></i><i></i><i></i></span></div>` },
    { id: "ios-app", state: "working", file: "FeedView.swift",
      tree: ["App/", "Features/", "FeedView.swift", "FeedModel.swift", "Tests/", "FeedTests.swift", "Package.swift"], on: 2, mods: [2],
      code: [
        '<span class="k">struct</span> <span class="t">FeedView</span>: <span class="t">View</span> {',
        '  <span class="k">@State private var</span> <span class="v">model</span> = <span class="t">FeedModel</span>()',
        '',
        '  <span class="k">var</span> <span class="v">body</span>: <span class="k">some</span> <span class="t">View</span> {',
        '    <span class="t">List</span>(<span class="v">model</span>.<span class="v">posts</span>) { <span class="v">post</span> <span class="k">in</span>',
        '      <span class="t">PostRow</span>(<span class="v">post</span>: <span class="v">post</span>)',
        '+        .<span class="f">task</span> { <span class="k">await</span> <span class="v">model</span>.<span class="f">prefetch</span>(<span class="v">after</span>: <span class="v">post</span>) }',
        '    }',
        '  }',
        '}'],
      chat: (s) => s === "attention"
        ? `<p class="csd-msg me">Prefetch the next page before the list ends</p><div class="csd-step">Ran FeedTests: 14 passed</div><div class="csd-ask">Tests pass. Want me to open a pull request?<div class="row"><button class="yes" data-clear>Open PR</button><button class="no" data-clear>Leave it</button></div></div>`
        : `<p class="csd-msg me">Prefetch the next page before the list ends</p><div class="csd-step">Edited FeedView.swift</div><div class="csd-step live">Running FeedTests <span class="csd-typing"><i></i><i></i><i></i></span></div>` },
    { id: "infra", state: "idle", file: "main.tf",
      tree: ["modules/", "envs/", "main.tf", "variables.tf", "prod.tfvars"], on: 2, mods: [],
      code: [
        '<span class="k">module</span> <span class="s">"api"</span> {',
        '  <span class="v">source</span>        = <span class="s">"./modules/service"</span>',
        '  <span class="v">name</span>          = <span class="s">"billing-api"</span>',
        '  <span class="v">min_instances</span> = <span class="n">2</span>',
        '  <span class="v">max_instances</span> = <span class="n">12</span>',
        '}'],
      chat: empty },
    { id: "docs-site", state: "idle", claude: true, file: "shortcuts.mdx",
      tree: ["content/", "guides/", "shortcuts.mdx", "install.mdx", "astro.config.mjs"], on: 2, mods: [],
      code: [
        '<span class="c">---</span>',
        '<span class="v">title</span>: <span class="s">Shortcuts</span>',
        '<span class="c">---</span>',
        '',
        '| Action       | Keys  |',
        '| ------------ | ----- |',
        '| Next tab     | ⌃⌥ ]  |',
        '| Previous tab | ⌃⌥ [  |'],
      chat: () => `<p class="csd-msg me">Tighten the shortcut table</p><p class="csd-msg bot">Updating the keys column.</p><div class="csd-step live">Editing shortcuts.mdx <span class="csd-typing"><i></i><i></i><i></i></span></div>` },
  ];

  function mount(root, opts = {}) {
    const P = projects();
    let current = 0, started = false;
    root.classList.add("csd");
    root.innerHTML = `
      <div class="csd-strip" role="tablist" aria-label="Demo stack">
        <div class="csd-lights" aria-hidden="true"><i style="background:#ff605c"></i><i style="background:#ffbd2e"></i><i style="background:#30d158"></i></div>
        <span class="csd-brand">CursorStack</span><span class="csd-sep" aria-hidden="true"></span>
      </div>
      <div class="csd-app">
        <aside class="csd-side"><h4></h4><ul></ul></aside>
        <div class="csd-editor"><div class="csd-edtabs"><span class="on"></span><span>README.md</span></div><pre class="csd-code"></pre></div>
        <aside class="csd-chat" aria-live="polite"></aside>
      </div>`;
    const strip = root.querySelector(".csd-strip"), q = (s) => root.querySelector(s);
    const tabs = P.map((p, i) => {
      const b = document.createElement("button");
      b.className = "csd-tab"; b.setAttribute("role", "tab");
      b.innerHTML = `<span>${p.id}</span><span class="csd-mark"></span><span class="csd-spark" aria-hidden="true"><b></b></span>`;
      b.addEventListener("click", () => select(i, true));
      strip.appendChild(b); return b;
    });
    const end = document.createElement("div"); end.className = "csd-end"; end.innerHTML = "<span>+ Add</span><span>Settings</span>";
    strip.appendChild(end);

    function render() {
      const p = P[current];
      tabs.forEach((t, i) => {
        const item = P[i];
        const bits = [item.id];
        if (item.state === "working") bits.push("Cursor running");
        if (item.state === "attention") bits.push("waiting on you");
        if (item.claude) bits.push("Claude Code running");
        t.setAttribute("aria-selected", i === current);
        t.setAttribute("aria-label", bits.join(", "));
        t.dataset.state = item.state;
        t.dataset.claude = item.claude ? "on" : "off";
        t.tabIndex = i === current ? 0 : -1;
      });
      q(".csd-side h4").textContent = p.id.toUpperCase();
      q(".csd-side ul").innerHTML = p.tree.map((f, i) => {
        const dir = f.endsWith("/");
        return `<li class="${dir ? "dir" : ""} ${i === p.on ? "on" : ""} ${p.mods.includes(i) ? "mod" : ""}">${dir ? "› " + f.slice(0, -1) : f}</li>`;
      }).join("");
      q(".csd-edtabs .on").textContent = p.file;
      q(".csd-code").innerHTML = p.code.map((l, i) => {
        const cls = l[0] === "+" ? "add" : l[0] === "-" ? "del" : "";
        return `<span class="line ${cls}"><span class="ln">${i + 1}</span>${cls ? " " + l.slice(1) : l}</span>`;
      }).join("");
      const who = p.claude && (p.state === "working" || p.state === "attention")
        ? "Cursor and Claude Code"
        : p.claude ? "Claude Code" : "Agent";
      q(".csd-chat").innerHTML = `<h4>${who}</h4>` + p.chat(p.state);
      opts.onUpdate && opts.onUpdate({
        running: P.filter(x => x.state === "working").length,
        waiting: P.filter(x => x.state === "attention").length,
        total: P.length, current: p.id, currentState: p.state,
      });
    }
    function select(i, byUser) {
      current = i; render();
      if (byUser) tabs[i].focus({ preventScroll: true });
      opts.onSelect && opts.onSelect(P[i], byUser);
    }
    root.addEventListener("click", (e) => {
      if (!e.target.matches("[data-clear]")) return;
      const p = P[current]; p.state = "idle";
      p.chat = () => `<p class="csd-msg bot">On it.</p><div class="csd-step">${e.target.textContent}</div>`;
      render(); schedule();
    });
    strip.addEventListener("keydown", (e) => {
      if (e.key === "ArrowRight") { e.preventDefault(); select((current + 1) % P.length, true); }
      if (e.key === "ArrowLeft") { e.preventDefault(); select((current + P.length - 1) % P.length, true); }
    });
    function schedule() {
      P.forEach((p, i) => {
        if (p.state !== "working") return;
        setTimeout(() => {
          if (P[i].state !== "working") return;
          P[i].state = "attention"; render();
          tabs[i].classList.remove("arrived"); void tabs[i].offsetWidth; tabs[i].classList.add("arrived");
        }, 1800 + i * 1700);
      });
    }
    // once every agent is idle, start a new one so the demo keeps breathing
    setInterval(() => {
      if (!started || P.some(p => p.state !== "idle")) return;
      const i = [1, 2].find(j => j !== current) ?? 1;
      P[i] = projects()[i]; render(); schedule();
    }, 4000);
    render();
    return {
      start() { if (!started) { started = true; schedule(); } },
      select,
    };
  }
  return { mount };
})();
