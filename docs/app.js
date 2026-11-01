// Every download, script and source URL on the site comes from here.
// The site itself is GitHub Pages from docs/: https://ignaciojuarez.github.io/cofre/
// The app shows its short pair link, ignaciojuarez.github.io/cofre/pair (docs/pair/ redirects to Step 3).
// Keep README.md, PAIRING.md, CofreLinks (app/UI) and Llave's getCofre in sync when you change these.
const LINKS = {
  site: "https://ignaciojuarez.github.io/cofre/",
  pair: "https://ignaciojuarez.github.io/cofre/pair/",
  ipa: "https://github.com/ignaciojuarez/cofre/releases/latest/download/Cofre.ipa",
  pairScript: "https://github.com/ignaciojuarez/cofre/releases/latest/download/pair.sh",
  pairingGuide: "https://github.com/ignaciojuarez/cofre/blob/main/PAIRING.md",
  source: "https://github.com/ignaciojuarez/cofre",
};

const COMMAND = `curl -fsSL ${LINKS.pairScript} | sh`;

const HELP_PROMPT = `I'm setting up Cofre, a Minecraft: Java Edition launcher for iPhone. I'm stuck on Step 3: with my iPhone plugged into my Mac, I run one command in Terminal, and a Cofre window puts my pairing key into Cofre over the cable.

The steps, what the command does, and troubleshooting are here: ${LINKS.pairingGuide}

Please read that page and tell me what to do next, one step at a time, in plain words. You can only explain; the command does the work. Never ask me for my pairing file or what's inside it. Before I paste anything, I will remove email addresses, account IDs, server addresses, tokens, logs, and file paths.

Here's what I see: `;

const COPIED = {
  command: "Copied. Paste it into Terminal and press Return.",
  help: "Copied. Remove personal data, then paste it into ChatGPT or Claude.",
};

for (const a of document.querySelectorAll("[data-link]")) {
  const url = LINKS[a.dataset.link];
  if (url) a.href = url;
}

for (const code of document.querySelectorAll("[data-command]")) code.textContent = COMMAND;

for (const button of document.querySelectorAll("[data-copy]")) {
  const kind = button.dataset.copy;
  const status = document.querySelector(`[data-copy-status="${kind}"]`);
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(kind === "help" ? HELP_PROMPT : COMMAND);
      status.textContent = COPIED[kind];
    } catch {
      status.textContent = kind === "help"
        ? "Couldn't copy. The same text is in the pairing guide."
        : "Couldn't copy. Select the command and press ⌘C.";
    }
  });
}
