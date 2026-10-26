# SPDX-License-Identifier: GPL-3.0-only
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import os
import sys
import threading
import re

try:
    import ezdxf
    HAS_EZDXF = True
except ImportError:
    HAS_EZDXF = False

try:
    import ezdwg
    HAS_EZDWG = True
except ImportError:
    HAS_EZDWG = False

from PIL import Image, ImageTk
from ezdxf.enums import TextEntityAlignment

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _solid_to_polyline(solid, owner):
    v0 = solid.dxf.vtx0
    v1 = solid.dxf.vtx1
    v2 = solid.dxf.vtx2
    v3 = solid.dxf.vtx3
    is_tri = (abs(v2[0] - v3[0]) < 1e-10 and abs(v2[1] - v3[1]) < 1e-10)
    if is_tri:
        pts = [(v0[0], v0[1]), (v1[0], v1[1]), (v2[0], v2[1])]
    else:
        pts = [(v0[0], v0[1]), (v1[0], v1[1]), (v3[0], v3[1]), (v2[0], v2[1])]
    return owner.add_lwpolyline(pts, dxfattribs={
        'layer': solid.dxf.layer,
        'color': solid.dxf.color,
        'const_width': 0,
        'closed': True,
    })


def _solid_to_lines(solid, owner):
    v0 = solid.dxf.vtx0
    v1 = solid.dxf.vtx1
    v2 = solid.dxf.vtx2
    v3 = solid.dxf.vtx3
    is_tri = (abs(v2[0] - v3[0]) < 1e-10 and abs(v2[1] - v3[1]) < 1e-10)
    attribs = {'layer': solid.dxf.layer, 'color': solid.dxf.color}
    lines = []
    if is_tri:
        lines.append(owner.add_line((v0[0], v0[1]), (v1[0], v1[1]), dxfattribs=attribs))
        lines.append(owner.add_line((v1[0], v1[1]), (v2[0], v2[1]), dxfattribs=attribs))
        lines.append(owner.add_line((v2[0], v2[1]), (v0[0], v0[1]), dxfattribs=attribs))
    else:
        lines.append(owner.add_line((v0[0], v0[1]), (v1[0], v1[1]), dxfattribs=attribs))
        lines.append(owner.add_line((v1[0], v1[1]), (v3[0], v3[1]), dxfattribs=attribs))
        lines.append(owner.add_line((v3[0], v3[1]), (v2[0], v2[1]), dxfattribs=attribs))
        lines.append(owner.add_line((v2[0], v2[1]), (v0[0], v0[1]), dxfattribs=attribs))
    return lines


def _process_container(container, stats):
    mtext_count, point_count, poly_fix_count, seg_removed, solid_count = stats
    to_discard = []

    for e in container:
        dxf_type = e.dxftype()

        if dxf_type == 'MTEXT':
            text = e.dxf.text
            insert = e.dxf.insert
            height = e.dxf.char_height
            layer = e.dxf.layer
            color = e.dxf.color
            rotation = e.dxf.get('rotation', 0)
            new_text = container.add_text(text, dxfattribs={
                'layer': layer, 'color': color, 'height': height, 'rotation': rotation,
            })
            new_text.set_placement(insert, align=TextEntityAlignment.LEFT)
            to_discard.append(e)
            mtext_count += 1

        elif dxf_type == 'POINT':
            to_discard.append(e)
            point_count += 1

        elif dxf_type == 'SOLID':
            _solid_to_lines(e, container)
            to_discard.append(e)
            solid_count += 1

        elif dxf_type == 'LWPOLYLINE':
            const_width = e.dxf.get('const_width', 0)
            if const_width > 0:
                vertices = list(e.get_points('xy'))
                clean_verts = []
                for i in range(len(vertices)):
                    if i > 0:
                        dx = vertices[i][0] - clean_verts[-1][0]
                        dy = vertices[i][1] - clean_verts[-1][1]
                        if abs(dx) < 1e-10 and abs(dy) < 1e-10:
                            seg_removed += 1
                            continue
                    clean_verts.append(vertices[i])

                if len(clean_verts) >= 2:
                    half = const_width / 2.0
                    outline1, outline2 = [], []
                    for i in range(len(clean_verts) - 1):
                        x1, y1 = clean_verts[i]
                        x2, y2 = clean_verts[i + 1]
                        dx = x2 - x1
                        dy = y2 - y1
                        length = (dx * dx + dy * dy) ** 0.5
                        if length < 1e-10:
                            continue
                        nx = -dy / length * half
                        ny = dx / length * half
                        outline1.append((x1 + nx, y1 + ny))
                        outline1.append((x2 + nx, y2 + ny))
                        outline2.append((x1 - nx, y1 - ny))
                        outline2.append((x2 - nx, y2 - ny))

                    attribs = {'layer': e.dxf.layer, 'color': e.dxf.color, 'const_width': 0, 'closed': False}
                    if len(outline1) >= 4:
                        container.add_lwpolyline(outline1, dxfattribs=attribs)
                    if len(outline2) >= 4:
                        container.add_lwpolyline(outline2, dxfattribs=attribs)
                    if e.closed and len(clean_verts) >= 2:
                        x1, y1 = clean_verts[-1]
                        x2, y2 = clean_verts[0]
                        dx = x2 - x1
                        dy = y2 - y1
                        length = (dx * dx + dy * dy) ** 0.5
                        if length >= 1e-10:
                            nx = -dy / length * half
                            ny = dx / length * half
                            cap_attribs = {'layer': e.dxf.layer, 'color': e.dxf.color}
                            container.add_line(
                                (clean_verts[-1][0] + nx, clean_verts[-1][1] + ny),
                                (clean_verts[-1][0] - nx, clean_verts[-1][1] - ny),
                                dxfattribs=cap_attribs)

                    to_discard.append(e)
                    poly_fix_count += 1

    for e in to_discard:
        container.delete_entity(e)

    return (mtext_count, point_count, poly_fix_count, seg_removed, solid_count)


def postprocess_for_allegro(dxf_path):
    doc = ezdxf.readfile(dxf_path)

    layers_rename = {}
    for layer in doc.layers:
        name = layer.dxf.name
        new_name = re.sub(r'[*$\s]', '_', name)
        if new_name != name:
            layers_rename[name] = new_name

    for old_name, new_name in layers_rename.items():
        target = doc.layers.get(new_name)
        if target is not None:
            for e in doc.modelspace().query(f'*[layer=="{old_name}"]'):
                try:
                    e.dxf.layer = new_name
                except Exception:
                    pass
            for block in doc.blocks:
                for e in block.query(f'*[layer=="{old_name}"]'):
                    try:
                        e.dxf.layer = new_name
                    except Exception:
                        pass
            doc.layers.remove(old_name)
        else:
            doc.layers.new(new_name)
            for e in doc.modelspace().query(f'*[layer=="{old_name}"]'):
                try:
                    e.dxf.layer = new_name
                except Exception:
                    pass
            for block in doc.blocks:
                for e in block.query(f'*[layer=="{old_name}"]'):
                    try:
                        e.dxf.layer = new_name
                    except Exception:
                        pass
            doc.layers.remove(old_name)

    stats = (0, 0, 0, 0, 0)

    for block in doc.blocks:
        if block.name in ('*Model_Space', '*Paper_Space'):
            continue
        stats = _process_container(block, stats)

    stats = _process_container(doc.modelspace(), stats)

    mtext_count, point_count, poly_fix_count, seg_removed, solid_count = stats

    doc.saveas(dxf_path)
    return mtext_count, point_count, poly_fix_count, seg_removed, solid_count


class Dwg2DxfApp:
    def __init__(self, root):
        self.root = root
        self.root.title("DWG \u2192 DXF \u8f6c\u6362\u5de5\u5177")
        self.root.resizable(False, False)

        self._load_icons()

        icons = [self.icon_normal, self.icon_iconify]
        icons = [i for i in icons if i is not None]
        if icons:
            self.root.iconphoto(True, *icons)

        main_frame = ttk.Frame(root, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)

        header_frame = ttk.Frame(main_frame)
        header_frame.pack(fill=tk.X, pady=(0, 15))

        ttk.Label(header_frame, text="designed by zst",
                  font=("Microsoft YaHei", 9, "italic"),
                  foreground="#888888").pack(side=tk.RIGHT)

        ttk.Label(header_frame, text="DWG \u2192 DXF \u8f6c\u6362",
                  font=("Microsoft YaHei", 14, "bold")).pack(side=tk.LEFT)

        input_frame = ttk.LabelFrame(main_frame, text="\u8f93\u5165 DWG \u6587\u4ef6", padding=10)
        input_frame.pack(fill=tk.X, pady=(0, 10))

        self.input_var = tk.StringVar()
        ttk.Entry(input_frame, textvariable=self.input_var).pack(
            side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        ttk.Button(input_frame, text="\u6d4f\u89c8...", command=self._browse_input).pack(side=tk.RIGHT)

        output_frame = ttk.LabelFrame(main_frame, text="\u8f93\u51fa DXF \u6587\u4ef6", padding=10)
        output_frame.pack(fill=tk.X, pady=(0, 10))

        self.output_var = tk.StringVar()
        ttk.Entry(output_frame, textvariable=self.output_var).pack(
            side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        ttk.Button(output_frame, text="\u6d4f\u89c8...", command=self._browse_output).pack(side=tk.RIGHT)

        option_frame = ttk.Frame(main_frame)
        option_frame.pack(fill=tk.X, pady=(0, 12))

        self.allegro_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(option_frame, text="Allegro \u517c\u5bb9\u6a21\u5f0f (\u5206\u89e3SOLID\u586b\u5145\u3001\u5bbd\u5ea6\u591a\u7ebf\u6bb5\u3001MTEXT\u2192TEXT)",
                        variable=self.allegro_var).pack(side=tk.LEFT)

        self.convert_btn = ttk.Button(main_frame, text="\u5f00\u59cb\u8f6c\u6362",
                                       command=self._convert)
        self.convert_btn.pack(pady=(0, 8))

        self.progress = ttk.Progressbar(main_frame, mode='indeterminate')
        self.status_var = tk.StringVar(value="\u5c31\u7eea")
        status_label = ttk.Label(main_frame, textvariable=self.status_var,
                                  font=("Microsoft YaHei", 9),
                                  foreground="#555555")
        status_label.pack()

        self._center_window()

    def _load_icons(self):
        closed_path = os.path.join(BASE_DIR, "kuromi_closed.png")
        open_path = os.path.join(BASE_DIR, "kuromi_open.png")

        if os.path.exists(closed_path):
            img = Image.open(closed_path).convert("RGBA")
            size = min(img.width, img.height)
            left = (img.width - size) // 2
            top = (img.height - size) // 2
            img = img.crop((left, top, left + size, top + size))
            img = img.resize((64, 64), Image.LANCZOS)
            self.icon_normal = ImageTk.PhotoImage(img)
        else:
            self.icon_normal = None

        if os.path.exists(open_path):
            img = Image.open(open_path).convert("RGBA")
            size = min(img.width, img.height)
            left = (img.width - size) // 2
            top = (img.height - size) // 2
            img = img.crop((left, top, left + size, top + size))
            img = img.resize((48, 48), Image.LANCZOS)
            self.icon_iconify = ImageTk.PhotoImage(img)
        else:
            self.icon_iconify = None

    def _center_window(self):
        self.root.update_idletasks()
        w, h = 540, 310
        sw = self.root.winfo_screenwidth()
        sh = self.root.winfo_screenheight()
        x = (sw - w) // 2
        y = (sh - h) // 2
        self.root.geometry(f"{w}x{h}+{x}+{y}")

    def _browse_input(self):
        path = filedialog.askopenfilename(
            title="\u9009\u62e9 DWG \u6587\u4ef6",
            filetypes=[("DWG \u6587\u4ef6", "*.dwg"), ("\u6240\u6709\u6587\u4ef6", "*.*")])
        if path:
            self.input_var.set(path)
            out = os.path.splitext(path)[0] + ".dxf"
            if not self.output_var.get():
                self.output_var.set(out)

    def _browse_output(self):
        path = filedialog.asksaveasfilename(
            title="\u4fdd\u5b58 DXF \u6587\u4ef6",
            defaultextension=".dxf",
            filetypes=[("DXF \u6587\u4ef6", "*.dxf"), ("\u6240\u6709\u6587\u4ef6", "*.*")])
        if path:
            self.output_var.set(path)

    def _set_ui_state(self, converting):
        state = tk.DISABLED if converting else tk.NORMAL
        for child in self.root.winfo_children():
            self._set_widgets_state(child, state)
        self.convert_btn.config(state=state)

    def _set_widgets_state(self, widget, state):
        try:
            widget.config(state=state)
        except tk.TclError:
            pass
        for child in widget.winfo_children():
            self._set_widgets_state(child, state)

    def _convert(self):
        dwg_path = self.input_var.get().strip()
        dxf_path = self.output_var.get().strip()

        if not dwg_path:
            messagebox.showwarning("\u63d0\u793a", "\u8bf7\u9009\u62e9 DWG \u6587\u4ef6")
            return
        if not dxf_path:
            messagebox.showwarning("\u63d0\u793a", "\u8bf7\u8bbe\u7f6e DXF \u8f93\u51fa\u8def\u5f84")
            return
        if not os.path.isfile(dwg_path):
            messagebox.showerror("\u9519\u8bef", "DWG \u6587\u4ef6\u4e0d\u5b58\u5728")
            return
        if dwg_path.lower() == dxf_path.lower():
            messagebox.showerror("\u9519\u8bef", "\u8f93\u5165\u548c\u8f93\u51fa\u4e0d\u80fd\u662f\u540c\u4e00\u4e2a\u6587\u4ef6")
            return

        if not HAS_EZDWG:
            messagebox.showerror("\u9519\u8bef",
                "\u7f3a\u5c11 ezdwg \u5e93\uff0c\u8bf7\u8fd0\u884c: pip install ezdwg[dxf]")
            return

        if self.allegro_var.get() and not HAS_EZDXF:
            ret = messagebox.askyesno("\u63d0\u793a",
                "Allegro \u517c\u5bb9\u6a21\u5f0f\u9700\u8981 ezdxf \u5e93\uff0c\u662f\u5426\u7ee7\u7eed\u666e\u901a\u8f6c\u6362\uff1f")
            if not ret:
                return
            self.allegro_var.set(False)

        self._set_ui_state(True)
        self.progress.pack(pady=(0, 6))
        self.progress.start()
        self.status_var.set("\u6b63\u5728\u8f6c\u6362...")

        threading.Thread(target=self._do_convert,
                         args=(dwg_path, dxf_path), daemon=True).start()

    def _do_convert(self, dwg_path, dxf_path):
        try:
            ezdwg.to_dxf(dwg_path, dxf_path)

            if self.allegro_var.get() and HAS_EZDXF:
                self.root.after(0, self._update_status, "\u6b63\u5728\u5904\u7406 Allegro \u517c\u5bb9...")
                try:
                    mt, pt, pf, sr, sc = postprocess_for_allegro(dxf_path)
                    extra = f"\n(Allegro: SOLID\u8f6c\u7ebf\u6bb5x{sc}, MTEXT\u8f6cTEXTx{mt}, \u5bbd\u5ea6\u5206\u89e3x{pf}, \u5220\u9664POINTx{pt})"
                except Exception as pe:
                    extra = f"\n(Allegro \u5904\u7406\u62a5\u9519: {pe})"
            else:
                extra = ""

            self.root.after(0, self._on_success, dxf_path, extra)
        except Exception as e:
            self.root.after(0, self._on_error, str(e))

    def _update_status(self, msg):
        self.status_var.set(msg)

    def _on_success(self, dxf_path, extra=""):
        self.progress.stop()
        self.progress.pack_forget()
        self._set_ui_state(False)
        self.status_var.set("\u8f6c\u6362\u5b8c\u6210 ✓")
        msg = f"\u8f6c\u6362\u5b8c\u6210!\n{dxf_path}{extra}"
        ret = messagebox.askyesno("\u6210\u529f", msg + "\n\n\u662f\u5426\u6253\u5f00\u6240\u5728\u6587\u4ef6\u5939?")
        if ret:
            os.startfile(os.path.dirname(dxf_path))

    def _on_error(self, err_msg):
        self.progress.stop()
        self.progress.pack_forget()
        self._set_ui_state(False)
        self.status_var.set("\u8f6c\u6362\u5931\u8d25 ✗")
        messagebox.showerror("\u8f6c\u6362\u5931\u8d25", err_msg)


def main():
    if not HAS_EZDWG:
        print("\u8b66\u544a: ezdwg \u672a\u5b89\u88c5\u3002\u8bf7\u8fd0\u884c: pip install ezdwg[dxf]")
    root = tk.Tk()
    app = Dwg2DxfApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
