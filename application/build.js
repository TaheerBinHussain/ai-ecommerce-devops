// Packages the static storefront into dist/ and stamps build metadata
// (version.json) so every deployed artifact is traceable to a commit.
const fs = require("node:fs");
const path = require("node:path");

const src = path.join(__dirname, "src");
const dist = path.join(__dirname, "dist");

fs.rmSync(dist, { recursive: true, force: true });
fs.cpSync(src, dist, { recursive: true });

const meta = {
  app: "nexvion-store",
  version: process.env.APP_VERSION || require("./package.json").version,
  commit: process.env.GIT_COMMIT || "local",
  buildNumber: process.env.BUILD_NUMBER || "0",
  builtAt: new Date().toISOString()
};
fs.writeFileSync(path.join(dist, "version.json"), JSON.stringify(meta, null, 2) + "\n");

const files = fs.readdirSync(dist);
console.log(`Built ${files.length} files into dist/ (version ${meta.version}, commit ${meta.commit})`);
