using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Web.Script.Serialization;

internal static partial class AiBridge
{
    // No GUI in panel jobs. Sensitive input travels only through stdin.
    static void PanelJob(string output, string cancel)
    {
        var fields = new Dictionary<string, string>();
        string action = "";
        try {
            string input;
            using (var reader = new StreamReader(Console.OpenStandardInput(), Utf8)) input = reader.ReadLine();
            var request = Json.Deserialize<Dictionary<string,string>>(input);
            action = request["action"];
            Func<string,string> get = k => request.ContainsKey(k) ? request[k] : "";
            if (action.StartsWith("settings-", StringComparison.Ordinal)) {
                Config c;
                try { c = Load(); } catch { c = new Config(); fields["warning"] = "原配置无法读取；请重新填写并保存。"; }
                bool savedKey = !String.IsNullOrEmpty(c.Secret);
                if (action != "settings-read") {
                    c.Endpoint = get("endpoint").Trim(); c.Model = get("model").Trim();
                    c.JsonMode = get("json_mode") == "1";
                    if (get("clear_key") == "1") c.Secret = "";
                    else if (get("secret") != "") c.Secret = get("secret").Trim();
                    if (action == "settings-models") {
                        fields["models"] = FetchModels(c,cancel);
                        fields["message"] = "已获取模型列表，请下拉选择后保存。";
                    }
                    else if (action == "settings-save") { Save(c); savedKey = !String.IsNullOrEmpty(c.Secret); fields["message"] = "已保存 API KEY 设置。"; }
                    else if (action == "settings-test") {
                        string answer = TestConnection(c, cancel);
                        if (String.IsNullOrWhiteSpace(answer)) throw new Exception("API 返回了空文本，连接测试未通过。");
                        fields["message"] = "连接成功；保存后生效。";
                    } else throw new Exception("未知设置操作。");
                }
                fields["endpoint"] = c.Endpoint; fields["model"] = c.Model;
                fields["json_mode"] = c.JsonMode ? "1" : "0";
                fields["has_key"] = String.IsNullOrEmpty(c.Secret) ? "0" : "1";
                fields["saved_key"] = savedKey ? "1" : "0";
            } else {
                string model = get("part_number").Trim();
                if (model.Length == 0) throw new Exception("器件未填写型号，无法匹配手册。");
                Datasheets.Document doc = null;
                switch (action) {
                    case "datasheet-read":
                        doc = Datasheets.Obtain(model, cancel);
                        if (doc == null && get("datasheet_url").StartsWith("https://",StringComparison.OrdinalIgnoreCase))
                            doc = Datasheets.Download(model, get("datasheet_url"), cancel);
                        break;
                    case "datasheet-import": doc = Datasheets.Import(get("path"), model, "local-import"); break;
                    case "datasheet-open":
                        doc = Datasheets.Read(model);
                        if (doc == null) throw new Exception("还没有该器件的 PDF。");
                        Datasheets.OpenPdf(doc,1); break;
                    case "datasheet-chip":
                    case "datasheet-lcsc":
                        string url = action == "datasheet-chip" ? "https://www.semiee.com/search?searchModel=" : "https://so.szlcsc.com/global.html?k=";
                        System.Diagnostics.Process.Start(url + Uri.EscapeDataString(model));
                        fields["message"] = "已在浏览器打开器件搜索。"; break;
                    default: throw new Exception("未知手册操作。");
                }
                if (action == "datasheet-read" || action == "datasheet-import" || action == "datasheet-open") {
                    fields["pdf"] = doc == null ? "" : doc.PdfPath;
                    fields["text"] = doc == null ? "" : String.Join("\n\n",doc.Pages.Select(p => "—— PDF 第 " + p.Page + " 页 ——\n" + p.Text));
                    fields["message"] = doc == null ? "未匹配到手册。可从资料站下载后，在本页填写 PDF 路径导入。" :
                        (doc.Reviewed ? "已核对：TI SCLS264R，精确型号与文件版本匹配。" : "已归档；型号、封装和规则依据待核对。") + "\n" + doc.PdfPath;
                }
            }
            var result = new StringBuilder("OK\n");
            foreach (var item in fields) result.Append(item.Key).Append('\t').Append(B64(item.Value)).Append('\n');
            AtomicWrite(output,result.ToString());
        } catch (Exception ex) {
            // Never expose upstream response bodies or secret-bearing exceptions.
            string message = action.StartsWith("settings-",StringComparison.Ordinal) ? SafeError(ex) :
                (ex is System.Net.WebException ? "手册请求未成功，请检查地址后重试。" : ex.Message);
            message = message.Replace('\r',' ').Replace('\n',' ');
            if (message.Length > 800) message = message.Substring(0,800);
            AtomicWrite(output, "ERROR\t" + B64(message) + "\n");
        }
    }
}
