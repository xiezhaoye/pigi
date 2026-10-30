import { createHash } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
const root = import.meta.dirname;

// 版本号唯一来源:仓库根目录 VERSION 第 1 行。页面里只写 {{VERSION}}。
const version = readFileSync(join(root, "..", "VERSION"), "utf8").split("\n")[0].trim();
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`VERSION 第 1 行必须是 X.Y.Z,实际是 '${version}'`);

const dist = join(root, "dist");
const html = readFileSync(join(root, "index.html"), "utf8").replaceAll("{{VERSION}}", version);
if (html.includes("{{")) throw new Error("index.html 里还有未替换的 {{占位符}}");
for (const required of ["assets/logo.png", "assets/multi-account.png", "assets/code-unsub.png", "assets/hotkey.png", "privacy/", "gmail-api/", "https://github.com/xiezhaoye/pigi"]) {
  if (!html.includes(required)) throw new Error(`Missing page asset or link: ${required}`);
}
// 下载按钮只能指向 R2 域名 + 当前版本的包。
const download = `https://pigi-dl.xiezhaoye.site/Pigi-${version}-macos-arm64.zip`;
if (!html.includes(download)) throw new Error(`下载链接没有指向 ${download}`);
const stray = [...html.matchAll(/https:\/\/([^"'\s]+)\/(Pigi-[^"'\s]+\.zip)/g)].filter((m) => m[0] !== download);
if (stray.length) throw new Error(`存在指向错误域名或旧版本的下载链接:${stray.map((m) => m[0]).join(", ")}`);

rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });
for (const file of ["style.css", "site.js", "404.html", "robots.txt", "sitemap.xml", "_headers", "assets"]) {
  cpSync(join(root, file), join(dist, file), { recursive: true });
}

const hashed = {};
for (const file of ["style.css", "site.js"]) {
  const content = readFileSync(join(root, file));
  const [name, ext] = file.split(".");
  const versioned = `${name}.${createHash("sha256").update(content).digest("hex").slice(0, 12)}.${ext}`;
  writeFileSync(join(dist, versioned), content);
  hashed[file] = versioned;
}

// docs/gmail-api.md 是教程的唯一来源,这里转成页面。只支持教程用到的 Markdown 子集。
const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const inline = (s) =>
  esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/&lt;(https?:\/\/[^&]+)&gt;/g, '<a href="$1">$1</a>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
function markdown(md) {
  const out = [];
  let list = null;
  const close = () => { if (list) { out.push(`</${list}>`); list = null; } };
  for (const line of md.split("\n")) {
    let m;
    if ((m = line.match(/^(#{1,3}) (.*)/))) { close(); out.push(`<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`); }
    else if ((m = line.match(/^\d+\. (.*)/))) { if (list !== "ol") { close(); out.push("<ol>"); list = "ol"; } out.push(`<li>${inline(m[1])}</li>`); }
    else if ((m = line.match(/^- (.*)/))) { if (list !== "ul") { close(); out.push("<ul>"); list = "ul"; } out.push(`<li>${inline(m[1])}</li>`); }
    else if ((m = line.match(/^> (.*)/))) { close(); out.push(`<blockquote>${inline(m[1])}</blockquote>`); }
    else if (line.trim() === "") close();
    else { close(); out.push(`<p>${inline(line)}</p>`); }
  }
  close();
  return out.join("\n");
}

const css = hashed["style.css"];
const shell = (title, desc, canonical, body) => `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title} · pigi</title>
  <meta name="description" content="${desc}">
  <link rel="canonical" href="${canonical}">
  <link rel="icon" type="image/png" href="../assets/logo.png">
  <link rel="stylesheet" href="../${css}">
</head>
<body class="doc-page">
<header class="nav"><div class="nav-inner"><a class="brand" href="../"><img src="../assets/logo.png" width="38" height="38" alt=""><span>pigi</span></a><nav aria-label="主导航"><a href="../">首页</a><a href="../privacy/">隐私政策</a><a href="https://github.com/xiezhaoye/pigi">GitHub</a></nav></div></header>
<main class="privacy doc-article">
${body}
</main>
<footer class="wrap footer"><a class="brand" href="../"><img src="../assets/logo.png" width="26" height="26" alt=""><span>pigi</span></a><p>由 <a href="https://www.xiezhaoye.site/">xiezhaoye</a> 开发,MIT 开源。</p><nav aria-label="页脚导航"><a href="../gmail-api/">Gmail 接入</a><a href="../privacy/">隐私政策</a><a href="../terms/">服务条款</a></nav></footer>
</body>
</html>
`;

mkdirSync(join(dist, "gmail-api"), { recursive: true });
writeFileSync(
  join(dist, "gmail-api", "index.html"),
  shell("申请 Gmail API 凭据", "一步步申请自己的 Gmail OAuth 客户端 ID,在 pigi 中添加 Gmail 账号。", "https://pigi.xiezhaoye.site/gmail-api/", markdown(readFileSync(join(root, "..", "docs", "gmail-api.md"), "utf8"))),
);

for (const page of ["privacy", "terms"]) {
  mkdirSync(join(dist, page), { recursive: true });
  writeFileSync(join(dist, page, "index.html"), readFileSync(join(root, page, "index.html"), "utf8").replace('"../style.css"', `"../${css}"`));
}
writeFileSync(join(dist, "index.html"), html.replace('"style.css"', `"${hashed["style.css"]}"`).replace('"site.js"', `"${hashed["site.js"]}"`));
console.log(`Built pigi landing/dist for v${version}`);
