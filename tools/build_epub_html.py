#!/usr/bin/env python3
"""Build EPUB 3 + a standalone styled HTML edition from the book markdown."""
import os, re, zipfile, uuid, html, datetime
import markdown

TITLE = "The Courage to Say Hello"
SUB = "An honest book about talking to the girl you like — and becoming the kind of man worth talking to"
AUTHOR = "A. R. Vance"
SRC = "THE-COURAGE-TO-SAY-HELLO.md"
os.makedirs("dist", exist_ok=True)

md_text = open(SRC, encoding="utf-8").read()

CSS = """
html{font-size:100%}
body{font-family:Georgia,'Iowan Old Style','Times New Roman',serif;line-height:1.62;
 color:#1a1a1a;max-width:36em;margin:0 auto;padding:3em 1.4em 6em;background:#fdfcfa;
 font-size:1.02rem;-webkit-text-size-adjust:100%}
h1{font-size:1.05rem;letter-spacing:.16em;text-transform:uppercase;text-align:center;
 font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-weight:700;
 margin:4em 0 2.4em;color:#7a6a55;page-break-before:always}
h2{font-size:1.75rem;line-height:1.25;margin:3.2em 0 1.1em;font-weight:700;page-break-before:always}
h3{font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:1.02rem;
 font-weight:700;margin:2.2em 0 .7em;letter-spacing:.005em}
h4{font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:.95rem;margin:1.6em 0 .5em}
p{margin:0 0 1.05em}
blockquote{margin:1.4em 0;padding:.15em 0 .15em 1.2em;border-left:3px solid #d8cfc0;
 color:#5a5245;font-style:italic}
blockquote p{margin:.4em 0}
ul,ol{margin:0 0 1.2em;padding-left:1.5em}
li{margin:.42em 0}
hr{border:0;height:1px;background:#e2dbcf;margin:2.6em auto;width:38%}
strong{font-weight:700}
em{font-style:italic}
table{border-collapse:collapse;width:100%;font-size:.88rem;margin:1.4em 0;
 font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif}
th,td{border-bottom:1px solid #e2dbcf;padding:.5em .6em;text-align:left;vertical-align:top}
th{background:#f4f0e8;font-weight:700}
code{background:#f0ece4;padding:.1em .3em;border-radius:3px;font-size:.9em}
a{color:#8a6d3b}
@media (prefers-color-scheme:dark){
 body{background:#15140f;color:#e6e1d6}h2{color:#f2ede2}h1{color:#b9a688}
 blockquote{color:#bcb4a3;border-color:#4a443a}
 th{background:#211f19}th,td{border-color:#3a352c}hr{background:#3a352c}
 code{background:#26241d}a{color:#c9a86a}}
"""

# ---------------- standalone HTML ----------------
body_html = markdown.markdown(md_text, extensions=["extra", "sane_lists", "smarty"])
open("dist/The-Courage-To-Say-Hello.html", "w", encoding="utf-8").write(
    f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(TITLE)} — {html.escape(AUTHOR)}</title>
<style>{CSS}
@media print{{body{{background:#fff;max-width:none;padding:0;font-size:11pt}}
 h1,h2{{page-break-after:avoid}}p,li,blockquote{{page-break-inside:avoid}}
 @page{{margin:20mm 18mm;size:A5}}}}
.cover{{text-align:center;margin:5em 0 6em;page-break-after:always}}
.cover .t{{font-size:2.6rem;line-height:1.15;font-weight:700;margin:0 0 .6em}}
.cover .s{{font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;font-size:.95rem;
 color:#7a6a55;max-width:26em;margin:0 auto 3em}}
.cover .a{{font-size:1.15rem;letter-spacing:.05em}}
h1:first-of-type{{page-break-before:avoid}}
</style></head><body>
<div class="cover"><p class="t">The Courage<br>to Say Hello</p>
<p class="s">{html.escape(SUB)}</p><p class="a">{html.escape(AUTHOR)}</p></div>
{body_html}
</body></html>""")

# ---------------- EPUB ----------------
# split into chapter files on H1/H2
parts, cur, title_cur = [], [], "Cover"
for line in md_text.split("\n"):
    m = re.match(r"^(#{1,2})\s+(.*)$", line)
    if m:
        if cur:
            parts.append((title_cur, "\n".join(cur)))
        title_cur = re.sub(r"[*_`]", "", m.group(2)).strip()
        cur = [line]
    else:
        cur.append(line)
if cur:
    parts.append((title_cur, "\n".join(cur)))

uid = "urn:uuid:" + str(uuid.uuid4())
now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")

items, spine, nav = [], [], []
files = {}
for idx, (t, chunk) in enumerate(parts):
    name = f"ch{idx:02d}.xhtml"
    inner = markdown.markdown(chunk, extensions=["extra", "sane_lists", "smarty"])
    files[f"OEBPS/{name}"] = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" lang="en"><head>'
        f'<meta charset="utf-8"/><title>{html.escape(t)}</title>'
        '<link rel="stylesheet" href="style.css"/></head><body>'
        f'{inner}</body></html>')
    items.append(f'<item id="c{idx}" href="{name}" media-type="application/xhtml+xml"/>')
    spine.append(f'<itemref idref="c{idx}"/>')
    nav.append(f'<li><a href="{name}">{html.escape(t)}</a></li>')

files["mimetype"] = "application/epub+zip"
files["META-INF/container.xml"] = (
    '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
    '</rootfiles></container>')
files["OEBPS/style.css"] = CSS + "\nbody{max-width:none;padding:0 1em;background:none}\n"
files["OEBPS/nav.xhtml"] = (
    '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">'
    '<head><meta charset="utf-8"/><title>Contents</title></head><body>'
    '<nav epub:type="toc" id="toc"><h2>Contents</h2><ol>' + "".join(nav) +
    '</ol></nav></body></html>')
files["OEBPS/content.opf"] = f"""<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="bookid">{uid}</dc:identifier>
<dc:title>{html.escape(TITLE)}</dc:title>
<dc:creator>{html.escape(AUTHOR)}</dc:creator>
<dc:language>en</dc:language>
<dc:description>{html.escape(SUB)}</dc:description>
<meta property="dcterms:modified">{now}</meta>
</metadata>
<manifest>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="css" href="style.css" media-type="text/css"/>
{chr(10).join(items)}
</manifest>
<spine>{"".join(spine)}</spine>
</package>"""

out = "dist/The-Courage-To-Say-Hello.epub"
with zipfile.ZipFile(out, "w") as z:
    z.writestr("mimetype", files.pop("mimetype"), zipfile.ZIP_STORED)
    for k, v in files.items():
        z.writestr(k, v, zipfile.ZIP_DEFLATED)

print("wrote dist/The-Courage-To-Say-Hello.html and", out,
      os.path.getsize(out) // 1024, "KB,", len(parts), "sections")
