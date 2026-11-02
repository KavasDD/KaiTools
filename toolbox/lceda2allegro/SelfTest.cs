// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
namespace Xiaokai.LcedaAllegro {
public static class SelfTest {
 static void Check(bool condition,string message){if(!condition)throw new Exception("FAIL: "+message);}
 static void Reject(Action action,string message){try{action();}catch(InvalidDataException){return;}throw new Exception("FAIL: accepted "+message);}
 static string Fixture(string[] shapes){return ConvertCore.Json.Serialize(new {packageDetail=new {title="Test_Package",dataStr=new {head=new {x=4000,y=3000},shape=shapes}}});}
 public static void Run(){
  string pad="PAD~RECT~4010~2990~4~2~1~~1~0~~30~id~0~~Y~0~0~0.2";
  var f=ConvertCore.Parse(Fixture(new[]{pad}),"C123");var p=f.Pads[0];
  Check(Math.Abs(p.X-2.54)<1e-9&&Math.Abs(p.Y-2.54)<1e-9,"origin, units and Y axis");
  Check(p.Angle==-30&&Math.Abs(p.W-1.016)<1e-9&&Math.Abs(p.Mask-.0508)<1e-9,"rotation and pad dimensions");
  var through=ConvertCore.Parse(Fixture(new[]{"PAD~ELLIPSE~4000~3000~8~8~11~~A1~2~~0~id~0~~Y~0~0~0.2"}),"C123").Pads[0];
  Check(Math.Abs(through.Drill-1.016)<1e-9&&through.Plated,"drill radius to diameter");
  var hole=ConvertCore.Parse(Fixture(new[]{pad,"HOLE~4010~3000~2~id~0"}),"C123").Pads[1];Check(!hole.Plated&&hole.Number==""&&Math.Abs(hole.Drill-1.016)<1e-9,"mechanical hole");
  var repeated=ConvertCore.Parse(Fixture(new[]{pad,pad}),"C123");Check(repeated.Pads.Count==2&&repeated.Pads[1].Number=="1_2"&&repeated.Pads[1].SourceNumber=="1","duplicate pins retain explicit unique mapping");
  Reject(()=>ConvertCore.Parse(Fixture(new[]{pad.Replace("RECT","POLYGON")}),"C123"),"polygon without outline");
  string custom="PAD~POLYGON~4000~3000~4~4~1~~1~0~3998 2998 4002 2998 4002 3000 4000 3000 4000 3002 3998 3002~90~id~0~~Y~0~-0.1~0.2";
  var polygon=ConvertCore.Parse(Fixture(new[]{custom}),"C123");var cp=polygon.Pads[0];
  Check(cp.Polygon.Count==7&&Math.Abs(cp.Polygon[0].X+.508)<1e-9&&Math.Abs(cp.Polygon[0].Y+.508)<1e-9,"polygon source rotation removed for pad-local coordinates");
  Check(Math.Abs(cp.W-1.016)<1e-9&&Math.Abs(cp.H-1.016)<1e-9,"polygon dimensions derive from the actual outline");
  Check(ConvertCore.PolygonSymbols(cp).Select(x=>x.Key).SequenceEqual(new[]{"c123_p1_cu","c123_p1_sm","c123_p1_pm"}),"copper and separate mask shape dependencies");
  Check(ConvertCore.PolygonSymbols(cp).Last().Value<0,"negative paste expansion preserved");
  string customNative=ConvertCore.Skill(polygon);
  Check(customNative.Contains("xkPolySymbol(\"c123_p1_cu\"")&&customNative.Contains("compile SSM")&&customNative.Contains("psmpath"),"native custom pad pipeline");
  Reject(()=>ConvertCore.Parse(Fixture(new[]{custom.Replace("3998 2998 4002 2998 4002 3000 4000 3000 4000 3002 3998 3002","3998 2998 4002 3002 3998 3002 4002 2998")}),"C123"),"self-intersecting polygon");
  Reject(()=>ExtraFormats.Validate(polygon,new ExportOptions{Altium=true}),"polygon AD export must not become a rectangle");
  Reject(()=>ExtraFormats.Validate(polygon,new ExportOptions{Pads=true}),"polygon PADS export must not become a rectangle");
  ExtraFormats.Validate(polygon,new ExportOptions());
  Reject(()=>ConvertCore.Parse(Fixture(new[]{pad.Replace("~0~~Y","~5~~Y")}),"C123"),"slot drill");
  Reject(()=>ConvertCore.Parse("{\"success\":false,\"message\":\"missing\"}","C123"),"API error");
  var q=SvgPath.Parse("M 0,0 h 10 v 10 l -10,0 z",0,0);Check(q.Count==5&&Math.Abs(q[2].X-2.54)<1e-9&&Math.Abs(q[2].Y+2.54)<1e-9,"relative path");
  var arc=SvgPath.Parse("M 10 0 A 10 10 0 0 1 0 10",0,0);Check(arc.Count>3&&Math.Abs(arc.Last().Y+2.54)<1e-9,"arc endpoint");Check(arc.All(v=>Math.Abs(Math.Sqrt(v.X*v.X+v.Y*v.Y)-2.54)<.00001),"arc geometry");
  Reject(()=>SvgPath.Parse("M 0 0 L 1 1 M 2 2 L 3 3",0,0),"disjoint subpaths");
  var region=ConvertCore.CleanRegion(new List<Pt>{new Pt(0,0),new Pt(1,0),new Pt(1,1),new Pt(.0004,1),new Pt(.0004,.9998),new Pt(.0001,.9998),new Pt(0,0)},.001);Check(region.Count==5,"submicron region spikes removed");
  var slot=ConvertCore.Parse(Fixture(new[]{"PAD~OVAL~4000~3000~8~12~11~~13~2~~0~id~8~4000 2998 4000 3002~Y~0~0~0.2"}),"C123").Pads[0];Check(Math.Abs(slot.Slot-2.032)<1e-9&&Math.Abs(Math.Abs(slot.SlotAngle)-90)<1e-9,"slot length and orientation");
  string native=ConvertCore.Skill(f);Check(native.Contains("-100:-100")&&native.Contains("compile PSM")&&native.Contains("REFDES"),"native symbol generation");
  string wrapped="{\"success\":true,\"result\":"+Fixture(new[]{pad})+"}";Check(ConvertCore.Parse(wrapped,"C123").Pads.Count==1,"wrapped cache");
  FormatChecks(f);
  Console.WriteLine("PASS: units, origin, rotation, drills, mechanical holes, mask margin, invalid data, duplicate pins, paths, arcs and SKILL output");
 }
 static void FormatChecks(Footprint fp){
  Check(!new ExportOptions().Altium&&!new ExportOptions().Pads,"optional formats default off");
  using(var form=new MainForm()){
   var fields=typeof(MainForm).GetFields(BindingFlags.Instance|BindingFlags.NonPublic);
   foreach(string name in new[]{"generateAd","generatePads"}){var check=(CheckBox)fields.Single(x=>x.Name==name).GetValue(form);Check(!check.Checked,"UI starts unchecked: "+name);check.Checked=true;}
  }
  using(var form=new MainForm()){
   foreach(string name in new[]{"generateAd","generatePads"})Check(!((CheckBox)typeof(MainForm).GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).GetValue(form)).Checked,"new window resets "+name);
  }
  fp.Drawings.Add(new Drawing {Layer="PACKAGE GEOMETRY/PASTEMASK_TOP",Filled=true,Points=new List<Pt>{new Pt(0,0),new Pt(1,0),new Pt(1,1),new Pt(0,0)}});
  string root=Path.Combine(Path.GetTempPath(),"xk-format-check-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  try{
   for(int mask=0;mask<4;mask++){
    var opts=new ExportOptions {Altium=(mask&1)!=0,Pads=(mask&2)!=0};string dir=Path.Combine(root,mask.ToString());Directory.CreateDirectory(dir);
    ExtraFormats.Write(fp,dir,opts,message=>{},()=>false);
    Check(Directory.Exists(Path.Combine(dir,"AD"))==opts.Altium,"AD output selection "+mask);
    Check(Directory.Exists(Path.Combine(dir,"PADS"))==opts.Pads,"PADS output selection "+mask);
    Check(opts.Formats.Length==1+(opts.Altium?1:0)+(opts.Pads?1:0),"manifest selection "+mask);
    if(opts.Altium){
     string file=Path.Combine(dir,"AD",fp.Name+".PcbLib");byte[] header=CompoundStorage.Read(file,"FileHeader");Check(System.Text.Encoding.ASCII.GetString(header).Contains("PCB 6.0 Binary Library File"),"native binary PcbLib header");
     Check(System.Text.Encoding.ASCII.GetString(CompoundStorage.Read(file,"Library/Data")).Contains("|VERSION=3.00|"),"AD17 library parameters version");
     byte[] data=CompoundStorage.Read(file,AltiumLibrary.Section(fp.Name)+"/Data");using(var reader=new BinaryReader(new MemoryStream(data))){int length=reader.ReadInt32();reader.ReadBytes(length);Check(reader.ReadByte()==2,"PcbLib pad object");for(int i=0;i<4;i++){length=reader.ReadInt32();reader.ReadBytes(length);}length=reader.ReadInt32();byte[] pad=reader.ReadBytes(length);Check(pad.Length==202,"AD pad record length");Check(Math.Abs(BitConverter.ToInt32(pad,13)/ (10000.0/.0254)-fp.Pads[0].X)<.000002,"AD coordinate roundtrip");Check(BitConverter.ToDouble(pad,52)==330,"AD rotation roundtrip");Check(pad[101]==2&&pad[102]==2,"manual paste/mask overrides");}
    }
    if(opts.Pads){string d=File.ReadAllText(Path.Combine(dir,"PADS",fp.Name+".d"));Check(d.StartsWith("*PADS-LIBRARY-PCB-DECALS-V9*"),"PADS library signature");Check(d.Contains("M 0 0 0 1 1 0 1 1 0"),"PADS decal header counts");Check(d.Contains("PAD 1 5 P 0"),"PADS native pad header");Check(d.Contains("RF 0 150 1.016 0"),"PADS rotation and finger dimensions");Check(d.Contains("-1 0 R")&&d.Contains("0 0 R"),"PADS inner and opposite copper layers");}
   }
   Footprint a=new Footprint {Name=new string('X',60)},b=new Footprint {Name=new string('X',59)+"Y"};Check(PadsLibrary.Name(a).Length==40&&PadsLibrary.Name(a)!=PadsLibrary.Name(b),"PADS name limit without collisions");
   bool cancelled=false;try{ExtraFormats.Write(fp,Path.Combine(root,"cancel"),new ExportOptions {Altium=true,Pads=true},message=>{},()=>true);}catch(OperationCanceledException){cancelled=true;}Check(cancelled&&!Directory.Exists(Path.Combine(root,"cancel")),"cancel before extra formats");
  }finally{string absolute=Path.GetFullPath(root);if(Path.GetDirectoryName(absolute).Equals(Path.GetTempPath().TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase)&&Path.GetFileName(absolute).StartsWith("xk-format-check-",StringComparison.Ordinal))Directory.Delete(absolute,true);}
  Console.WriteLine("PASS: four format combinations, unchecked UI defaults on every new window, native PcbLib binary geometry, PADS header/rotation/layers, name limits and cancellation");
 }

}
}
