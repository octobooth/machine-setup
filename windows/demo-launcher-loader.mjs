// Demo Launcher loader (repo-setup-scripts, .github/extensions/demo-launcher-loader/).
// A user-level extension that loads the Demo Launcher from a local repo-setup-scripts
// checkout, so every Copilot session can open it. Install it from its GitHub folder URL
// with the name "demo-launcher", or run .github/extensions/demo-launcher/install.sh,
// which writes this same file.
//
// Checkout: $DEMO_LAUNCHER_REPO, else the path install.sh baked in below, else
// ~/repos/repo-setup-scripts (%USERPROFILE%\repos\repo-setup-scripts on Windows).
import { existsSync } from "node:fs";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const INSTALLED_REPO = ""; // install.sh replaces this line with the checkout it installed from.

const LAUNCHER = join(".github", "extensions", "demo-launcher", "extension.mjs");
const LOADER_DIR = dirname(fileURLToPath(import.meta.url));

const repoRoot = resolve(process.env.DEMO_LAUNCHER_REPO || INSTALLED_REPO || join(homedir(), "repos", "repo-setup-scripts"));
const launcherFile = join(repoRoot, LAUNCHER);

// Loaded from a checkout (as a project extension) rather than installed: that checkout's
// own demo-launcher folder already provides the canvas.
function loadedFromCheckout() {
    return existsSync(join(LOADER_DIR, "..", "..", "..", LAUNCHER));
}

// In a repo that ships its own copy (repo-setup-scripts), let that one provide the canvas.
function sessionRepoHasOwnCopy() {
    for (let dir = process.cwd(); ; dir = dirname(dir)) {
        if (existsSync(join(dir, LAUNCHER))) return true;
        if (existsSync(join(dir, ".git")) || dirname(dir) === dir) return false;
    }
}

const escapeHtml = (s) => String(s).replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);

// Registers a "Demo Launcher" canvas that explains what's missing instead of failing silently.
async function showSetupError(problem) {
    const { joinSession, createCanvas } = await import("@github/copilot-sdk/extension");
    const message =
        `${problem} Clone octobooth-demos/repo-setup-scripts to ${repoRoot} ` +
        "(or set DEMO_LAUNCHER_REPO to your checkout), then restart the Copilot app.";
    const html = `<!doctype html><meta charset="utf-8"><title>Demo Launcher</title>
<body style="font-family: system-ui, sans-serif; margin: 2rem; line-height: 1.5">
<h2>Demo Launcher isn't set up yet</h2>
<p>${escapeHtml(problem)}</p>
<p>Clone the launcher's repo to the path this loader expects, then restart the Copilot app:</p>
<pre style="white-space: pre-wrap">gh repo clone octobooth-demos/repo-setup-scripts "${escapeHtml(repoRoot)}"</pre>
<p>Or set the <code>DEMO_LAUNCHER_REPO</code> environment variable to an existing checkout.</p>
</body>`;
    let urlPromise;
    const serve = () =>
        (urlPromise ??= new Promise((done) => {
            const server = createServer((_req, res) => {
                res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
                res.end(html);
            });
            server.listen(0, "127.0.0.1", () => done(`http://127.0.0.1:${server.address().port}/`));
        }));
    const session = await joinSession({
        canvases: [
            createCanvas({
                id: "demo-launcher",
                displayName: "Demo Launcher",
                description: `Demo Launcher (not set up: ${message})`,
                actions: [
                    {
                        name: "setup_status",
                        description: "Explain why the Demo Launcher isn't available and how to fix it.",
                        handler: async () => ({ ok: false, repoRoot, message }),
                    },
                ],
                open: async () => ({ title: "Demo Launcher", url: await serve() }),
            }),
        ],
    });
    try {
        session?.log?.(`Demo Launcher: ${message}`, { level: "error" });
    } catch {}
}

if (loadedFromCheckout() || sessionRepoHasOwnCopy()) {
    const { joinSession } = await import("@github/copilot-sdk/extension");
    await joinSession({});
} else if (!existsSync(launcherFile)) {
    await showSetupError(`No Demo Launcher found at ${launcherFile}.`);
} else {
    // A file URL, not a path: a bare C:\... path breaks dynamic import on Windows.
    await import(pathToFileURL(launcherFile).href);
}
