# Booth machine: approved package sources

Use the machine's working, approved package sources. Public npm and Python endpoints may be blocked; device enrollment alone does not establish package access.

- Before `npm install`, `npm ci`, `npx`, `npm create vite`, or `pip install`, confirm booth staff has verified the configured route and approved the download. Preserve existing feed, proxy, certificate, and credential settings. Other package managers and separate binary downloads need their own verification.
- Never switch to a public registry after a failure, disable TLS/security controls, copy tokens between machines, or sign in with a staff account. Ask booth staff to resolve feed/network access instead. Keep machine-specific sources and credentials out of public repository config and lockfiles.
- For new apps and games, use plain HTML, CSS, and JavaScript with no dependencies. A single `index.html` the user can open directly in the browser is best.
- If that doesn't fit and approved package access is unavailable, use Node.js built-ins (including `node:test` for tests), the Python standard library, or a Cloud session. Ask booth staff for help with framework demos.
