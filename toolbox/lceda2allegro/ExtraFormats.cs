// SPDX-License-Identifier: GPL-3.0-only
// Native Altium PCB 6 binary library and PADS V9 ASCII decal writers.
// Format references and verification details are documented in FORMATS.md.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
namespace Xiaokai.LcedaAllegro {
public sealed class ExportOptions {
    public bool Altium, Pads;
    public string[] Formats { get { var n=new List<string>{"Allegro"};if(Altium)n.Add("AD");if(Pads)n.Add("PADS");return n.ToArray(); } }
}
public static class ExtraFormats {
    public static void Validate(Footprint fp,ExportOptions options){
        if((options.Altium||options.Pads)&&fp.Pads.Any(p=>p.Slot>0))throw new InvalidDataException("当前槽孔封装支持 Allegro 输出；请取消 AD/PADS 勾选后重试，避免导出错误的圆孔。");
        if((options.Altium||options.Pads)&&fp.Pads.Any(p=>p.Shape=="POLYGON"))throw new InvalidDataException("当前异形焊盘支持 Allegro 输出；请取消 AD/PADS 勾选后重试，避免丢失原始轮廓。");
    }
    public static void Write(Footprint fp,string stage,ExportOptions options,Action<string> log,Func<bool> cancelled){
        if(cancelled())throw new OperationCanceledException();
        Validate(fp,options);
        if(options.Altium){string dir=Path.Combine(stage,"AD");Directory.CreateDirectory(dir);AltiumLibrary.Write(fp,Path.Combine(dir,fp.Name+".PcbLib"));log("已生成 AD 封装库："+fp.Name+".PcbLib");}
        if(cancelled())throw new OperationCanceledException();
        if(options.Pads){string dir=Path.Combine(stage,"PADS");Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,fp.Name+".d"),PadsLibrary.Write(fp),Encoding.ASCII);log("已生成 PADS 封装库："+fp.Name+".d（封装名："+PadsLibrary.Name(fp)+"）");}
        if(cancelled())throw new OperationCanceledException();
    }
    public static string Instructions(ExportOptions options){
        var s=new StringBuilder();
        if(options.Altium)s.Append("\r\nAD：AD 子目录内的 .PcbLib 可直接用 Altium Designer 打开或加入封装库。\r\n");
        if(options.Pads)s.Append("\r\nPADS：在 PADS Layout 的 File → Library 中选择目标库，点击 Import，导入 PADS 子目录内的 .d 文件（PCB Decals）。单位为 mm。图层沿用标准默认层：21 顶阻焊、28 底阻焊、23 顶钢网、22 底钢网、26 顶丝印、29 底丝印、27 顶装配、30 底装配；如使用自定义层映射，请核对 CAM 输出。\r\n");
        return s.ToString();
    }
}
// Windows structured storage keeps the application self-contained; no external runtime or writer DLL.
public static class CompoundStorage {
    [ComImport,Guid("0000000B-0000-0000-C000-000000000046"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface Storage {
        void CreateStream([MarshalAs(UnmanagedType.LPWStr)] string name,uint mode,uint reserved1,uint reserved2,out IStream stream);
        void OpenStream([MarshalAs(UnmanagedType.LPWStr)] string name,IntPtr reserved1,uint mode,uint reserved2,out IStream stream);
        void CreateStorage([MarshalAs(UnmanagedType.LPWStr)] string name,uint mode,uint reserved1,uint reserved2,out Storage storage);
        void OpenStorage([MarshalAs(UnmanagedType.LPWStr)] string name,Storage priority,uint mode,IntPtr exclude,uint reserved,out Storage storage);
        void CopyTo(uint count,IntPtr exclude,IntPtr names,Storage dest);
        void MoveElementTo([MarshalAs(UnmanagedType.LPWStr)] string name,Storage dest,[MarshalAs(UnmanagedType.LPWStr)] string newName,uint flags);
        void Commit(uint flags);void Revert();void EnumElements(uint reserved1,IntPtr reserved2,uint reserved3,out IntPtr enumerator);
        void DestroyElement([MarshalAs(UnmanagedType.LPWStr)] string name);
        void RenameElement([MarshalAs(UnmanagedType.LPWStr)] string oldName,[MarshalAs(UnmanagedType.LPWStr)] string newName);
        void SetElementTimes([MarshalAs(UnmanagedType.LPWStr)] string name,IntPtr create,IntPtr access,IntPtr modify);
        void SetClass(ref Guid clsid);void SetStateBits(uint state,uint mask);void Stat(out System.Runtime.InteropServices.ComTypes.STATSTG stat,uint flags);
    }
    [DllImport("ole32.dll",CharSet=CharSet.Unicode)]static extern int StgCreateDocfile(string name,uint mode,uint reserved,out Storage result);
    [DllImport("ole32.dll",CharSet=CharSet.Unicode)]static extern int StgOpenStorage(string name,Storage priority,uint mode,IntPtr exclude,uint reserved,out Storage result);
    public static void Write(string path,Dictionary<string,byte[]> streams){
        Storage root;Marshal.ThrowExceptionForHR(StgCreateDocfile(path,0x1012,0,out root));
        var stores=new Dictionary<string,Storage>{{"",root}};
        try{foreach(var entry in streams){string[] names=entry.Key.Split('/');string key="";Storage parent=root;
            for(int i=0;i<names.Length-1;i++){key+=(key.Length==0?"":"/")+names[i];Storage next;if(!stores.TryGetValue(key,out next)){parent.CreateStorage(names[i],0x1012,0,0,out next);stores.Add(key,next);}parent=next;}
            IStream stream;parent.CreateStream(names.Last(),0x1012,0,0,out stream);try{stream.Write(entry.Value,entry.Value.Length,IntPtr.Zero);}finally{Marshal.ReleaseComObject(stream);}}
            root.Commit(0);
        }finally{foreach(var store in stores.Values.Reverse())Marshal.ReleaseComObject(store);}
    }
    public static byte[] Read(string path,string name){
        Storage root;Marshal.ThrowExceptionForHR(StgOpenStorage(path,null,0x20,IntPtr.Zero,0,out root));var opened=new List<Storage>{root};
        try{var parent=root;string[] parts=name.Split('/');for(int i=0;i<parts.Length-1;i++){Storage child;parent.OpenStorage(parts[i],null,0x10,IntPtr.Zero,0,out child);opened.Add(child);parent=child;}IStream stream;parent.OpenStream(parts.Last(),IntPtr.Zero,0x10,0,out stream);try{System.Runtime.InteropServices.ComTypes.STATSTG stat;stream.Stat(out stat,1);byte[] data=new byte[checked((int)stat.cbSize)];stream.Read(data,data.Length,IntPtr.Zero);return data;}finally{Marshal.ReleaseComObject(stream);}}
        finally{foreach(var item in opened.AsEnumerable().Reverse())Marshal.ReleaseComObject(item);}
    }
}
public static class AltiumLibrary {
    const double RawPerMm=10000.0/.0254;
    public static int Raw(double mm){return checked((int)Math.Round(mm*RawPerMm,MidpointRounding.AwayFromZero));}
    static byte[] Bytes(Action<BinaryWriter> write){using(var m=new MemoryStream()){using(var w=new BinaryWriter(m)){write(w);return m.ToArray();}}}
    static void Block(BinaryWriter w,byte[] value){w.Write(value.Length);w.Write(value);}
    static void Block(BinaryWriter w,Action<BinaryWriter> write){Block(w,Bytes(write));}
    static void Short(BinaryWriter w,string value){byte[] b=Encoding.GetEncoding(1252).GetBytes(value);if(b.Length>255)throw new InvalidDataException("AD 名称过长");w.Write((byte)b.Length);w.Write(b);}
    static void Name(BinaryWriter w,string value){Block(w,x=>Short(x,value));}
    static void Params(BinaryWriter w,string value){Block(w,Encoding.GetEncoding(1252).GetBytes(value+"\0"));}
    static void XY(BinaryWriter w,double x,double y){w.Write(Raw(x));w.Write(Raw(y));}
    static void Common(BinaryWriter w,int layer){w.Write((byte)layer);w.Write((ushort)12);w.Write((ushort)0xffff);w.Write((ushort)0xffff);w.Write((ushort)0xffff);w.Write(0xffffffffu);}
    static uint V7(int layer){if(layer==32)return 0x0100ffff;if(layer>=1&&layer<=31)return 0x01000000u+(uint)layer;if(layer>=57&&layer<=72)return 0x01020000u+(uint)(layer-56);return 0x01030000u+(uint)(layer>=33&&layer<=38?layer-27:15);}
    public static int Layer(string layer){switch(layer){case "ETCH/TOP":return 1;case "ETCH/BOTTOM":return 32;case "PACKAGE GEOMETRY/SILKSCREEN_TOP":return 33;case "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM":return 34;case "PACKAGE GEOMETRY/PASTEMASK_TOP":return 35;case "PACKAGE GEOMETRY/PASTEMASK_BOTTOM":return 36;case "PACKAGE GEOMETRY/SOLDERMASK_TOP":return 37;case "PACKAGE GEOMETRY/SOLDERMASK_BOTTOM":return 38;case "PACKAGE GEOMETRY/ASSEMBLY_TOP":return 57;case "PACKAGE GEOMETRY/ASSEMBLY_BOTTOM":return 58;default:throw new InvalidDataException("AD 未映射图层："+layer);}}
    static void Put(byte[] bytes,int offset,int value){Array.Copy(BitConverter.GetBytes(value),0,bytes,offset,4);}
    static void PadRecord(BinaryWriter w,Pad pad){
        w.Write((byte)2);Name(w,pad.Number);Name(w,"");Name(w,"|&|0");Block(w,new byte[]{0});
        int layer=pad.Layer==11?74:pad.Layer==2?32:1;
        Block(w,b=>{
            Common(b,layer);XY(b,pad.X,pad.Y);double width=pad.Layer==11&&!pad.Plated?0:pad.W,height=pad.Layer==11&&!pad.Plated?0:pad.H;
            for(int i=0;i<3;i++)XY(b,width,height);b.Write(Raw(pad.Drill));byte shape=(byte)(pad.Shape=="RECT"?2:1);b.Write(shape);b.Write(shape);b.Write(shape);
            b.Write((pad.Angle%360+360)%360);b.Write(pad.Plated);
            byte[] tail=new byte[141];Put(tail,68-61,Raw(.254));tail[72-61]=4;Put(tail,74-61,Raw(.254));Put(tail,78-61,Raw(.508));Put(tail,82-61,Raw(.508));Put(tail,86-61,Raw(pad.Paste));Put(tail,90-61,Raw(pad.Mask));tail[101-61]=2;tail[102-61]=2;Put(tail,114-61,unchecked((int)V7(layer)));Put(tail,121-61,Raw(pad.Mask));
            Guid.NewGuid().ToByteArray().CopyTo(tail,126-61);Guid.NewGuid().ToByteArray().CopyTo(tail,142-61);Put(tail,162-61,int.MaxValue);Put(tail,166-61,int.MaxValue);tail[171-61]=1;tail[172-61]=26;tail[184-61]=1;tail[185-61]=1;b.Write(tail);
        });
        // Simple stacks do not need the optional per-internal-layer size/shape block.
        Block(w,new byte[0]);
    }
    static void TrackRecord(BinaryWriter w,Pt a,Pt b,double width,int layer){w.Write((byte)4);Block(w,x=>{Common(x,layer);XY(x,a.X,a.Y);XY(x,b.X,b.Y);x.Write(Raw(width));x.Write((short)0);x.Write(0);x.Write((short)0);x.Write(V7(layer));x.Write(new byte[4]);});}
    static void RegionRecord(BinaryWriter w,Drawing drawing){int layer=Layer(drawing.Layer);w.Write((byte)11);Block(w,b=>{Common(b,layer);b.Write(new byte[5]);Params(b,"V7_LAYER="+LayerName(layer)+"|NAME=|KIND=0|SUBPOLYINDEX=-1|UNIONINDEX=0|ARCRESOLUTION=0.2mil|ISSHAPEBASED=FALSE|CAVITYHEIGHT=0mil");var points=drawing.Points;if(points.Count>1&&Pt.Dist(points[0],points.Last())<.000001)points=points.Take(points.Count-1).ToList();b.Write(points.Count);foreach(var pt in points){b.Write((double)Raw(pt.X));b.Write((double)Raw(pt.Y));}});}
    static string LayerName(int layer){switch(layer){case 1:return "TOP";case 32:return "BOTTOM";case 33:return "TOPOVERLAY";case 34:return "BOTTOMOVERLAY";case 35:return "TOPPASTE";case 36:return "BOTTOMPASTE";case 37:return "TOPSOLDER";case 38:return "BOTTOMSOLDER";case 57:return "MECHANICAL1";case 58:return "MECHANICAL2";default:return "MULTILAYER";}}
    public static string Section(string name){return name.Length>31?name.Substring(0,26)+"_LCED":name;}
    public static void Write(Footprint fp,string path){
        string section=Section(fp.Name);var streams=new Dictionary<string,byte[]>();
        streams["FileHeader"]=Bytes(w=>{string text="PCB 6.0 Binary Library File";w.Write(text.Length);Short(w,text);w.Write(5.01);w.Write(8);Short(w,Guid.NewGuid().ToString("N").Substring(0,8).ToUpperInvariant());});
        if(section!=fp.Name)streams["SectionKeys"]=Bytes(w=>{w.Write(1);Name(w,fp.Name);Name(w,section);});
        streams["Library/Header"]=BitConverter.GetBytes(1);
        streams["Library/Data"]=Bytes(w=>{Params(w,"|KIND=Protel_Advanced_PCB_Library|VERSION=3.00|HEADER=PCB 6.0 Binary Library File|WEIGHT=1");w.Write(1);Name(w,fp.Name);});
        streams["Library/Models/Header"]=BitConverter.GetBytes(0);streams["Library/Models/Data"]=new byte[0];
        streams[section+"/Parameters"]=Bytes(w=>Params(w,"|PATTERN="+fp.Name+"|HEIGHT=0mil|DESCRIPTION=LCEDA "+fp.Code+"|ITEMGUID=|REVISIONGUID="));
        streams[section+"/WideStrings"]=Bytes(w=>Params(w,""));
        int primitives=fp.Pads.Count+fp.Drawings.Sum(d=>d.Filled?1:Math.Max(0,d.Points.Count-1));streams[section+"/Header"]=BitConverter.GetBytes(primitives);
        streams[section+"/Data"]=Bytes(w=>{Name(w,fp.Name);foreach(var pad in fp.Pads)PadRecord(w,pad);foreach(var d in fp.Drawings){if(d.Filled)RegionRecord(w,d);else for(int i=1;i<d.Points.Count;i++)TrackRecord(w,d.Points[i-1],d.Points[i],d.Width,Layer(d.Layer));}});
        CompoundStorage.Write(path,streams);
    }
}
public static class PadsLibrary {
    public static string Name(Footprint fp){if(fp.Name.Length<=40)return fp.Name;using(var hash=System.Security.Cryptography.SHA256.Create()){string suffix=BitConverter.ToString(hash.ComputeHash(Encoding.ASCII.GetBytes(fp.Name))).Replace("-","").Substring(0,8);return fp.Name.Substring(0,31)+"_"+suffix;}}
    static string F(double value){return ConvertCore.F(value);}
    public static int Layer(string name){switch(name){case "ETCH/TOP":return 1;case "ETCH/BOTTOM":return 2;case "PACKAGE GEOMETRY/SILKSCREEN_TOP":return 26;case "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM":return 29;case "PACKAGE GEOMETRY/PASTEMASK_TOP":return 23;case "PACKAGE GEOMETRY/PASTEMASK_BOTTOM":return 22;case "PACKAGE GEOMETRY/SOLDERMASK_TOP":return 21;case "PACKAGE GEOMETRY/SOLDERMASK_BOTTOM":return 28;case "PACKAGE GEOMETRY/ASSEMBLY_TOP":return 27;case "PACKAGE GEOMETRY/ASSEMBLY_BOTTOM":return 30;default:throw new InvalidDataException("PADS 未映射图层："+name);}}
    static string PadLayer(int layer,Pad pad,double w,double h){
        string shape=pad.Shape=="ELLIPSE"?"R":pad.Shape=="OVAL"?"OF":"RF";
        if(w<=0||h<=0)return layer+" 0 R";
        if(shape=="R")return layer+" "+F(w)+" R";
        // PADS finger width is local Y, length is local X. Rotation is counterclockwise.
        return layer+" "+F(h)+" "+shape+(shape=="RF"?" 0":"")+" "+F((pad.Angle%180+180)%180)+" "+F(w)+" 0";
    }
    public static string Write(Footprint fp){
        foreach(var pad in fp.Pads)if(pad.Number.Length>7)throw new InvalidDataException("PADS 引脚编号最多 7 个字符："+pad.Number);
        var b=new StringBuilder("*PADS-LIBRARY-PCB-DECALS-V9*\r\n");
        b.AppendLine(Name(fp)+" M 0 0 0 1 "+fp.Drawings.Count+" 0 "+fp.Pads.Count+" "+fp.Pads.Count+" 0");
        b.AppendLine("TIMESTAMP "+DateTime.UtcNow.ToString("yyyy.MM.dd.HH.mm.ss",ConvertCore.Inv));
        b.AppendLine("0 0 0 0 1 0.15 26 17 33 \"Default Font\"");b.AppendLine("REF-DES");
        foreach(var d in fp.Drawings){int layer=Layer(d.Layer);bool closed=d.Points.Count>2&&Pt.Dist(d.Points[0],d.Points.Last())<.000001;b.AppendLine((d.Filled?"COPCLS":closed?"CLOSED":"OPEN")+" "+d.Points.Count+" "+F(d.Width)+" "+layer+" -1");foreach(var pt in d.Points)b.AppendLine(F(pt.X)+" "+F(pt.Y));}
        int index=0;foreach(var pad in fp.Pads){index++;string number=pad.Number.Length==0?"MH"+index:pad.Number;b.AppendLine("T"+F(pad.X)+" "+F(pad.Y)+" "+F(pad.X)+" "+F(pad.Y)+" "+number);}
        index=0;foreach(var pad in fp.Pads){index++;var lines=new List<string>();bool through=pad.Layer==11;
            if(through){foreach(int layer in new[]{-2,-1,0})lines.Add(PadLayer(layer,pad,pad.Plated?pad.W:0,pad.Plated?pad.H:0));}
            else{lines.Add(PadLayer(-2,pad,pad.Layer==1?pad.W:0,pad.Layer==1?pad.H:0));lines.Add("-1 0 R");lines.Add(PadLayer(0,pad,pad.Layer==2?pad.W:0,pad.Layer==2?pad.H:0));}
            foreach(int side in through?new[]{1,2}:new[]{pad.Layer}){lines.Add(PadLayer(side==1?21:28,pad,pad.W+2*pad.Mask,pad.H+2*pad.Mask));if(!through&&pad.W+2*pad.Paste>0&&pad.H+2*pad.Paste>0)lines.Add(PadLayer(side==1?23:22,pad,pad.W+2*pad.Paste,pad.H+2*pad.Paste));}
            b.AppendLine("PAD "+index+" "+lines.Count+" "+(pad.Plated?"P":"N")+" "+F(pad.Drill));foreach(string line in lines)b.AppendLine(line);
        }
        b.AppendLine("*END*");return b.ToString().Replace("\r\r\n","\r\n");
    }
}
}
