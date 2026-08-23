#!/usr/bin/env python3
"""Build a print-ready PDF of the book from the assembled markdown."""
import re, os
from fpdf import FPDF

SRC = "THE-COURAGE-TO-SAY-HELLO.md"
OUT = "dist/The-Courage-To-Say-Hello.pdf"
FDIR = "/usr/share/fonts/truetype/dejavu"

TITLE = "The Courage to Say Hello"
AUTHOR = "A. R. Vance"


class Book(FPDF):
    def __init__(self):
        super().__init__(format="A5", unit="mm")
        self.set_margins(18, 18, 18)
        self.set_auto_page_break(True, margin=20)
        self.add_font("serif", "", f"{FDIR}/DejaVuSerif.ttf")
        self.add_font("serif", "B", f"{FDIR}/DejaVuSerif-Bold.ttf")
        self.add_font("sans", "", f"{FDIR}/DejaVuSans.ttf")
        self.add_font("sans", "B", f"{FDIR}/DejaVuSans-Bold.ttf")
        self.running = False
        self.set_title(TITLE)
        self.set_author(AUTHOR)

    def header(self):
        if not self.running or self.page_no() <= 2:
            return
        self.set_font("sans", "", 7)
        self.set_text_color(140)
        label = TITLE if self.page_no() % 2 == 0 else AUTHOR
        self.cell(0, 6, label, align="C")
        self.set_text_color(0)
        self.ln(8)

    def footer(self):
        if not self.running or self.page_no() <= 2:
            return
        self.set_y(-14)
        self.set_font("sans", "", 8)
        self.set_text_color(120)
        self.cell(0, 6, str(self.page_no()), align="C")
        self.set_text_color(0)


INLINE = re.compile(r"(\*\*.+?\*\*|\*[^*]+?\*|`[^`]+?`)")


def clean(t):
    t = t.replace("&nbsp;", " ")
    return t


def rich(pdf, text, size=10.5, lh=5.4, base="serif", indent=0, color=0):
    """Write a paragraph honouring **bold** and *italic* (italic -> bold-ish serif)."""
    text = clean(text)
    if indent:
        pdf.set_x(pdf.l_margin + indent)
    pdf.set_text_color(color)
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            pdf.set_font(base, "B", size)
            pdf.write(lh, part[2:-2])
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            pdf.set_font("sans", "", size - 0.3)
            pdf.write(lh, part[1:-1])
        elif part.startswith("`") and part.endswith("`"):
            pdf.set_font("sans", "", size - 0.5)
            pdf.write(lh, part[1:-1])
        else:
            pdf.set_font(base, "", size)
            pdf.write(lh, part)
    pdf.set_text_color(0)
    pdf.ln(lh)


def build():
    md = open(SRC, encoding="utf-8").read()
    lines = md.split("\n")

    pdf = Book()

    # ---- Cover ----
    pdf.add_page()
    pdf.ln(45)
    pdf.set_font("serif", "B", 26)
    pdf.multi_cell(0, 12, "The Courage\nto Say Hello", align="C")
    pdf.ln(6)
    pdf.set_font("sans", "", 10)
    pdf.set_text_color(90)
    pdf.multi_cell(0, 5.6,
                   "An honest book about talking to the girl you like\n"
                   "— and becoming the kind of man worth talking to", align="C")
    pdf.set_text_color(0)
    pdf.ln(50)
    pdf.set_font("serif", "", 13)
    pdf.cell(0, 8, AUTHOR, align="C")

    pdf.add_page()
    pdf.ln(60)
    pdf.set_font("sans", "", 8.5)
    pdf.set_text_color(110)
    pdf.multi_cell(0, 4.6,
                   "Copyright © 2026. All rights reserved.\n\n"
                   "This book offers general guidance on communication, relationships and "
                   "personal confidence. It is not a substitute for professional counselling "
                   "or mental health treatment.", align="C")
    pdf.set_text_color(0)

    pdf.running = True
    pdf.add_page()

    i = 0
    n = len(lines)
    in_table = False
    while i < n:
        raw = lines[i]
        line = raw.rstrip()
        s = line.strip()
        i += 1

        # tables
        if s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if all(set(c) <= set("-: ") for c in cells):
                continue
            if not in_table:
                in_table = True
            w = (pdf.w - pdf.l_margin - pdf.r_margin) / max(len(cells), 1)
            pdf.set_font("sans", "", 7.6)
            y0 = pdf.get_y()
            heights = []
            for c in cells:
                heights.append(len(pdf.multi_cell(w, 4, re.sub(r"\*\*", "", c),
                                                  split_only=True)))
            h = max(heights) * 4
            if y0 + h > pdf.h - pdf.b_margin:
                pdf.add_page()
                y0 = pdf.get_y()
            for k, c in enumerate(cells):
                pdf.set_xy(pdf.l_margin + k * w, y0)
                pdf.multi_cell(w, 4, re.sub(r"\*\*", "", c), border=0)
            pdf.set_y(y0 + h + 0.6)
            pdf.set_draw_color(220)
            pdf.line(pdf.l_margin, pdf.get_y(), pdf.w - pdf.r_margin, pdf.get_y())
            pdf.ln(1.2)
            continue
        in_table = False

        if not s:
            pdf.ln(2)
            continue

        if s in ("---", "***", "___"):
            continue

        if s.startswith("*[") or s == "*End.*":
            continue

        # headings
        m = re.match(r"^(#{1,4})\s+(.*)$", s)
        if m:
            level, text = len(m.group(1)), m.group(2).strip()
            text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
            if level == 1:
                pdf.add_page()
                pdf.ln(28)
                pdf.set_font("sans", "B", 15)
                pdf.multi_cell(0, 8, text.upper(), align="C")
                pdf.ln(10)
            elif level == 2:
                pdf.add_page()
                pdf.ln(14)
                pdf.set_font("serif", "B", 17)
                pdf.multi_cell(0, 9, text)
                pdf.ln(5)
            elif level == 3:
                pdf.ln(4)
                pdf.set_font("sans", "B", 10.5)
                pdf.multi_cell(0, 5.6, text)
                pdf.ln(1.5)
            else:
                pdf.ln(2)
                pdf.set_font("sans", "B", 9.5)
                pdf.multi_cell(0, 5, text)
            continue

        # blockquote
        if s.startswith(">"):
            body = s.lstrip("> ").strip()
            if body:
                x0, y0 = pdf.l_margin, pdf.get_y()
                rich(pdf, body, size=10, lh=5.2, base="serif", indent=7, color=70)
                pdf.set_draw_color(180)
                pdf.set_line_width(0.5)
                pdf.line(x0 + 2.5, y0 + 1, x0 + 2.5, pdf.get_y() - 1)
                pdf.set_line_width(0.2)
            pdf.ln(1.5)
            continue

        # bullets
        if re.match(r"^[-*]\s+", s):
            body = re.sub(r"^[-*]\s+", "", s)
            y = pdf.get_y()
            pdf.set_font("serif", "", 10.5)
            pdf.set_xy(pdf.l_margin + 2, y)
            pdf.cell(4, 5.4, "•")
            pdf.set_xy(pdf.l_margin + 6, y)
            rich(pdf, body, size=10.5, lh=5.4, indent=6)
            continue

        # numbered
        mn = re.match(r"^(\d+)\.\s+(.*)$", s)
        if mn:
            y = pdf.get_y()
            pdf.set_font("serif", "", 10.5)
            pdf.set_xy(pdf.l_margin + 1, y)
            pdf.cell(6, 5.4, mn.group(1) + ".")
            pdf.set_xy(pdf.l_margin + 7, y)
            rich(pdf, mn.group(2), size=10.5, lh=5.4, indent=7)
            continue

        rich(pdf, s)

    os.makedirs("dist", exist_ok=True)
    pdf.output(OUT)
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB", pdf.page_no(), "pages")


if __name__ == "__main__":
    build()
