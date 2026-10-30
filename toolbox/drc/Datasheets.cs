// PDF sources and page evidence. Runs in the helper, never inside Capture.
using System;
using System.IO;
using System.Net;
using System.Text;
using System.Linq;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Reflection;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Drawing;
using UglyToad.PdfPig;

internal static class Datasheets
{
    static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 8 * 1024 * 1024 };
    static readonly Encoding Utf8 = new UTF8Encoding(false);
    internal const string ReviewedModel = "SN74AHCT125PWR";
    internal const string ReviewedUrl = "https://www.ti.com/lit/ds/symlink/sn74ahct125.pdf";
    internal const string ReviewedHash = "66da72e586dbca7a1548164adf28e238484c5c1ad250fcb28ec972e4732c6fc2";
    internal sealed class PageText { public int Page; public string Text; }
    internal sealed class Document {
        public string Model, SourceUrl, Sha256, PdfPath;
        public PageText[] Pages;
        public bool Reviewed;
    }
    internal static string Root {
        get {
#if AI_TEST
            string fixture = Environment.GetEnvironmentVariable("XIAOKAI_DATASHEET_TEST_ROOT");
            if (!String.IsNullOrEmpty(fixture)) return Path.GetFullPath(fixture);
#endif
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "小开工具箱", "数据手册");
        }
    }
    internal static void InstallResolver() {
        AppDomain.CurrentDomain.AssemblyResolve += delegate(object sender, ResolveEventArgs args) {
            string resource = "pdf." + new AssemblyName(args.Name).Name + ".dll";
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource)) {
                if (stream == null) return null;
                using (var bytes = new MemoryStream()) { stream.CopyTo(bytes); return Assembly.Load(bytes.ToArray()); }
            }
        };
    }
    static string Key(string model) {
        using (var hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(Utf8.GetBytes(model.Trim().ToUpperInvariant()))).Replace("-", "").Substring(0, 20);
    }
    internal static string Hash(string path) {
        using (var hash = SHA256.Create()) using (var file = File.OpenRead(path)) return BitConverter.ToString(hash.ComputeHash(file)).Replace("-", "").ToLowerInvariant();
    }
    static string Folder(string model) { return Path.Combine(Root, Regex.Replace(model, @"[^A-Za-z0-9._-]", "_").Substring(0, Math.Min(60, model.Length)) + "-" + Key(model)); }
    static string Compact(string text) { return Regex.Replace(text, @"\s+", " ").Trim(); }
    static void Write(string path, string body) {
        string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        File.WriteAllText(temp, body, Utf8);
        if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp, path);
    }
    internal static Document Read(string model) {
        string path = Path.Combine(Folder(model), "pages.json");
        try {
            if (!File.Exists(path) || new FileInfo(path).Length > 8 * 1024 * 1024) return null;
            var doc = Json.Deserialize<Document>(File.ReadAllText(path, Utf8));
            string pdf = Path.Combine(Folder(model), "datasheet.pdf");
            if (doc == null || !String.Equals(doc.Model, model, StringComparison.OrdinalIgnoreCase) || !File.Exists(pdf) || Hash(pdf) != doc.Sha256) return null;
            doc.PdfPath = pdf;
            // The manifest never grants trust. Exact source bytes identify the
            // reviewed edition; derive its text again for electrical evidence.
            doc.Reviewed = String.Equals(model, ReviewedModel, StringComparison.OrdinalIgnoreCase) && doc.Sha256 == ReviewedHash;
            return doc;
        } catch { return null; }
    }
    static Document Extract(string path, string model, string url) {
        var pages = new List<PageText>();
        using (var pdf = PdfDocument.Open(path)) {
            if (pdf.NumberOfPages > 500) throw new Exception("手册超过 500 页，请选用器件数据手册。");
            int length = 0;
            foreach (var page in pdf.GetPages()) {
                string text = Compact(String.Join(" ", page.GetWords().Select(word => word.Text)));
                length += text.Length;
                if (length > 1500000) throw new Exception("手册文本超过本次提取上限。");
                pages.Add(new PageText { Page = page.Number, Text = text });
            }
        }
        string hash = Hash(path);
        return new Document { Model = model, SourceUrl = url, PdfPath = path, Sha256 = hash, Pages = pages.ToArray(),
            Reviewed = String.Equals(model, ReviewedModel, StringComparison.OrdinalIgnoreCase) && hash == ReviewedHash };
    }
    internal static Document Import(string source, string model, string url) {
        if (String.IsNullOrWhiteSpace(model) || model.Length > 160) throw new Exception("请先填写完整器件型号。");
        if (new FileInfo(source).Length > 30 * 1024 * 1024) throw new Exception("PDF 超过 30 MB。");
        byte[] head = new byte[5];
        using (var file = File.OpenRead(source)) if (file.Read(head, 0, 5) != 5 || Encoding.ASCII.GetString(head) != "%PDF-") throw new Exception("下载内容不是 PDF。");
        string folder = Folder(model); Directory.CreateDirectory(folder);
        string stage = Path.Combine(folder, Guid.NewGuid().ToString("N") + ".pdf");
        try {
            File.Copy(source, stage);
            Document doc = Extract(stage, model, url);
            string dest = Path.Combine(folder, "datasheet.pdf");
            if (File.Exists(dest)) File.Replace(stage, dest, null); else File.Move(stage, dest);
            doc.PdfPath = dest;
            Write(Path.Combine(folder, "pages.json"), Json.Serialize(doc));
            return doc;
        } finally { if (File.Exists(stage)) File.Delete(stage); }
    }
    internal static Document Download(string model, string url, string cancel) {
        Uri uri;
        if (!Uri.TryCreate(url, UriKind.Absolute, out uri) || uri.Scheme != "https" || uri.UserInfo != "") throw new Exception("请使用公开的 HTTPS 手册链接。");
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        string temp = Path.GetTempFileName();
        try {
            var request = (HttpWebRequest)WebRequest.Create(uri);
            request.UserAgent = "Mozilla/5.0 XiaokaiDatasheet/1.0";
            request.Timeout = 18000; request.ReadWriteTimeout = 18000;
            request.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
            using (var response = (HttpWebResponse)request.GetResponse()) {
                if (response.ResponseUri.Scheme != "https") throw new Exception("手册下载跳转到了非 HTTPS 地址。");
                if (response.ContentLength > 30 * 1024 * 1024) throw new Exception("PDF 超过 30 MB。");
                using (var input = response.GetResponseStream()) using (var output = File.Create(temp)) {
                    byte[] buffer = new byte[65536]; int count; long total = 0;
                    while ((count = input.Read(buffer, 0, buffer.Length)) > 0) {
                        if (cancel != null && File.Exists(cancel)) throw new Exception("已取消资料读取。");
                        total += count; if (total > 30 * 1024 * 1024) throw new Exception("PDF 超过 30 MB。");
                        output.Write(buffer, 0, count);
                    }
                }
                url = response.ResponseUri.AbsoluteUri;
            }
            return Import(temp, model, url);
        } finally { File.Delete(temp); }
    }
    internal static Document Obtain(string model, string cancel) {
        Document doc = Read(model);
        if (doc != null) return doc;
        return String.Equals(model, ReviewedModel, StringComparison.OrdinalIgnoreCase) ? Download(model, ReviewedUrl, cancel) : null;
    }
    internal static string Requirement(string model, string footprint, string number, string name, string rule) {
        if (!String.Equals(model, ReviewedModel, StringComparison.OrdinalIgnoreCase) || rule != "unconnected_pin" ||
            !Regex.IsMatch(footprint ?? "", @"(?:^|[^A-Z])TSSOP[-_ ]?14(?:[^0-9]|$)", RegexOptions.IgnoreCase)) return "";
        var names = new Dictionary<string, string> { {"1","1OE"},{"2","1A"},{"3","1Y"},{"4","2OE"},{"5","2A"},{"6","2Y"},{"8","3Y"},{"9","3A"},{"10","3OE"},{"11","4Y"},{"12","4A"},{"13","4OE"},{"7","GND"},{"14","VCC"} };
        string expected;
        if (!names.TryGetValue(number ?? "", out expected) || Regex.Replace((name ?? "").ToUpperInvariant(), @"[~!#/_\\\s]", "") != expected) return "";
        return expected.EndsWith("Y",StringComparison.Ordinal) ? "optional_output" : (number == "7" || number == "14" ? "power" : "input");
    }
    internal static PageText Page(Document doc, int number) { return doc.Pages.FirstOrDefault(p => p.Page == number); }
    internal static Dictionary<string, object> Evidence(Document doc, string id, string requirement) {
        // Re-extract the exact reviewed PDF to avoid trusting edited cache text.
        doc = Extract(doc.PdfPath, doc.Model, doc.SourceUrl);
        int number = requirement == "power" ? 10 : 11;
        PageText page = Page(doc, number);
        if (!doc.Reviewed || page == null || !page.Text.Contains("SCLS264R")) return null;
        string text = page.Text;
        if (requirement == "input") {
            int at = text.IndexOf("Unused inputs must be terminated", StringComparison.OrdinalIgnoreCase);
            int end = at < 0 ? -1 : text.IndexOf("Unused outputs can be left floating", at, StringComparison.OrdinalIgnoreCase);
            if (at < 0 || end < 0) return null;
            text = text.Substring(at, Math.Min(end - at + "Unused outputs can be left floating.".Length, 4000));
        }
        if (requirement == "optional_output") {
            int at = text.IndexOf("Unused outputs can be left floating", StringComparison.OrdinalIgnoreCase);
            if (at < 0) return null;
            text = text.Substring(at, Math.Min(250, text.Length-at));
        }
        return new Dictionary<string, object> { {"id",id}, {"type","reviewed_datasheet"}, {"part_number",doc.Model},
            {"document","TI SCLS264R, February 2024"}, {"sha256",doc.Sha256}, {"url",ReviewedUrl}, {"pdf_page",number}, {"text",text}, {"requirement",requirement} };
    }
    internal static void OpenPdf(Document doc, int page) {
        // Open the existing PDF without shell command text or file association changes.
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(doc.PdfPath) { UseShellExecute = true });
    }
}
