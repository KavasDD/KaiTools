#!/usr/bin/env python
# SPDX-License-Identifier: GPL-3.0-only
# -*- coding: utf-8 -*-
"""
STEP/STP to DXF Converter
Auto-exports 6 orthographic views (Top, Bottom, Left, Right, Front, Back)
from 3D STEP/STP files to 2D DXF files (units: mm).

Dependencies: cadquery, ezdxf, Pillow
"""

import os
import sys
import math
import re
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from PIL import Image, ImageTk

# ─── Configuration ────────────────────────────────────────────────────────────

APP_NAME = "STEP/STP to DXF Converter"
APP_VERSION = "1.0"
DESIGN_BY = "design by zhanshuting"

VIEWS = {
    "Top":   {"dir": ( 0,  0,  1), "map": lambda p: ( p.X(),  p.Y())},
    "Front": {"dir": ( 0,  1,  0), "map": lambda p: ( p.Y(),  p.X())},
    "Left":  {"dir": ( 1,  0,  0), "map": lambda p: (-p.Y(),  p.X())},
}

# ─── STEP Unit Detection ──────────────────────────────────────────────────────

def detect_step_unit(filepath):
    conversion_to_mm = 1.0
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read(65536)
    except:
        return conversion_to_mm
    data_start = content.find('DATA;')
    if data_start < 0:
        return conversion_to_mm
    data_section = content[data_start:]
    unit_defs = {}
    for m in re.finditer(r'#(\d+)\s*=\s*([^;]+);', data_section):
        num = m.group(1)
        val = m.group(2).strip()
        unit_defs[num] = val
    length_unit_num = None
    for num, val in unit_defs.items():
        if 'LENGTH_UNIT' in val and 'NAMED_UNIT' in val:
            refs = re.findall(r'#(\d+)', val)
            for ref in refs:
                if ref in unit_defs:
                    length_unit_num = ref
                    break
    if length_unit_num and length_unit_num in unit_defs:
        val = unit_defs[length_unit_num]
        if 'MILLI' in val and 'METRE' in val:
            conversion_to_mm = 1.0
        elif 'CENTI' in val and 'METRE' in val:
            conversion_to_mm = 10.0
        elif 'METRE' in val and 'MILLI' not in val and 'CENTI' not in val:
            conversion_to_mm = 1000.0
        elif 'INCH' in val or 'inch' in val:
            conversion_to_mm = 25.4
        elif 'FOOT' in val or 'foot' in val:
            conversion_to_mm = 304.8
    for num, val in unit_defs.items():
        if 'CONVERSION_BASED_UNIT' in val and ('INCH' in val or 'inch' in val):
            conversion_to_mm = 25.4
            break
        if 'CONVERSION_BASED_UNIT' in val and ('FOOT' in val or 'foot' in val):
            conversion_to_mm = 304.8
            break
    return conversion_to_mm

# ─── HLR Projection → DXF ─────────────────────────────────────────────────────

def view_to_dxf(shape, view_info, output_path, scale=1.0):
    from OCP.gp import gp_Pnt, gp_Dir, gp_Ax2
    from OCP.HLRBRep import HLRBRep_Algo, HLRBRep_HLRToShape
    from OCP.HLRAlgo import HLRAlgo_Projector
    from OCP.TopExp import TopExp_Explorer
    from OCP.TopAbs import TopAbs_EDGE
    from OCP.TopoDS import TopoDS
    from OCP.BRepAdaptor import BRepAdaptor_Curve
    from OCP.GeomAbs import GeomAbs_Line, GeomAbs_Circle, GeomAbs_BSplineCurve
    import ezdxf
    import math

    dx, dy, dz = view_info["dir"]
    coord_map = view_info["map"]

    projector = HLRAlgo_Projector(gp_Ax2(gp_Pnt(0, 0, 0), gp_Dir(dx, dy, dz)))
    hlr = HLRBRep_Algo()
    hlr.Add(shape)
    hlr.Projector(projector)
    hlr.Update()

    hlr_shapes = HLRBRep_HLRToShape(hlr)
    compounds = [
        hlr_shapes.OutLineVCompound(),
        hlr_shapes.VCompound(),
    ]

    doc = ezdxf.new('R2010')
    msp = doc.modelspace()
    seen = set()
    edge_count = 0
    eps = 1e-3

    for compound in compounds:
        if not compound:
            continue
        exp = TopExp_Explorer(compound, TopAbs_EDGE)
        while exp.More():
            s = exp.Current()
            edge = TopoDS.Edge_s(s)
            try:
                adaptor = BRepAdaptor_Curve(edge)
                ctype = adaptor.GetType()
                first = adaptor.FirstParameter()
                last = adaptor.LastParameter()

                if ctype == GeomAbs_Line:
                    p1 = adaptor.Value(first)
                    p2 = adaptor.Value(last)
                    x1, y1 = coord_map(p1)
                    x2, y2 = coord_map(p2)
                    if (x1 - x2) ** 2 + (y1 - y2) ** 2 < eps ** 2:
                        exp.Next()
                        continue
                    ax, ay = round(x1 * scale, 2), round(y1 * scale, 2)
                    bx, by = round(x2 * scale, 2), round(y2 * scale, 2)
                    if (ax, ay) < (bx, by):
                        sig = ("L", ax, ay, bx, by)
                    else:
                        sig = ("L", bx, by, ax, ay)
                    if sig in seen:
                        exp.Next()
                        continue
                    seen.add(sig)
                    msp.add_line((x1 * scale, y1 * scale), (x2 * scale, y2 * scale))
                    edge_count += 1

                elif ctype == GeomAbs_Circle:
                    circle = adaptor.Circle()
                    center = circle.Location()
                    radius = circle.Radius()
                    cx, cy = coord_map(center)
                    cr = round(cx * scale, 2)
                    cy2 = round(cy * scale, 2)
                    rr = round(radius * scale, 2)
                    angle_len = abs(last - first)
                    if angle_len >= 2 * math.pi - 1e-6:
                        sig = ("C", cr, cy2, rr)
                    else:
                        sa = round(first, 3)
                        ea = round(last, 3)
                        sig = ("A", cr, cy2, rr, sa, ea)
                    if sig in seen:
                        exp.Next()
                        continue
                    seen.add(sig)
                    if angle_len >= 2 * math.pi - 1e-6:
                        msp.add_circle((cx * scale, cy * scale), radius * scale)
                    else:
                        msp.add_arc((cx * scale, cy * scale), radius * scale,
                                    math.degrees(first), math.degrees(last))
                    edge_count += 1

                elif ctype == GeomAbs_BSplineCurve:
                    bspline = adaptor.BSpline()
                    degree = bspline.Degree()
                    npoles = bspline.NbPoles()
                    poles = []
                    for i in range(1, npoles + 1):
                        pt = bspline.Pole(i)
                        x, y = coord_map(pt)
                        poles.append((x * scale, y * scale, 0))
                    nknots = bspline.NbKnots()
                    knots = [bspline.Knot(i) for i in range(1, nknots + 1)]
                    if bspline.IsRational():
                        weights = [bspline.Weight(i) for i in range(1, npoles + 1)]
                    else:
                        weights = None
                    try:
                        msp.add_spline(control_points=poles, degree=min(degree, 3),
                                       knots=knots, weights=weights)
                    except:
                        pts = []
                        for i in range(21):
                            t = first + (last - first) * i / 20
                            p = adaptor.Value(t)
                            x, y = coord_map(p)
                            pts.append((x * scale, y * scale))
                        msp.add_lwpolyline(pts)
                    edge_count += 1

                else:
                    pts = []
                    for i in range(21):
                        t = first + (last - first) * i / 20
                        p = adaptor.Value(t)
                        x, y = coord_map(p)
                        pts.append((x * scale, y * scale))
                    msp.add_lwpolyline(pts)
                    edge_count += 1

            except:
                pass
            exp.Next()

    doc.saveas(output_path)
    return edge_count


def convert_step_to_dxf(step_path, output_dir, progress_callback=None):
    import cadquery as cq
    step_path = os.path.abspath(step_path)
    output_dir = os.path.abspath(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    base_name = os.path.splitext(os.path.basename(step_path))[0]

    if progress_callback:
        progress_callback(0, "Importing STEP file...")

    unit_factor = detect_step_unit(step_path)

    try:
        result = cq.importers.importStep(step_path)
    except Exception as e:
        raise RuntimeError(f"Failed to import STEP file: {e}")

    shape = result.val().wrapped

    if progress_callback:
        progress_callback(15, "Generating 3 orthographic views (HLR)...")

    generated = []
    total_views = len(VIEWS)
    for i, (view_name, view_info) in enumerate(VIEWS.items()):
        filename = f"{base_name}_{view_name}.dxf"
        filepath = os.path.join(output_dir, filename)
        scale = unit_factor
        try:
            count = view_to_dxf(shape, view_info, filepath, scale)
        except Exception as e:
            if progress_callback:
                progress_callback(15 + int(85 * (i + 1) / total_views),
                                  f"Error on {view_name}: {e}")
            continue
        generated.append(filepath)
        if progress_callback:
            pct = 15 + int(85 * (i + 1) / total_views)
            progress_callback(pct, f"Exported {view_name} ({count} entities)")

    if progress_callback:
        progress_callback(100, f"Done. {len(generated)} DXF files generated.")
    return generated


# ─── GUI Application ──────────────────────────────────────────────────────────

class StepToDxfApp:
    def __init__(self, root):
        self.root = root
        self.root.title(APP_NAME)
        self.root.resizable(False, False)

        if getattr(sys, 'frozen', False):
            base_dir = sys._MEIPASS
        else:
            base_dir = os.path.dirname(os.path.abspath(__file__))

        self._icon_png = os.path.join(base_dir, "hello_kitty_logo.png")
        self._icon_ico = os.path.join(base_dir, "hello_kitty_logo.ico")

        # Load logo image for in-app display (needed before _build_ui)
        self.logo_image = None
        if os.path.exists(self._icon_png):
            try:
                pil_img = Image.open(self._icon_png)
                logo = pil_img.resize((80, 80), Image.LANCZOS)
                if logo.mode == 'P':
                    logo = logo.convert('RGBA' if pil_img.info.get('transparency') else 'RGB')
                self.logo_image = ImageTk.PhotoImage(logo)
            except:
                pass

        # Defer window icon setup to ensure window is fully initialized
        self.root.after(50, self._setup_icons)

        self._build_ui()
        self.converting = False

    def _setup_icons(self):
        ico = self._icon_ico
        png = self._icon_png

        # Method 1: iconbitmap (Windows taskbar / ALT+TAB)
        if os.path.exists(ico):
            try:
                self.root.iconbitmap(default=ico)
                self.root.iconbitmap(ico)
            except:
                pass

        # Method 2: iconphoto (title bar)
        if os.path.exists(png):
            try:
                pil_img = Image.open(png)
                # Logo display (80x80)
                logo = pil_img.resize((80, 80), Image.LANCZOS)
                if logo.mode == 'P':
                    logo = logo.convert('RGBA' if pil_img.info.get('transparency') else 'RGB')
                self.logo_image = ImageTk.PhotoImage(logo)
                # Title bar icon (32x32)
                tb = pil_img.resize((32, 32), Image.LANCZOS)
                if tb.mode == 'P':
                    tb = tb.convert('RGBA' if pil_img.info.get('transparency') else 'RGB')
                tb_photo = ImageTk.PhotoImage(tb)
                self.root.tk.call('wm', 'iconphoto', self.root._w, '-default', tb_photo)
                self._tb_photo = tb_photo
            except:
                pass

    def _build_ui(self):
        main_frame = ttk.Frame(self.root, padding=(15, 10))
        main_frame.pack(fill=tk.BOTH, expand=True)

        top_frame = ttk.Frame(main_frame)
        top_frame.pack(fill=tk.X, pady=(0, 10))

        if self.logo_image:
            logo_label = ttk.Label(top_frame, image=self.logo_image)
            logo_label.pack(side=tk.LEFT, padx=(0, 10))

        title_frame = ttk.Frame(top_frame)
        title_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Label(title_frame, text=APP_NAME,
                  font=("Segoe UI", 14, "bold")).pack(anchor=tk.W)
        ttk.Label(title_frame, text="STEP/STP \u2192 DXF  |  Top / Front / Left",
                  font=("Segoe UI", 9)).pack(anchor=tk.W)

        design_label = ttk.Label(top_frame, text=DESIGN_BY,
                                 font=("Microsoft YaHei", 8, "italic"),
                                 foreground="#888888")
        design_label.pack(side=tk.RIGHT, padx=(10, 0))

        ttk.Separator(main_frame, orient=tk.HORIZONTAL).pack(fill=tk.X, pady=(0, 10))

        # Input file
        input_frame = ttk.LabelFrame(main_frame, text="Input 3D File", padding=(10, 8))
        input_frame.pack(fill=tk.X, pady=(0, 8))
        fi_row = ttk.Frame(input_frame)
        fi_row.pack(fill=tk.X)
        self.input_var = tk.StringVar()
        ttk.Entry(fi_row, textvariable=self.input_var, width=55).pack(
            side=tk.LEFT, padx=(0, 5), fill=tk.X, expand=True)
        ttk.Button(fi_row, text="Browse...", command=self._browse_input).pack(side=tk.RIGHT)

        # Output dir
        out_frame = ttk.LabelFrame(main_frame, text="Output Directory", padding=(10, 8))
        out_frame.pack(fill=tk.X, pady=(0, 8))
        fo_row = ttk.Frame(out_frame)
        fo_row.pack(fill=tk.X)
        self.output_var = tk.StringVar()
        ttk.Entry(fo_row, textvariable=self.output_var, width=55).pack(
            side=tk.LEFT, padx=(0, 5), fill=tk.X, expand=True)
        ttk.Button(fo_row, text="Browse...", command=self._browse_output).pack(side=tk.RIGHT)

        # Progress
        self.progress_var = tk.IntVar()
        self.progress_bar = ttk.Progressbar(main_frame, orient=tk.HORIZONTAL,
                                            length=400, mode='determinate',
                                            variable=self.progress_var)
        self.progress_bar.pack(fill=tk.X, pady=(5, 2))
        self.status_var = tk.StringVar(value="Ready")
        ttk.Label(main_frame, textvariable=self.status_var,
                  font=("Segoe UI", 8)).pack(anchor=tk.W, pady=(0, 8))

        # Buttons
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X)
        self.open_btn = ttk.Button(btn_frame, text="Open Output Folder",
                                   command=self._open_output, state=tk.DISABLED)
        self.open_btn.pack(side=tk.RIGHT, padx=(5, 0))
        self.convert_btn = ttk.Button(btn_frame, text="Convert",
                                      command=self._start_conversion, width=15)
        self.convert_btn.pack(side=tk.RIGHT)

        self.root.bind('<Return>', lambda e: self._start_conversion())

    def _browse_input(self):
        path = filedialog.askopenfilename(
            title="Select STEP/STP file",
            filetypes=[("STEP files", "*.stp *.step *.STP *.STEP"), ("All files", "*.*")])
        if path:
            self.input_var.set(path)
            default_out = os.path.join(os.path.dirname(path), "DXF_Output")
            if not self.output_var.get():
                self.output_var.set(default_out)

    def _browse_output(self):
        path = filedialog.askdirectory(title="Select output directory")
        if path:
            self.output_var.set(path)

    def _open_output(self):
        out_path = self.output_var.get().strip()
        if out_path and os.path.exists(out_path):
            os.startfile(out_path)
        else:
            messagebox.showinfo("Info", "Output directory does not exist yet.")

    def _start_conversion(self):
        if self.converting:
            return
        in_path = self.input_var.get().strip()
        out_path = self.output_var.get().strip()
        if not in_path:
            messagebox.showwarning("Warning", "Please select an input STEP/STP file.")
            return
        if not os.path.isfile(in_path):
            messagebox.showerror("Error", "Input file does not exist.")
            return
        if not in_path.lower().endswith(('.stp', '.step')):
            if not messagebox.askyesno("Confirm", "File does not have .stp/.step extension. Continue?"):
                return
        if not out_path:
            out_path = os.path.join(os.path.dirname(in_path), "DXF_Output")
            self.output_var.set(out_path)

        self.converting = True
        self.convert_btn.config(state=tk.DISABLED, text="Converting...")
        self.open_btn.config(state=tk.DISABLED)
        self.progress_var.set(0)
        self.status_var.set("Starting...")

        def task():
            try:
                files = convert_step_to_dxf(in_path, out_path,
                                            progress_callback=self._update_progress)
                self.root.after(0, lambda: self._on_complete(files, out_path))
            except Exception as e:
                self.root.after(0, lambda: self._on_error(str(e)))

        threading.Thread(target=task, daemon=True).start()

    def _update_progress(self, pct, msg):
        self.root.after(0, lambda: self.progress_var.set(pct))
        self.root.after(0, lambda: self.status_var.set(msg))

    def _on_complete(self, files, out_path):
        self.converting = False
        self.convert_btn.config(state=tk.NORMAL, text="Convert")
        if files:
            self.open_btn.config(state=tk.NORMAL)
            self.status_var.set(f"Done. {len(files)} DXF files generated.")
            messagebox.showinfo(
                "Success",
                f"Generated {len(files)} DXF files:\n" +
                "\n".join(os.path.basename(f) for f in files) +
                f"\n\nLocation: {out_path}")
        else:
            self.status_var.set("No files generated.")
            messagebox.showwarning("Warning", "No DXF files were generated.")

    def _on_error(self, msg):
        self.converting = False
        self.convert_btn.config(state=tk.NORMAL, text="Convert")
        self.status_var.set("Error occurred.")
        messagebox.showerror("Error", msg)


def main():
    root = tk.Tk()
    app = StepToDxfApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
