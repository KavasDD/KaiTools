// SPDX-License-Identifier: GPL-3.0-only
// Native Allegro footprint generation. No Cadence binaries or libraries are redistributed.
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
[assembly: AssemblyTitle("立创封装转 Allegro")]
[assembly: AssemblyVersion("1.3.0.0")]
namespace Xiaokai.LcedaAllegro {
public struct Pt {
    public double X,Y;
    public Pt(double x,double y){X=x;Y=y;}
    public static double Dist(Pt a,Pt b){return Math.Sqrt((a.X-b.X)*(a.X-b.X)+(a.Y-b.Y)*(a.Y-b.Y));}
}
public sealed class Pad {
    public string Number,SourceNumber,Shape,Name; public double X,Y,W,H,Angle,Drill,Slot,SlotAngle,Mask,Paste; public int Layer; public bool Plated=true; public List<Pt> Polygon=new List<Pt>();
}
public sealed class Drawing {
    public string Layer; public double Width; public bool Filled; public List<Pt> Points=new List<Pt>();
}
public sealed class Footprint {
    public string Code,Title,Name; public List<Pad> Pads=new List<Pad>(); public List<Drawing> Drawings=new List<Drawing>();
    public List<string> Warnings=new List<string>(); public double Extent=100;
}
public static class ConvertCore {
    public static readonly CultureInfo Inv=CultureInfo.InvariantCulture;
    public static readonly JavaScriptSerializer Json=new JavaScriptSerializer { MaxJsonLength=32*1024*1024,RecursionLimit=160 };
    public static string F(double n){if(double.IsNaN(n)||double.IsInfinity(n))throw new InvalidDataException("无效坐标");return n.ToString("0.######",Inv);}
    public static double N(string s){double n;if(!double.TryParse(s,NumberStyles.Float,Inv,out n)||double.IsNaN(n)||double.IsInfinity(n))throw new InvalidDataException("无效数值："+s);return n;}
    public static string Q(string s){return "\""+s.Replace("\\","/").Replace("\"","\\\"").Replace("\r"," ").Replace("\n"," ")+"\"";}
    public static Dictionary<string,object> Obj(object o){if(o is string)o=Json.DeserializeObject((string)o);var d=o as Dictionary<string,object>;if(d==null)throw new InvalidDataException("封装数据格式不正确");return d;}
    public static object Get(Dictionary<string,object> d,string k,object fallback){object v;return d.TryGetValue(k,out v)?v:fallback;}
    public static string Text(Dictionary<string,object>d,string k,string fallback){return System.Convert.ToString(Get(d,k,fallback),Inv);}
    public static string Field(string[] a,int i,string fallback){return a.Length>i&&!string.IsNullOrEmpty(a[i])?a[i]:fallback;}
    public static string Normalize(string value){var m=Regex.Match(value.Trim(),@"^C\d+$",RegexOptions.IgnoreCase);if(!m.Success)throw new ArgumentException("请输入立创编号，例如 C25804。");return m.Value.ToUpperInvariant();}
    public static string SafeName(string text){string s=Regex.Replace(text,@"[^A-Za-z0-9_]","_");s=Regex.Replace(s,"_+","_").Trim('_');return s.Length==0?"PACKAGE":s;}
    public static Dictionary<string,object> Result(string text){var d=Obj(Json.DeserializeObject(text));if(d.ContainsKey("success")&&!System.Convert.ToBoolean(d["success"],Inv))throw new InvalidDataException("立创接口返回失败："+Text(d,"message","未找到该元件"));if(d.ContainsKey("result"))d=Obj(d["result"]);return d;}
    public static Footprint Parse(string text,string code){
        var d=Result(text);Dictionary<string,object> package;
        if(d.ContainsKey("packageDetail")&&d["packageDetail"]!=null)package=Obj(d["packageDetail"]);
        else if(Text(d,"docType","")=="4")package=d;
        else throw new InvalidDataException("该元件没有标准版 PCB 封装数据。");
        var data=Obj(Get(package,"dataStr",null));var head=Obj(Get(data,"head",null));
        double ox=N(Text(head,"x","0")),oy=N(Text(head,"y","0"));
        var fp=new Footprint {Code=Normalize(code),Title=Text(package,"title",code)};
        // Match lceda::sanitizeFootprint in the existing Capture plugin.
        fp.Name=fp.Title.Replace(".","d");
        if(Regex.IsMatch(fp.Name,@"[^A-Za-z0-9_+\-]"))throw new InvalidDataException("源封装名包含 Allegro 不支持的字符："+fp.Name);
        if(fp.Name.Length>128)throw new InvalidDataException("源封装名称过长："+fp.Name);
        var shapes=Get(data,"shape",null) as IEnumerable;if(shapes==null)throw new InvalidDataException("封装缺少图形。");
        foreach(object item in shapes){
            string[] a=System.Convert.ToString(item,Inv).Split('~');string kind=a[0];
            try {
                if(kind=="PAD"){
                    if(a.Length<12)throw new InvalidDataException("焊盘字段不完整");
                    var p=new Pad {Shape=a[1],X=(N(a[2])-ox)*.254,Y=(oy-N(a[3]))*.254,W=N(a[4])*.254,H=N(a[5])*.254,Layer=int.Parse(a[6],Inv),Number=a[8],Drill=N(a[9])*2*.254,Angle=-N(a[11]),Slot=N(Field(a,13,"0"))*.254,Plated=Field(a,15,"Y")=="Y",Paste=N(Field(a,17,"0"))*.254,Mask=N(Field(a,18,"0"))*.254};
                    if(p.Shape!="RECT"&&p.Shape!="ELLIPSE"&&p.Shape!="OVAL"&&p.Shape!="POLYGON")throw new InvalidDataException("暂不支持 "+p.Shape+" 异形焊盘；已停止，未输出不完整封装");
                    if(p.Shape=="POLYGON"){
                        p.Polygon=PolygonPoints(a[10],p,ox,oy);
                        p.W=p.Polygon.Max(v=>v.X)-p.Polygon.Min(v=>v.X);
                        p.H=p.Polygon.Max(v=>v.Y)-p.Polygon.Min(v=>v.Y);
                        if(p.Slot>0)throw new InvalidDataException("异形铜皮组合槽孔尚未支持");
                    }
                    if(p.Shape=="ELLIPSE"&&Math.Abs(p.W-p.H)>.0005)throw new InvalidDataException("暂不支持椭圆铜焊盘");
                    if(p.Layer!=1&&p.Layer!=2&&p.Layer!=11)throw new InvalidDataException("不支持焊盘层 "+p.Layer);
                    if(p.W<=0||p.H<=0||p.Drill<0||p.Slot<0)throw new InvalidDataException("焊盘尺寸无效");
                    if(p.Layer!=11&&p.Drill>0)throw new InvalidDataException("贴片焊盘包含孔径，需人工核对");
                    if(p.Slot>0){
                        if(p.Layer!=11||p.Drill<=0||p.Slot<p.Drill)throw new InvalidDataException("槽孔长宽或图层无效");
                        var ends=Coords(Field(a,14,""),ox,oy);
                        if(ends.Count!=2)throw new InvalidDataException("槽孔缺少两个端点");
                        p.SlotAngle=Math.Atan2(ends[1].Y-ends[0].Y,ends[1].X-ends[0].X)*180/Math.PI;
                        double relative=((p.Angle-p.SlotAngle)%180+180)%180;
                        if(Math.Abs(relative-90)>.05&&Math.Min(relative,180-relative)>.05)throw new InvalidDataException("暂不支持槽孔与铜皮非正交的焊盘");
                    }
                    if(p.W+2*p.Mask<=0||p.H+2*p.Mask<=0)throw new InvalidDataException("阻焊开窗尺寸无效");
                    if(string.IsNullOrWhiteSpace(p.Number))throw new InvalidDataException("电气焊盘缺少引脚编号");
                    if(Regex.IsMatch(p.Number,@"[^A-Za-z0-9_+.-]"))throw new InvalidDataException("Allegro 不支持该引脚编号："+p.Number);
                    fp.Pads.Add(p);
                } else if(kind=="HOLE"){
                    fp.Pads.Add(new Pad {Shape="ELLIPSE",Number="",Layer=11,X=(N(a[1])-ox)*.254,Y=(oy-N(a[2]))*.254,W=N(a[3])*2*.254,H=N(a[3])*2*.254,Drill=N(a[3])*2*.254,Plated=false,Mask=0});
                } else if(kind=="TRACK"){
                    string layer=Layer(a[2]);if(layer!=null)fp.Drawings.Add(new Drawing {Layer=layer,Width=N(a[1])*.254,Points=Coords(a[4],ox,oy)});
                } else if(kind=="RECT"){
                    string layer=Layer(a[5]);if(layer!=null){double x=N(a[1]),y=N(a[2]),w=N(a[3]),h=N(a[4]);var pts=new List<Pt>{Point(x,y,ox,oy),Point(x+w,y,ox,oy),Point(x+w,y+h,ox,oy),Point(x,y+h,ox,oy),Point(x,y,ox,oy)};fp.Drawings.Add(new Drawing {Layer=layer,Width=N(Field(a,8,"0.6"))*.254,Filled=Field(a,9,"none")!="none",Points=pts});}
                } else if(kind=="CIRCLE"){
                    string layer=Layer(a[5]);if(layer!=null){double x=N(a[1]),y=N(a[2]),r=N(a[3]);var pts=new List<Pt>();int count=Math.Max(24,Math.Min(1024,(int)Math.Ceiling(2*Math.PI*r*.254/.02)));for(int i=0;i<=count;i++){double angle=i*2*Math.PI/count;pts.Add(Point(x+r*Math.Cos(angle),y+r*Math.Sin(angle),ox,oy));}fp.Drawings.Add(new Drawing {Layer=layer,Width=N(a[4])*.254,Points=pts});}
                } else if(kind=="ARC"){
                    string layer=Layer(a[2]);if(layer!=null)fp.Drawings.Add(new Drawing {Layer=layer,Width=N(a[1])*.254,Points=SvgPath.Parse(a[4],ox,oy)});
                } else if(kind=="SOLIDREGION"){
                    string layer=Layer(a[1]);if(layer!=null){if(Field(a,4,"solid")=="cutout"){if(a[1]=="99"||a[1]=="100"){fp.Warnings.Add("3D 外观层的挖空未导入；电气焊盘不受影响。");continue;}throw new InvalidDataException("暂不支持封装区域挖空");}var pts=SvgPath.Parse(a[3],ox,oy);if(pts.Count>0&&Pt.Dist(pts[0],pts[pts.Count-1])>.00001)pts.Add(pts[0]);fp.Drawings.Add(new Drawing {Layer=layer,Width=0,Filled=true,Points=pts});}
                } else if(kind=="TEXT"){
                    fp.Warnings.Add("原始文字未导入；已生成 Allegro 位号文字。");
                } else if(kind=="SVGNODE"||kind=="LIB"||kind=="DIMENSION"){
                    fp.Warnings.Add(kind+" 辅助数据未导入（不包含 STEP 模型）。");
                } else throw new InvalidDataException("不支持图形类型 "+kind);
            } catch(Exception ex){throw new InvalidDataException("解析 "+kind+" 失败："+ex.Message,ex);}
        }
        if(!fp.Pads.Any(p=>p.Number.Length>0))throw new InvalidDataException("封装中没有电气焊盘。");
        var duplicates=fp.Pads.Where(p=>p.Number.Length>0).GroupBy(p=>p.Number).Where(g=>g.Count()>1).Select(g=>g.Key).ToArray();
        var used=new HashSet<string>(fp.Pads.Select(p=>p.Number),StringComparer.OrdinalIgnoreCase);
        var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(var pad in fp.Pads){pad.SourceNumber=pad.Number;if(pad.Number.Length==0||seen.Add(pad.Number))continue;
            int suffix=2;string name;do{name=pad.SourceNumber+"_"+(suffix++).ToString(Inv);}while(used.Contains(name));
            used.Add(name);pad.Number=name;
            fp.Warnings.Add("引脚编号映射：源 "+pad.SourceNumber+" → Allegro "+pad.Number+"；必须在原理图/网表中添加此引脚并连接原编号同一网络，详见 pin-map.csv。");
        }
        int n=0;foreach(var p in fp.Pads){p.Name=fp.Code.ToLowerInvariant()+"_p"+(++n).ToString(Inv);fp.Extent=Math.Max(fp.Extent,Math.Max(Math.Abs(p.X),Math.Abs(p.Y))+Math.Max(p.W,p.H)+10);}
        foreach(var g in fp.Drawings)foreach(var p in g.Points)fp.Extent=Math.Max(fp.Extent,Math.Max(Math.Abs(p.X),Math.Abs(p.Y))+10);
        fp.Warnings=fp.Warnings.Distinct().ToList();return fp;
    }
    public static List<Pt> PolygonPoints(string text,Pad pad,double ox,double oy){
        var points=new List<Pt>();double angle=-pad.Angle*Math.PI/180,co=Math.Cos(angle),si=Math.Sin(angle);
        foreach(var world in Coords(text,ox,oy)){
            double x=world.X-pad.X,y=world.Y-pad.Y;var local=new Pt(co*x-si*y,si*x+co*y);
            if(points.Count==0||Pt.Dist(points.Last(),local)>1e-8)points.Add(local);
        }
        if(points.Count>1&&Pt.Dist(points[0],points.Last())<1e-8)points.RemoveAt(points.Count-1);
        if(points.Count<3||points.Count>5000)throw new InvalidDataException("异形焊盘轮廓点数量无效");
        double area=0;for(int i=0;i<points.Count;i++){var a=points[i];var b=points[(i+1)%points.Count];area+=a.X*b.Y-a.Y*b.X;}
        if(Math.Abs(area)<1e-10)throw new InvalidDataException("异形焊盘面积为零");
        for(int i=0;i<points.Count;i++)for(int j=i+1;j<points.Count;j++){
            if(j==i+1||(i==0&&j==points.Count-1))continue;
            if(SegmentsIntersect(points[i],points[(i+1)%points.Count],points[j],points[(j+1)%points.Count]))throw new InvalidDataException("异形焊盘轮廓自交");
        }
        points.Add(points[0]);return points;
    }
    static double Cross(Pt a,Pt b,Pt p){return (b.X-a.X)*(p.Y-a.Y)-(b.Y-a.Y)*(p.X-a.X);}
    static bool OnSegment(Pt a,Pt b,Pt p){return Math.Abs(Cross(a,b,p))<1e-10&&p.X>=Math.Min(a.X,b.X)-1e-10&&p.X<=Math.Max(a.X,b.X)+1e-10&&p.Y>=Math.Min(a.Y,b.Y)-1e-10&&p.Y<=Math.Max(a.Y,b.Y)+1e-10;}
    static bool SegmentsIntersect(Pt a,Pt b,Pt c,Pt d){
        double ac=Cross(a,b,c),ad=Cross(a,b,d),ca=Cross(c,d,a),cb=Cross(c,d,b);
        return ((ac>0&&ad<0)||(ac<0&&ad>0))&&((ca>0&&cb<0)||(ca<0&&cb>0))||OnSegment(a,b,c)||OnSegment(a,b,d)||OnSegment(c,d,a)||OnSegment(c,d,b);
    }
    public static IEnumerable<KeyValuePair<string,double>> PolygonSymbols(Pad pad){
        if(pad.Shape!="POLYGON")yield break;
        yield return new KeyValuePair<string,double>(pad.Name+"_cu",0);
        if(Math.Abs(pad.Mask)>1e-10)yield return new KeyValuePair<string,double>(pad.Name+"_sm",pad.Mask);
        if(pad.Layer!=11&&pad.W+2*pad.Paste>0&&pad.H+2*pad.Paste>0&&Math.Abs(pad.Paste)>1e-10)yield return new KeyValuePair<string,double>(pad.Name+"_pm",pad.Paste);
    }
    public static List<Pt> CleanRegion(List<Pt> source,double tolerance){
        var pts=new List<Pt>();
        foreach(var point in source){
            var q=new Pt(Math.Round(point.X/tolerance)*tolerance,Math.Round(point.Y/tolerance)*tolerance);
            if(pts.Count==0||Pt.Dist(pts.Last(),q)>tolerance*.1)pts.Add(q);
        }
        if(pts.Count>1&&Pt.Dist(pts[0],pts.Last())<tolerance*.1)pts.RemoveAt(pts.Count-1);
        bool changed=true;
        while(changed&&pts.Count>3){changed=false;for(int i=0;i<pts.Count;i++){
            Pt a=pts[(i+pts.Count-1)%pts.Count],b=pts[i],c=pts[(i+1)%pts.Count];
            double cross=(b.X-a.X)*(c.Y-a.Y)-(b.Y-a.Y)*(c.X-a.X);
            if(Math.Abs(cross)<tolerance*tolerance*.01){pts.RemoveAt(i);changed=true;break;}
        }}
        if(pts.Count<3)throw new InvalidDataException("区域小于 Allegro 的有效图形精度");
        pts.Add(pts[0]);return pts;
    }
    public static Pt Point(double x,double y,double ox,double oy){return new Pt((x-ox)*.254,(oy-y)*.254);}
    public static List<Pt> Coords(string text,double ox,double oy){var v=Regex.Split(text.Trim(),@"[\s,]+");if(v.Length%2!=0)throw new InvalidDataException("坐标对不完整");var pts=new List<Pt>();for(int i=0;i<v.Length;i+=2)pts.Add(Point(N(v[i]),N(v[i+1]),ox,oy));return pts;}
    public static string Layer(string n){switch(n){case "1":return "ETCH/TOP";case "2":return "ETCH/BOTTOM";case "3":return "PACKAGE GEOMETRY/SILKSCREEN_TOP";case "4":return "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM";case "5":return "PACKAGE GEOMETRY/PASTEMASK_TOP";case "6":return "PACKAGE GEOMETRY/PASTEMASK_BOTTOM";case "7":return "PACKAGE GEOMETRY/SOLDERMASK_TOP";case "8":return "PACKAGE GEOMETRY/SOLDERMASK_BOTTOM";case "10":case "12":case "15":case "99":case "100":return "PACKAGE GEOMETRY/ASSEMBLY_TOP";case "13":return "PACKAGE GEOMETRY/ASSEMBLY_TOP";case "14":return "PACKAGE GEOMETRY/ASSEMBLY_BOTTOM";case "19":case "101":return null;default:throw new InvalidDataException("暂不支持图形层 "+n);}}
    public static string Skill(Footprint fp){
        string template;using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("native.il"))using(var r=new StreamReader(s))template=r.ReadToEnd();
        var b=new StringBuilder(template);b.AppendLine("procedure(xkBuildFootprint() let((pad path orientation)");
        foreach(var pad in fp.Pads)foreach(var symbol in PolygonSymbols(pad)){
            b.Append("xkPolySymbol("+Q(symbol.Key)+" list(");foreach(var point in pad.Polygon)b.Append(F(point.X)+":"+F(point.Y)+" ");
            b.AppendLine(") "+F(symbol.Value)+")");
        }
        if(fp.Pads.Any(p=>p.Shape=="POLYGON")){
            b.AppendLine("xkMust(axlOpenDesign(?design "+Q(fp.Name+".dra")+" ?mode \"nf\" ?noMru t) \"new package drawing\")");
            b.AppendLine("axlSetVariable(\"psmpath\" \".\") axlSetVariable(\"padpath\" \".\")");
        }
        b.AppendLine("axlSetSymbolType(\"package\")\naxlDBChangeDesignUnits(\"millimeters\" 4)");
        b.AppendLine("xkMust(axlDBChangeDesignExtents(list("+F(-fp.Extent)+":"+F(-fp.Extent)+" "+F(fp.Extent)+":"+F(fp.Extent)+")) \"design extents\")");
        foreach(var p in fp.Pads)b.AppendLine("xkPad("+Q(p.Name)+" "+Q(p.Shape)+" "+p.Layer+" "+F(p.W)+" "+F(p.H)+" "+F(p.Drill)+" "+(p.Plated?"t":"nil")+" "+F(p.Mask)+" "+F(p.Paste)+" "+Q(p.Number)+" "+F(p.X)+":"+F(p.Y)+" "+F(p.Angle)+" "+F(p.Slot)+" "+F(p.SlotAngle)+")");
        foreach(var g in fp.Drawings){if(g.Filled)g.Points=CleanRegion(g.Points,.001);if(g.Points.Count<2)continue;b.Append("xkDraw(list(");foreach(var p in g.Points)b.Append(F(p.X)+":"+F(p.Y)+" ");b.AppendLine(") "+F(g.Width)+" "+Q(g.Layer)+" "+(g.Filled?"t":"nil")+")");}
        double top=fp.Pads.Max(p=>p.Y+Math.Max(p.W,p.H)/2)+1.2;
        b.AppendLine("orientation=make_axlTextOrientation(?textBlock 1 ?justify \"center\")");
        b.AppendLine("xkMust(axlDBCreateText(\"REFDES\" 0:"+F(top)+" orientation \"REF DES/SILKSCREEN_TOP\" nil) \"reference text\")");
        b.AppendLine("xkMust(axlDBCreateText(\"REFDES\" 0:0 orientation \"REF DES/ASSEMBLY_TOP\" nil) \"assembly text\")");
        b.AppendLine("xkMust(axlSaveDesign(?design "+Q(fp.Name+".dra")+" ?noMru t ?noConfirm t) \"save DRA\")");
        b.AppendLine("xkMust(axlCompileSymbol(?symbol "+Q(fp.Name)+" ?type \"package\") \"compile PSM\")\nt))\nxkRunFootprint()\n");return b.ToString();
    }
}
public static class SvgPath {
    static string[] tokens; // Parsing is serialized by the converter worker.
    public static List<Pt> Parse(string source,double ox,double oy){
        tokens=Regex.Matches(source,@"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?").Cast<Match>().Select(m=>m.Value).ToArray();
        if(Regex.Replace(source,@"[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?|[\s,]","").Length>0)throw new InvalidDataException("无效 SVG 路径");
        int i=0;char cmd=' ';var result=new List<Pt>();Pt pos=new Pt(0,0),start=pos;
        while(i<tokens.Length){if(char.IsLetter(tokens[i][0]))cmd=tokens[i++][0];char c=char.ToUpperInvariant(cmd);bool rel=char.IsLower(cmd);Pt prior=pos;
            if(c=='Z'){pos=start;result.Add(ConvertCore.Point(pos.X,pos.Y,ox,oy));cmd=' ';continue;}
            int count=c=='H'||c=='V'?1:c=='M'||c=='L'?2:c=='Q'?4:c=='C'?6:c=='A'?7:0;
            if(count==0||i+count>tokens.Length)throw new InvalidDataException("不支持或不完整的 SVG 路径指令 "+cmd);
            var v=new double[count];for(int j=0;j<count;j++)v[j]=ConvertCore.N(tokens[i++]);
            if(c=='M'||c=='L'){pos=new Pt(v[0]+(rel?pos.X:0),v[1]+(rel?pos.Y:0));if(c=='M'){if(result.Count>0)throw new InvalidDataException("暂不支持包含多个子路径的区域");start=pos;cmd=rel?'l':'L';}result.Add(ConvertCore.Point(pos.X,pos.Y,ox,oy));}
            else if(c=='H'||c=='V'){pos=c=='H'?new Pt(v[0]+(rel?pos.X:0),pos.Y):new Pt(pos.X,v[0]+(rel?pos.Y:0));result.Add(ConvertCore.Point(pos.X,pos.Y,ox,oy));}
            else if(c=='A'){
                var end=new Pt(v[5]+(rel?pos.X:0),v[6]+(rel?pos.Y:0));foreach(var p in Arc(pos,end,v[0],v[1],v[2],v[3]!=0,v[4]!=0))result.Add(ConvertCore.Point(p.X,p.Y,ox,oy));pos=end;
            } else {
                Pt a=new Pt(v[0]+(rel?prior.X:0),v[1]+(rel?prior.Y:0)),b=c=='C'?new Pt(v[2]+(rel?prior.X:0),v[3]+(rel?prior.Y:0)):a;
                pos=new Pt(v[count-2]+(rel?prior.X:0),v[count-1]+(rel?prior.Y:0));int steps=Math.Max(8,Math.Min(4096,(int)Math.Ceiling((Pt.Dist(prior,a)+Pt.Dist(a,b)+Pt.Dist(b,pos))*.254/.01)));
                for(int j=1;j<=steps;j++){double t=(double)j/steps,u=1-t;var p=c=='C'?new Pt(u*u*u*prior.X+3*u*u*t*a.X+3*u*t*t*b.X+t*t*t*pos.X,u*u*u*prior.Y+3*u*u*t*a.Y+3*u*t*t*b.Y+t*t*t*pos.Y):new Pt(u*u*prior.X+2*u*t*a.X+t*t*pos.X,u*u*prior.Y+2*u*t*a.Y+t*t*pos.Y);result.Add(ConvertCore.Point(p.X,p.Y,ox,oy));}
            }
        }return result;
    }
    static IEnumerable<Pt> Arc(Pt start,Pt end,double rx,double ry,double deg,bool large,bool sweep){
        rx=Math.Abs(rx);ry=Math.Abs(ry);if(rx==0||ry==0||Pt.Dist(start,end)<1e-10){yield return end;yield break;}
        double phi=deg*Math.PI/180,co=Math.Cos(phi),si=Math.Sin(phi),dx=(start.X-end.X)/2,dy=(start.Y-end.Y)/2,x=co*dx+si*dy,y=-si*dx+co*dy;
        double scale=x*x/(rx*rx)+y*y/(ry*ry);if(scale>1){rx*=Math.Sqrt(scale);ry*=Math.Sqrt(scale);}
        double factor=(large==sweep?-1:1)*Math.Sqrt(Math.Max(0,(rx*rx*ry*ry-rx*rx*y*y-ry*ry*x*x)/(rx*rx*y*y+ry*ry*x*x)));
        double cx=factor*rx*y/ry,cy=-factor*ry*x/rx,centerX=co*cx-si*cy+(start.X+end.X)/2,centerY=si*cx+co*cy+(start.Y+end.Y)/2;
        double a=Math.Atan2((y-cy)/ry,(x-cx)/rx),b=Math.Atan2((-y-cy)/ry,(-x-cx)/rx),delta=b-a;
        if(!sweep&&delta>0)delta-=2*Math.PI;if(sweep&&delta<0)delta+=2*Math.PI;
        double maxRadius=Math.Max(rx,ry)*.254;double step=2*Math.Acos(Math.Max(-1,1-.005/Math.Max(.005,maxRadius)));int count=Math.Max(2,Math.Min(8192,(int)Math.Ceiling(Math.Abs(delta)/Math.Min(Math.PI/18,step))));
        for(int j=1;j<=count;j++){double angle=a+delta*j/count;yield return j==count?end:new Pt(centerX+co*rx*Math.Cos(angle)-si*ry*Math.Sin(angle),centerY+si*rx*Math.Cos(angle)+co*ry*Math.Sin(angle));}
    }
}
public static class Cadence {
    public static string Find(){
        var roots=new List<string>();foreach(string key in new[]{"CDSROOT","CDS_INST_DIR"}){string value=Environment.GetEnvironmentVariable(key);if(!string.IsNullOrEmpty(value))roots.Add(value);}
        foreach(string drive in new[]{"C:\\","D:\\","E:\\"})foreach(string parent in new[]{"Cadence","orcad\\Cadence","Cadence\\Cadence"}){string dir=Path.Combine(drive,parent);if(Directory.Exists(dir))roots.AddRange(Directory.GetDirectories(dir,"SPB*"));}
        foreach(string root in roots.OrderByDescending(s=>s,StringComparer.OrdinalIgnoreCase)){string path=Path.Combine(root,"tools","bin","allegro.exe");if(File.Exists(path))return path;}
        return "";
    }
    public static string Run(Footprint fp,string output,string exe,Action<string> log,Func<bool> cancelled,ExportOptions options=null){
        if(options==null)options=new ExportOptions();
        ExtraFormats.Validate(fp,options);
        if(!File.Exists(exe)||!Path.GetFileName(exe).Equals("allegro.exe",StringComparison.OrdinalIgnoreCase))throw new FileNotFoundException("请选择已安装的 Allegro PCB Editor（allegro.exe）。");
        Directory.CreateDirectory(output);string dest=Path.Combine(output,fp.Name);
        if(Directory.Exists(dest))throw new IOException("输出已存在："+dest+"。请选择其他目录，已有封装不会被覆盖。");
        string job=Path.Combine(Path.GetTempPath(),"xk-lceda-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(job);
        File.WriteAllText(Path.Combine(job,"native.il"),ConvertCore.Skill(fp),Encoding.GetEncoding(936));
        File.WriteAllText(Path.Combine(job,"convert.scr"),"set noconfirm\nskill load(\"native.il\")\nexit\n",Encoding.ASCII);
        log("正在启动 Allegro 生成 "+fp.Pads.Count+" 个焊盘……");
        var start=new ProcessStartInfo(exe,"-s convert.scr "+fp.Name+".dra"){WorkingDirectory=job,UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden};
        // A private pcbenv avoids running user auto-load scripts in the conversion process.
        string env=Path.Combine(job,"pcbenv");Directory.CreateDirectory(env);
        // Preserve the selected product/license so Allegro does not show Product Choices.
        foreach(string candidate in EnvCandidates())if(File.Exists(candidate)){foreach(string line in File.ReadAllLines(candidate))if(line.StartsWith("base_license=",StringComparison.OrdinalIgnoreCase)){File.WriteAllText(Path.Combine(env,"allegro.ini"),"[allegro]\n"+line+"\n",Encoding.ASCII);break;}if(File.Exists(Path.Combine(env,"allegro.ini")))break;}
        start.EnvironmentVariables["ALLEGRO_PCBENV"]=env;
        var timer=Stopwatch.StartNew();
        using(var p=Process.Start(start)){
            while(!p.WaitForExit(200)){
                if(cancelled()||timer.Elapsed.TotalSeconds>180){try{p.Kill();p.WaitForExit(5000);}catch(InvalidOperationException){}if(cancelled())throw new OperationCanceledException("已取消；诊断目录："+job);throw new TimeoutException("Allegro 生成超时，请检查许可证和启动窗口。诊断目录："+job);}
            }
        }
        string status=Path.Combine(job,"conversion.status");string result=File.Exists(status)?File.ReadAllText(status):"Allegro 未返回生成结果，请检查许可证或启动提示。";
        var required=new List<string>{fp.Name+".dra",fp.Name+".psm"};required.AddRange(fp.Pads.Select(p=>p.Name+".pad"));
        foreach(var pad in fp.Pads)foreach(var symbol in ConvertCore.PolygonSymbols(pad)){required.Add(symbol.Key+".ssm");required.Add(symbol.Key+".dra");}
        if(!result.Trim().StartsWith("OK",StringComparison.Ordinal)||required.Any(n=>!File.Exists(Path.Combine(job,n))||new FileInfo(Path.Combine(job,n)).Length<100))throw new IOException("生成失败："+result+"\n"+NativeError(job)+"\n诊断目录："+job);
        if(cancelled())throw new OperationCanceledException("已取消；诊断目录："+job);
        string stage=Path.Combine(output,".xk-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(stage);
        foreach(string name in required)File.Copy(Path.Combine(job,name),Path.Combine(stage,name));
        try{ExtraFormats.Write(fp,stage,options,log,cancelled);}
        catch(Exception ex){throw new IOException("附加格式未完成；未发布本次输出。诊断目录："+stage+"\n"+ex.Message,ex);}
        var mapping=new StringBuilder("SourcePin,AllegroPin,X_mm,Y_mm\r\n");
        foreach(var pad in fp.Pads)mapping.AppendLine(pad.SourceNumber+","+pad.Number+","+ConvertCore.F(pad.X)+","+ConvertCore.F(pad.Y));
        File.WriteAllText(Path.Combine(stage,"pin-map.csv"),mapping.ToString(),new UTF8Encoding(true));
        File.Copy(Path.Combine(job,"native.il"),Path.Combine(stage,"rebuild.il"));
        File.WriteAllText(Path.Combine(stage,"rebuild.scr"),"set noconfirm\nskill load(\"rebuild.il\")\nexit\n",Encoding.ASCII);
        foreach(string logFile in Directory.GetFiles(job,"*.log").Concat(Directory.GetFiles(job,"*.jrl")))File.Copy(logFile,Path.Combine(stage,Path.GetFileName(logFile)),true);
        File.WriteAllText(Path.Combine(stage,"manifest.json"),ConvertCore.Json.Serialize(new {code=fp.Code,title=fp.Title,symbol=fp.Name,units="millimeters",formats=options.Formats,adSymbol=options.Altium?fp.Name:null,padsSymbol=options.Pads?PadsLibrary.Name(fp):null,pins=fp.Pads.Select(p=>new {number=p.Number,sourceNumber=p.SourceNumber,shape=p.Shape,polygon=p.Polygon.Select(v=>new {x=v.X,y=v.Y}).ToArray(),x=p.X,y=p.Y,width=p.W,height=p.H,rotation=p.Angle,drill=p.Drill,slotLength=p.Slot,slotRotation=p.SlotAngle,layer=p.Layer,padstack=p.Name}).ToArray(),warnings=fp.Warnings.ToArray(),generatedAt=DateTimeOffset.Now.ToString("o"),cadence=FileVersionInfo.GetVersionInfo(exe).FileVersion}),new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(stage,"使用说明.txt"),"立创编号："+fp.Code+"\r\n源封装："+fp.Title+"\r\nPCB Footprint："+fp.Name+"\r\n\r\n将本文件夹加入 Allegro 的 psmpath 和 padpath。Capture 元件的 PCB Footprint 属性填写上面的名称（不带扩展名）。\r\n.dra 为可编辑封装；.psm 为可放置封装；.pad 为配套焊盘。需保留整组文件。\r\n尺寸单位 mm；原点沿用立创封装原点；Y 轴和旋转方向已转换。\r\n槽孔与同号多焊盘保留；异形焊盘使用配套 .ssm 轮廓，须与 .pad、.psm 一起保留并加入 psmpath。\r\n首次使用前请结合规格书核对焊盘尺寸、编号及装配方向。\r\n"+string.Join("\r\n",fp.Warnings.ToArray())+ExtraFormats.Instructions(options),new UTF8Encoding(false));
        if(cancelled())throw new OperationCanceledException("已取消；未发布本次输出。诊断目录："+stage);
        Directory.Move(stage,dest);log("已生成："+dest);return dest;
    }
    static string NativeError(string job){
        var errors=new List<string>();
        foreach(string path in Directory.GetFiles(job,"*.jrl"))foreach(string line in File.ReadAllLines(path,Encoding.Default))
            if(line.Contains("ERROR(")||line.Contains("*Error*"))errors.Add(line.Trim());
        return string.Join("\n",errors.Distinct().Take(8).ToArray());
    }
    static IEnumerable<string> EnvCandidates(){
        string value=Environment.GetEnvironmentVariable("ALLEGRO_PCBENV");if(!string.IsNullOrEmpty(value))yield return Path.Combine(value,"allegro.ini");
        foreach(string root in new[]{Environment.GetEnvironmentVariable("HOME"),Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),Environment.CurrentDirectory})if(!string.IsNullOrEmpty(root))yield return Path.Combine(root,"pcbenv","allegro.ini");
    }
}
public static class Fetcher {
    public static string Download(string code,string cache,Action<string> log){
        string file=Path.Combine(cache,code+".json");if(File.Exists(file)){string text=File.ReadAllText(file,Encoding.UTF8);try{ConvertCore.Parse(text,code);log("使用缓存："+code);return text;}catch(InvalidDataException){log("缓存不可用，重新下载……");}}
        ServicePointManager.SecurityProtocol=(SecurityProtocolType)3072;
        string url="https://easyeda.com/api/products/"+code+"/components?version=6.4.19.5";var req=(HttpWebRequest)WebRequest.Create(url);req.UserAgent="Mozilla/5.0 XiaokaiToolbox/1.0";req.Accept="application/json";req.Referer="https://easyeda.com/";req.Timeout=30000;req.ReadWriteTimeout=30000;req.AutomaticDecompression=DecompressionMethods.GZip|DecompressionMethods.Deflate;
        log("下载立创元件："+code);string raw;using(var response=req.GetResponse())using(var stream=response.GetResponseStream())using(var reader=new StreamReader(stream,Encoding.UTF8))raw=reader.ReadToEnd();
        ConvertCore.Parse(raw,code);Directory.CreateDirectory(cache);string temp=file+"."+Guid.NewGuid().ToString("N")+".tmp";File.WriteAllText(temp,raw,new UTF8Encoding(false));if(File.Exists(file))File.Delete(file);File.Move(temp,file);return raw;
    }
}
public sealed class MainForm:Form {
    TextBox code=new TextBox(),folder=new TextBox(),exe=new TextBox(),log=new TextBox();Button run=new Button(),cancel=new Button(),open=new Button();CheckBox openDra=new CheckBox(),generateAd=new CheckBox(),generatePads=new CheckBox();BackgroundWorker worker=new BackgroundWorker();string last="";string settings=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"XiaokaiToolbox","lceda2allegro-settings.json");
    public MainForm(){
        Text="立创 PCB 封装一键转 Allegro · 小开工具箱";Font=new Font("Microsoft YaHei UI",10);ClientSize=new Size(800,560);MinimumSize=new Size(780,540);StartPosition=FormStartPosition.CenterScreen;BackColor=Color.FromArgb(245,247,250);
        try{Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);}catch(ArgumentException){}
        var layout=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(22),ColumnCount=3,RowCount=9};layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,100));layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,100));Controls.Add(layout);
        var title=new Label {Text="立创 PCB 封装 → Allegro",Font=new Font(Font.FontFamily,18,FontStyle.Bold),AutoSize=true,Margin=new Padding(0,0,0,12)};layout.Controls.Add(title,0,0);layout.SetColumnSpan(title,3);
        var info=new Label {Text="输入立创编号，自动生成 .dra、.psm 和配套 .pad 文件。",AutoSize=true,Margin=new Padding(0,0,0,16)};layout.Controls.Add(info,0,1);layout.SetColumnSpan(info,3);
        AddRow(layout,"立创编号",code,2,"粘贴编号",delegate{try{string s=Clipboard.GetText();var m=Regex.Match(s,@"\bC\d+\b",RegexOptions.IgnoreCase);if(m.Success)code.Text=m.Value.ToUpperInvariant();}catch(System.Runtime.InteropServices.ExternalException){}});code.Text="";
        AddRow(layout,"输出目录",folder,3,"选择目录",delegate{using(var d=new FolderBrowserDialog()){d.SelectedPath=folder.Text;if(d.ShowDialog(this)==DialogResult.OK)folder.Text=d.SelectedPath;}});
        folder.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"立创Allegro封装");
        AddRow(layout,"Allegro 程序",exe,4,"选择程序",delegate{using(var d=new OpenFileDialog {Filter="Allegro PCB Editor|allegro.exe",FileName="allegro.exe"})if(d.ShowDialog(this)==DialogResult.OK)exe.Text=d.FileName;});exe.Text=Cadence.Find();
        generateAd.Text="同时生成 AD 封装";generateAd.AutoSize=true;generateAd.Checked=false;
        generatePads.Text="同时生成 PADS 封装";generatePads.AutoSize=true;generatePads.Checked=false;
        var formats=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,WrapContents=true,Margin=new Padding(0,5,0,5)};
        formats.Controls.AddRange(new Control[]{generateAd,generatePads});
        layout.Controls.Add(new Label {Text="附加输出",AutoSize=true,Anchor=AnchorStyles.Left},0,5);layout.Controls.Add(formats,1,5);layout.SetColumnSpan(formats,2);
        openDra.Text="完成后在 Allegro 中打开封装";openDra.AutoSize=true;formats.Controls.Add(openDra);
        var actions=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Fill,Margin=new Padding(0,12,0,8)};run.Text="一键转换";run.Size=new Size(135,36);run.BackColor=Color.FromArgb(168,35,42);run.ForeColor=Color.White;run.FlatStyle=FlatStyle.Flat;cancel.Text="取消";cancel.Size=new Size(85,36);cancel.Enabled=false;open.Text="打开输出目录";open.Size=new Size(135,36);open.Enabled=false;actions.Controls.AddRange(new Control[]{run,cancel,open});layout.Controls.Add(actions,0,6);layout.SetColumnSpan(actions,3);
        log.Multiline=true;log.ReadOnly=true;log.ScrollBars=ScrollBars.Vertical;log.Dock=DockStyle.Fill;log.BackColor=Color.White;layout.Controls.Add(log,0,7);layout.SetColumnSpan(log,3);layout.RowStyles.Clear();for(int i=0;i<7;i++)layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,30));
        var foot=new Label {Text="需要本机 Allegro 及可用许可证 · 已有输出不会被覆盖",Dock=DockStyle.Fill,ForeColor=Color.DimGray,TextAlign=ContentAlignment.MiddleLeft};layout.Controls.Add(foot,0,8);layout.SetColumnSpan(foot,3);
        worker.WorkerSupportsCancellation=true;worker.DoWork+=Work;worker.RunWorkerCompleted+=Done;
        run.Click+=delegate{Start();};cancel.Click+=delegate{worker.CancelAsync();cancel.Enabled=false;WriteLog("正在取消……");};open.Click+=delegate{if(Directory.Exists(last))Process.Start("explorer.exe","\""+last+"\"");};AcceptButton=run;
        FormClosing+=delegate(object sender,FormClosingEventArgs e){if(worker.IsBusy){worker.CancelAsync();e.Cancel=true;WriteLog("正在取消转换，完成后可关闭窗口。");}};
        try{if(File.Exists(settings)){var d=ConvertCore.Obj(ConvertCore.Json.DeserializeObject(File.ReadAllText(settings)));folder.Text=ConvertCore.Text(d,"output",folder.Text);exe.Text=ConvertCore.Text(d,"allegro",exe.Text);}}catch(Exception){WriteLog("配置读取失败，使用默认设置。");}
        WriteLog("输入立创编号，例如 C25804、C2040。每个封装输出至独立文件夹。");
    }
    void AddRow(TableLayoutPanel p,string label,TextBox value,int row,string action,EventHandler click){p.Controls.Add(new Label {Text=label,AutoSize=true,Anchor=AnchorStyles.Left},0,row);value.Dock=DockStyle.Fill;value.Margin=new Padding(0,5,8,5);p.Controls.Add(value,1,row);var b=new Button {Text=action,Dock=DockStyle.Fill,AutoSize=true};b.Click+=click;p.Controls.Add(b,2,row);}
    void WriteLog(string message){if(InvokeRequired){BeginInvoke(new Action<string>(WriteLog),message);return;}log.AppendText(message+Environment.NewLine);}
    void Start(){try{string id=ConvertCore.Normalize(code.Text);string path=Path.GetFullPath(folder.Text.Trim());if(!File.Exists(exe.Text.Trim()))throw new IOException("未找到 Allegro，请选择 allegro.exe。");Directory.CreateDirectory(Path.GetDirectoryName(settings));File.WriteAllText(settings,ConvertCore.Json.Serialize(new {output=path,allegro=exe.Text.Trim()}));run.Enabled=false;cancel.Enabled=true;open.Enabled=false;generateAd.Enabled=false;generatePads.Enabled=false;code.Enabled=false;folder.Enabled=false;exe.Enabled=false;worker.RunWorkerAsync(new object[]{id,path,exe.Text.Trim(),new ExportOptions {Altium=generateAd.Checked,Pads=generatePads.Checked}});}catch(Exception ex){MessageBox.Show(this,ex.Message,"无法开始转换",MessageBoxButtons.OK,MessageBoxIcon.Information);}}
    void Work(object sender,DoWorkEventArgs e){var args=(object[])e.Argument;string cache=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"XiaokaiToolbox","lceda2allegro-cache");string raw=Fetcher.Download((string)args[0],cache,WriteLog);var fp=ConvertCore.Parse(raw,(string)args[0]);foreach(string warning in fp.Warnings)WriteLog("提示："+warning);if(worker.CancellationPending){e.Cancel=true;return;}e.Result=Cadence.Run(fp,(string)args[1],(string)args[2],WriteLog,()=>worker.CancellationPending,(ExportOptions)args[3]);
        File.WriteAllText(Path.Combine((string)e.Result,"source.json"),raw,new UTF8Encoding(false));}
    void Done(object sender,RunWorkerCompletedEventArgs e){run.Enabled=true;cancel.Enabled=false;generateAd.Enabled=true;generatePads.Enabled=true;code.Enabled=true;folder.Enabled=true;exe.Enabled=true;if(e.Cancelled||e.Error is OperationCanceledException){WriteLog("转换已取消。");return;}if(e.Error!=null){WriteLog(e.Error.Message);return;}last=(string)e.Result;open.Enabled=true;WriteLog("转换完成。Capture 的 PCB Footprint 属性填写："+Path.GetFileName(last));if(openDra.Checked)Process.Start(exe.Text,"\""+Path.Combine(last,Path.GetFileName(last)+".dra")+"\"");}
}
public static class Program {
    [STAThread]public static int Main(string[] args){
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(),new UTF8Encoding(false)){AutoFlush=true});Console.SetError(new StreamWriter(Console.OpenStandardError(),new UTF8Encoding(false)){AutoFlush=true});
        if(args.Length>0){try{
            if(args[0]=="--self-test"){SelfTest.Run();return 0;}
            if(args[0]=="--preview"&&args.Length==2){Application.EnableVisualStyles();using(var form=new MainForm()){form.Opacity=0;form.ShowInTaskbar=false;form.Show();Application.DoEvents();form.PerformLayout();using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));image.Save(args[1]);}}return 0;}
            if(args[0]=="--download"&&args.Length==3){string id=ConvertCore.Normalize(args[1]);string raw=Fetcher.Download(id,Path.GetFullPath(args[2]),Console.WriteLine);Console.WriteLine("Downloaded "+id);return 0;}
            if((args[0]=="--convert"||args[0]=="--export-only")&&args.Length>=4){string raw=File.ReadAllText(args[1],Encoding.UTF8);var fp=ConvertCore.Parse(raw,args[2]);string output=Path.GetFullPath(args[3]);Directory.CreateDirectory(output);string exe=Cadence.Find();var options=new ExportOptions();bool exeSet=false;for(int i=4;i<args.Length;i++){if(args[i]=="--ad")options.Altium=true;else if(args[i]=="--pads")options.Pads=true;else if(!args[i].StartsWith("--")&&!exeSet){exe=args[i];exeSet=true;}else throw new ArgumentException("Unknown option: "+args[i]);}
            string dest;if(args[0]=="--export-only"){dest=Path.Combine(output,fp.Name);if(Directory.Exists(dest))throw new IOException("Output already exists: "+dest);Directory.CreateDirectory(dest);ExtraFormats.Write(fp,dest,options,Console.WriteLine,()=>false);}else {foreach(string warning in fp.Warnings)Console.WriteLine("提示："+warning);dest=Cadence.Run(fp,output,exe,Console.WriteLine,()=>false,options);}File.Copy(args[1],Path.Combine(dest,"source.json"));return 0;}
            throw new ArgumentException("Usage: --convert source.json C25804 output [allegro.exe] [--ad] [--pads] | --self-test");
        }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}}
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new MainForm());return 0;
    }
}
}
