# SPDX-License-Identifier: GPL-3.0-only
import os
import sys
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import threading
from pathlib import Path
import math

from gerbonara import GerberFile, MM
from gerbonara.graphic_objects import Line, Arc, Flash, Region
from gerbonara.apertures import CircleAperture, RectangleAperture, ObroundAperture
from gerbonara.aperture_macros.primitive import PRIMITIVE_CLASSES
# Some CAD tools (e.g. Cadence Allegro) use primitive code 22 for regular polygon (same as code 5)
PRIMITIVE_CLASSES.setdefault(22, PRIMITIVE_CLASSES[5])
import ezdxf

INCH_TO_MM = 25.4


def generate_arc_points(x1, y1, x2, y2, cx, cy, clockwise, segments=64):
    r = math.hypot(x1 - cx, y1 - cy)
    if r < 1e-10:
        return [(x1, y1), (x2, y2)]
    start_a = math.atan2(y1 - cy, x1 - cx)
    end_a = math.atan2(y2 - cy, x2 - cx)
    if clockwise:
        while end_a > start_a:
            end_a -= 2 * math.pi
    else:
        while end_a < start_a:
            end_a += 2 * math.pi
    total_angle = end_a - start_a
    if abs(total_angle) < 1e-10:
        total_angle = 2 * math.pi if not clockwise else -2 * math.pi
    steps = max(2, int(segments * abs(total_angle) / (2 * math.pi)))
    pts = []
    for i in range(steps + 1):
        a = start_a + total_angle * (i / steps)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def to_mm(val, unit):
    return val * INCH_TO_MM if unit == 'in' else val


def rotate_point(px, py, cx, cy, angle):
    cos_r = math.cos(angle)
    sin_r = math.sin(angle)
    dx = px - cx
    dy = py - cy
    return (cx + dx * cos_r - dy * sin_r, cy + dx * sin_r + dy * cos_r)


def generate_obround_outline(x, y, w, h, arc_segments=16):
    r = min(w, h) / 2
    d = abs(w - h) / 2
    pts = []
    if w > h:
        lcx, lcy = x - d, y
        rcx, rcy = x + d, y
        pts.append((lcx, y - r))
        pts.append((rcx, y - r))
        for i in range(1, arc_segments + 1):
            a = -math.pi / 2 + math.pi * (i / arc_segments)
            pts.append((rcx + r * math.cos(a), rcy + r * math.sin(a)))
        pts.append((lcx, y + r))
        for i in range(1, arc_segments + 1):
            a = math.pi / 2 + math.pi * (i / arc_segments)
            pts.append((lcx + r * math.cos(a), lcy + r * math.sin(a)))
    elif h > w:
        tcx, tcy = x, y - d
        bcx, bcy = x, y + d
        for i in range(arc_segments + 1):
            a = math.pi / 2 + math.pi * (i / arc_segments)
            pts.append((x + r * math.cos(a), bcy + r * math.sin(a)))
        for i in range(arc_segments + 1):
            a = -math.pi / 2 + math.pi * (i / arc_segments)
            pts.append((x + r * math.cos(a), tcy + r * math.sin(a)))
    else:
        for i in range(arc_segments * 2 + 1):
            a = 2 * math.pi * (i / (arc_segments * 2))
            pts.append((x + r * math.cos(a), y + r * math.sin(a)))
    return pts


def find_gerber_files(input_folder):
    gerber_extensions = {'.gbr', '.gtl', '.gbl', '.gts', '.gbs',
                         '.gto', '.gbo', '.gpt', '.gpb', '.gm1',
                         '.gm2', '.gko', '.cmp', '.sol', '.stc',
                         '.sts', '.plc', '.pls', '.art', '.ger', '.pho'}
    files = []
    for f in Path(input_folder).iterdir():
        if f.is_file() and f.suffix.lower() in gerber_extensions:
            files.append(f)
        elif f.is_file() and f.suffix.lower() == '':
            try:
                with open(f, 'r') as fh:
                    first = fh.read(1024)
                    if '%' in first and ('FS' in first or 'ADD' in first or 'MO' in first):
                        files.append(f)
            except:
                pass
    return files


def create_dxf_doc():
    doc = ezdxf.new('R2010')
    doc.header['$INSUNITS'] = 4
    doc.header['$MEASUREMENT'] = 1
    return doc


def process_gerber_file(filepath, msp, layer_name, dxf_doc):
    if layer_name not in dxf_doc.layers:
        dxf_doc.layers.new(name=layer_name)

    gf = GerberFile.open(filepath)
    lines_count = 0
    arcs_count = 0
    flashes_count = 0
    regions_count = 0

    for obj in gf.objects:
        if isinstance(obj, Line):
            x1 = to_mm(obj.x1, obj.unit)
            y1 = to_mm(obj.y1, obj.unit)
            x2 = to_mm(obj.x2, obj.unit)
            y2 = to_mm(obj.y2, obj.unit)
            msp.add_lwpolyline([(x1, y1), (x2, y2)], dxfattribs={'layer': layer_name})
            lines_count += 1

        elif isinstance(obj, Arc):
            x1 = to_mm(obj.x1, obj.unit)
            y1 = to_mm(obj.y1, obj.unit)
            x2 = to_mm(obj.x2, obj.unit)
            y2 = to_mm(obj.y2, obj.unit)
            cx = x1 + to_mm(obj.cx, obj.unit)
            cy = y1 + to_mm(obj.cy, obj.unit)
            pts = generate_arc_points(x1, y1, x2, y2, cx, cy, obj.clockwise)
            if len(pts) >= 2:
                msp.add_lwpolyline(pts, dxfattribs={'layer': layer_name})
            arcs_count += 1

        elif isinstance(obj, Flash):
            x = to_mm(obj.x, obj.unit)
            y = to_mm(obj.y, obj.unit)
            apt = obj.aperture
            if isinstance(apt, CircleAperture):
                r = to_mm(apt.diameter, apt.unit) / 2
                msp.add_circle((x, y), radius=r, dxfattribs={'layer': layer_name})
            elif isinstance(apt, ObroundAperture):
                w = to_mm(apt.w, apt.unit)
                h = to_mm(apt.h, apt.unit)
                pts = generate_obround_outline(x, y, w, h)
                msp.add_lwpolyline(pts, close=True, dxfattribs={'layer': layer_name})
            elif isinstance(apt, RectangleAperture):
                w = to_mm(apt.w, apt.unit)
                h = to_mm(apt.h, apt.unit)
                pts = [(x - w/2, y - h/2), (x + w/2, y - h/2),
                        (x + w/2, y + h/2), (x - w/2, y + h/2)]
                msp.add_lwpolyline(pts, close=True, dxfattribs={'layer': layer_name})
            else:
                try:
                    eq = apt.equivalent_width()
                    if isinstance(eq, (int, float)) and eq > 0:
                        r = to_mm(eq, apt.unit) / 2
                        msp.add_circle((x, y), radius=r, dxfattribs={'layer': layer_name})
                        msp.add_line((x - r, y), (x + r, y), dxfattribs={'layer': layer_name})
                        msp.add_line((x, y - r), (x, y + r), dxfattribs={'layer': layer_name})
                except (ValueError, TypeError):
                    pass
            flashes_count += 1

        elif isinstance(obj, Region):
            raw_pts = obj.outline
            if len(raw_pts) < 3:
                continue
            pts = [(to_mm(p[0], obj.unit), to_mm(p[1], obj.unit)) for p in raw_pts]
            if obj.arc_centers and any(c is not None and c[1][0] is not None for c in obj.arc_centers):
                seg_count = min(len(pts), len(obj.arc_centers))
                final_pts = []
                for i in range(seg_count):
                    ac = obj.arc_centers[i]
                    if ac is not None and ac[1][0] is not None:
                        x1, y1 = pts[i]
                        x2, y2 = pts[(i + 1) % len(pts)]
                        arc_clockwise, (arc_cx, arc_cy) = ac
                        acx = to_mm(arc_cx, obj.unit)
                        acy = to_mm(arc_cy, obj.unit)
                        seg_pts = generate_arc_points(x1, y1, x2, y2, acx, acy, arc_clockwise, 32)
                        final_pts.extend(seg_pts[:-1] if seg_pts else [])
                    else:
                        final_pts.append(pts[i])
                if final_pts:
                    msp.add_lwpolyline(final_pts, close=True, dxfattribs={'layer': layer_name})
            else:
                if len(pts) >= 3:
                    msp.add_lwpolyline(pts, close=True, dxfattribs={'layer': layer_name})
            regions_count += 1

    return lines_count, arcs_count, flashes_count, regions_count


def convert_folder(input_folder, output_folder, progress_callback=None, status_callback=None):
    files = find_gerber_files(input_folder)
    if not files:
        if status_callback:
            status_callback("No Gerber files found in input folder")
        return False

    combined_path = os.path.join(output_folder, "combined_output.dxf")
    doc = create_dxf_doc()
    total = len(files)

    for idx, gerber_file in enumerate(files):
        base_name = os.path.splitext(gerber_file.name)[0]
        layer_name = base_name

        if status_callback:
            status_callback(f"Processing: {gerber_file.name} ({idx + 1}/{total})")

        try:
            msp = doc.modelspace()
            lc, ac, fc, rc = process_gerber_file(str(gerber_file), msp, layer_name, doc)
        except Exception as e:
            if status_callback:
                status_callback(f"Failed: {gerber_file.name} - {e}")
            import traceback
            traceback.print_exc()
            continue

        single_path = os.path.join(output_folder, base_name + ".dxf")
        try:
            s_doc = create_dxf_doc()
            s_msp = s_doc.modelspace()
            process_gerber_file(str(gerber_file), s_msp, '0', s_doc)
            s_doc.saveas(single_path)
        except Exception as e:
            if status_callback:
                status_callback(f"Save failed: {single_path} - {e}")

        if status_callback:
            status_callback(
                f"Done: {gerber_file.name} -> {base_name}.dxf "
                f"({lc} lines, {ac} arcs, {fc} flashes, {rc} regions)"
            )
        if progress_callback:
            progress_callback(int((idx + 1) / total * 100))

    try:
        doc.saveas(combined_path)
    except Exception as e:
        if status_callback:
            status_callback(f"Combined DXF save failed: {e}")

    if status_callback:
        status_callback(f"Conversion complete! Processed {total} files")
    return True


ICON_B64 = "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"


class GerberToDxfApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Gerber to DXF Converter v2.0")
        self.root.geometry("750x500")
        self.root.resizable(False, False)
        try:
            icon_photo = tk.PhotoImage(data=ICON_B64)
            self.root.iconphoto(True, icon_photo)
        except Exception:
            pass

        main_frame = ttk.Frame(root, padding="15")
        main_frame.pack(fill=tk.BOTH, expand=True)

        title_frame = ttk.Frame(main_frame)
        title_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(title_frame, text="Gerber to DXF Converter",
                  font=("Arial", 14, "bold")).pack(side=tk.LEFT)

        ttk.Label(title_frame, text="design by zhanshuting",
                  font=("Arial", 9, "italic")).pack(side=tk.RIGHT, padx=(0, 5))

        top_frame = ttk.Frame(main_frame)
        top_frame.pack(fill=tk.X, pady=(0, 10))

        left_panel = ttk.Frame(top_frame)
        left_panel.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        input_frame = ttk.LabelFrame(left_panel, text="Input GERBER Folder", padding="8")
        input_frame.pack(fill=tk.X, pady=(0, 8))

        self.input_var = tk.StringVar()
        input_entry = ttk.Entry(input_frame, textvariable=self.input_var)
        input_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))

        input_btn = ttk.Button(input_frame, text="Browse...", command=self.browse_input, width=10)
        input_btn.pack(side=tk.RIGHT)

        output_frame = ttk.LabelFrame(left_panel, text="Output DXF Folder", padding="8")
        output_frame.pack(fill=tk.X)

        self.output_var = tk.StringVar()
        output_entry = ttk.Entry(output_frame, textvariable=self.output_var)
        output_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))

        output_btn = ttk.Button(output_frame, text="Browse...", command=self.browse_output, width=10)
        output_btn.pack(side=tk.RIGHT)

        btn_panel = ttk.Frame(top_frame, width=160)
        btn_panel.pack(side=tk.RIGHT, fill=tk.Y, padx=(15, 0))
        btn_panel.pack_propagate(False)

        self.export_btn = ttk.Button(
            btn_panel,
            text="Export DXF",
            command=self.start_conversion,
            width=18
        )
        self.export_btn.pack()

        self.open_btn = ttk.Button(
            btn_panel,
            text="Open Output Folder",
            command=self.open_output_folder,
            width=18
        )
        self.open_btn.pack(pady=(6, 0))

        file_frame = ttk.LabelFrame(main_frame, text="Detected Gerber Files", padding="5")
        file_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 8))

        list_frame = ttk.Frame(file_frame)
        list_frame.pack(fill=tk.BOTH, expand=True)

        self.file_listbox = tk.Listbox(list_frame, font=("Consolas", 9), height=6)
        self.file_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        scrollbar = ttk.Scrollbar(list_frame, orient=tk.VERTICAL, command=self.file_listbox.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.file_listbox.configure(yscrollcommand=scrollbar.set)

        bottom_frame = ttk.Frame(main_frame)
        bottom_frame.pack(fill=tk.X)

        self.progress = ttk.Progressbar(bottom_frame, mode='determinate')
        self.progress.pack(fill=tk.X, pady=(0, 5))

        self.status_var = tk.StringVar(value="Ready")
        status_label = ttk.Label(bottom_frame, textvariable=self.status_var, font=("Consolas", 9))
        status_label.pack(fill=tk.X)

        self.input_var.trace_add('write', self.on_folder_change)
        self.output_var.trace_add('write', self.on_folder_change)

        self.root.mainloop()

    def browse_input(self):
        folder = filedialog.askdirectory(title="Select GERBER Input Folder")
        if folder:
            self.input_var.set(folder)

    def browse_output(self):
        folder = filedialog.askdirectory(title="Select DXF Output Folder")
        if folder:
            self.output_var.set(folder)

    def open_output_folder(self):
        folder = self.output_var.get().strip()
        if folder and os.path.isdir(folder):
            os.startfile(folder)
        elif folder:
            messagebox.showinfo("Info", "Output folder does not exist yet.\nRun Export DXF first to create it.")
        else:
            messagebox.showinfo("Info", "Please select an output folder first.")

    def on_folder_change(self, *args):
        folder = self.input_var.get().strip()
        self.file_listbox.delete(0, tk.END)
        if os.path.isdir(folder):
            files = find_gerber_files(folder)
            if files:
                for f in files:
                    size = os.path.getsize(f)
                    self.file_listbox.insert(tk.END, f"  {f.name}  ({size:,} bytes)")
            else:
                self.file_listbox.insert(tk.END, "  (no Gerber files found)")

    def start_conversion(self):
        input_folder = self.input_var.get().strip()
        output_folder = self.output_var.get().strip()

        if not input_folder:
            messagebox.showwarning("Warning", "Please select GERBER input folder first")
            return
        if not output_folder:
            messagebox.showwarning("Warning", "Please select DXF output folder first")
            return
        if not os.path.isdir(input_folder):
            messagebox.showerror("Error", "Input folder does not exist")
            return

        os.makedirs(output_folder, exist_ok=True)

        self.export_btn.config(state=tk.DISABLED)
        self.progress['value'] = 0

        self.file_listbox.delete(0, tk.END)
        self.file_listbox.insert(tk.END, "  Conversion in progress...")

        thread = threading.Thread(target=self.run_conversion, args=(input_folder, output_folder))
        thread.daemon = True
        thread.start()

    def run_conversion(self, input_folder, output_folder):
        def update_progress(value):
            self.root.after(0, lambda: self.progress.configure(value=value))

        def update_status(msg):
            self.root.after(0, lambda: self.status_var.set(msg))

        try:
            convert_folder(input_folder, output_folder, update_progress, update_status)
        except Exception as e:
            update_status(f"Conversion failed: {e}")
            import traceback
            traceback.print_exc()

        self.root.after(0, lambda: self.export_btn.config(state=tk.NORMAL))
        self.root.after(0, lambda: self.on_folder_change())


if __name__ == '__main__':
    root = tk.Tk()
    app = GerberToDxfApp(root)
