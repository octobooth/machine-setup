# Booth machine: no package downloads

This machine can't download npm or Python packages (registry.npmjs.org and files.pythonhosted.org are blocked).

- Never run `npm install`, `npm ci`, `npx`, `yarn`, `pnpm`, `create-*` scaffolders (such as `npm create vite`), `pip install`, `uv`, `uvx`, or `pipx`. Don't add npm dependencies or Python requirements.
- For new apps and games, use plain HTML, CSS, and JavaScript with no dependencies. A single `index.html` the user can open directly in the browser is best.
- If that doesn't fit, use Node.js built-ins (including `node:test` for tests) or the Python standard library only.
- If the user asks for a framework or library that needs packages (React, Next.js, Vite, Flask, etc.), tell them it needs a Cloud session and to ask booth staff for help.
