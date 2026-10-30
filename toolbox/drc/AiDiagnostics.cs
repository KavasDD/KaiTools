using System;
using System.IO;
using System.Net;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Text.RegularExpressions;

internal static partial class AiBridge
{
    sealed class ModelFormatException : Exception {
        internal ModelFormatException(string message) : base(message) { }
    }
    static string RedactPreview(string value, string secret) {
        if (!String.IsNullOrEmpty(secret)) value = value.Replace(secret,"[Key 已隐藏]");
        value = Regex.Replace(value,@"(?i)(?:bearer\s+\S+|sk-[A-Za-z0-9_-]+|(?:api[_-]?key|token|secret)\s*[:=]\s*[^\s,;]+)","[凭据已隐藏]");
        value = Regex.Replace(value,@"https?://\S+","[服务地址]");
        value = Regex.Replace(value,@"[\p{Cc}\p{Cf}]+"," ");
        value = Regex.Replace(value,@"\s+"," ").Trim();
        return value.Length <= 800 ? value : value.Substring(0,800) + "…（片段已截短）";
    }
    static Dictionary<string,object> ParseModelAnswer(string body) {
        string text = body.Trim().TrimStart('\uFEFF');
        // Some compatible proxies JSON-encode the assistant text twice.
        if (text.StartsWith("\"",StringComparison.Ordinal)) {
            try {
                var decoded = Json.DeserializeObject(text) as string;
                if (decoded != null) { text = decoded.Trim().TrimStart('\uFEFF'); Progress("识别到二次编码的模型文本，已解码"); }
            } catch { }
        }
        if (text.StartsWith("[",StringComparison.Ordinal))
            throw new ModelFormatException("模型返回了数组，预期为包含 request_id 和 findings 的 JSON 对象");
        int start=-1, end=-1, depth=0, objects=0;
        bool quoted=false, escaped=false;
        for (int i=0;i<text.Length;i++) {
            char ch=text[i];
            if (depth==0) {
                if (ch=='{') { start=objects==0 ? i : start; depth=1; objects++; quoted=false; escaped=false; }
                continue;
            }
            if (quoted) {
                if (escaped) { escaped=false; continue; }
                if (ch=='\\') { escaped=true; continue; }
                if (ch=='"') quoted=false;
                continue;
            }
            if (ch=='"') { quoted=true; continue; }
            if (ch=='{') depth++;
            if (ch=='}' && --depth==0) end=i;
        }
        if (objects==0) throw new ModelFormatException("模型返回了说明文字，未找到完整的 JSON 对象");
        if (objects>1) throw new ModelFormatException("模型返回了多个 JSON 对象，无法确定唯一结论");
        if (depth!=0 || quoted || end<start) throw new ModelFormatException("模型的 JSON 对象或字符串未闭合，返回可能不完整");
        string candidate=text.Substring(start,end-start+1);
        object parsed;
        try { parsed=Json.DeserializeObject(candidate); }
        catch { throw new ModelFormatException("模型结论的 JSON 语法不合法，例如引号、逗号或转义符错误"); }
        var obj=parsed as Dictionary<string,object>;
        if (obj==null) throw new ModelFormatException("模型结论不是 JSON 对象");
        if (start!=0 || end!=text.Length-1) Progress("已从说明文字或代码块中提取完整 JSON，继续核对批次与证据");
        return obj;
    }
    static Dictionary<string,object> ReadModelAnswer(Config config, string context, string cancel) {
        string reply=Call(config,Instructions,context,cancel);
        try { return ParseModelAnswer(reply); }
        catch (ModelFormatException first) {
            if (Cancelled(cancel)) throw new Exception("已取消 AI 请求。");
            Progress("模型结论格式不符合约定：" + first.Message + "；自动重试一次（1/1）");
            reply=Call(config,Instructions,context,cancel,reply);
            try { return ParseModelAnswer(reply); }
            catch (ModelFormatException second) {
                throw new Exception("AI 模型结论格式重试后仍失败：" + second.Message + "。\n这表示返回格式未通过解析，不能据此判断模型是否理解原理图。\n返回长度：" + reply.Length + " 字符。\n模型返回片段（未应用）：" + RedactPreview(reply,config.Secret));
            }
        }
    }
    static string progressPath;
    static void Progress(string message) {
        if (String.IsNullOrEmpty(progressPath)) return;
        try { File.AppendAllText(progressPath, DateTime.Now.ToString("HH:mm:ss") + "  " + message + "\n", Utf8); } catch { }
    }
    static object ParseApiResponse(string body, string contentType, string stage) {
        string trimmed = body.TrimStart('\uFEFF', ' ', '\t', '\r', '\n');
        if (trimmed.StartsWith("<", StringComparison.Ordinal) ||
            (!trimmed.StartsWith("{", StringComparison.Ordinal) &&
             (contentType ?? "").IndexOf("text/html", StringComparison.OrdinalIgnoreCase) >= 0))
            throw new Exception("API " + stage + "返回了 HTML 网页，未返回 JSON；请检查 API 路径，常见地址为 https://域名/v1。若路径正确，请检查代理登录页或访问验证；这不表示模型不支持 JSON。");
        if (trimmed.StartsWith("data:", StringComparison.Ordinal) ||
            (contentType ?? "").IndexOf("text/event-stream", StringComparison.OrdinalIgnoreCase) >= 0)
            throw new Exception("API " + stage + "返回了流式事件，但请求已设置 stream=false；请检查代理是否支持非流式 Chat Completions。");
        return ParseJson(body, stage);
    }
    static object ParseJson(string body, string stage) {
        string trimmed = body.Trim();
        if (trimmed.StartsWith("```",StringComparison.Ordinal)) {
            int newline = trimmed.IndexOf('\n');
            string fence = newline < 0 ? "" : trimmed.Substring(0,newline).Trim();
            if ((fence == "```json" || fence == "```") && trimmed.EndsWith("```",StringComparison.Ordinal))
                trimmed = trimmed.Substring(newline+1,trimmed.Length-newline-4).Trim();
        }
        if (!trimmed.StartsWith("{",StringComparison.Ordinal))
            throw new Exception("AI " + stage + "未返回 JSON 对象；可能是接口地址、协议不兼容，或模型未按要求返回 JSON。");
        try { return Json.DeserializeObject(trimmed); }
        catch { throw new Exception("AI " + stage + "的 JSON 格式无法解析；请换用支持结构化输出的模型，或检查代理返回格式。"); }
    }
    static string ReadBounded(Stream stream, int limit) {
        using (var memory = new MemoryStream()) {
            byte[] buffer = new byte[4096]; int count;
            while ((count = stream.Read(buffer,0,Math.Min(buffer.Length,limit+1-(int)memory.Length))) > 0) {
                memory.Write(buffer,0,count);
                if (memory.Length > limit) throw new Exception("API 响应过大，已停止读取。");
            }
            return Utf8.GetString(memory.ToArray());
        }
    }
    static string HttpError(WebException ex, Config config) {
        var response = ex.Response as HttpWebResponse;
        if (response == null) {
            switch (ex.Status) {
                case WebExceptionStatus.NameResolutionFailure: case WebExceptionStatus.ProxyNameResolutionFailure:
                    return "AI 无法解析接口域名，请检查 API 地址和 DNS。";
                case WebExceptionStatus.ConnectFailure: return "AI 无法连接接口；请检查地址、端口或本机代理是否启动。";
                case WebExceptionStatus.TrustFailure: case WebExceptionStatus.SecureChannelFailure:
                    return "AI HTTPS 证书或 TLS 握手失败，请检查证书、代理和系统时间。";
                case WebExceptionStatus.Timeout: case WebExceptionStatus.RequestCanceled:
                    return "AI 请求超时，服务未在 90 秒内返回，请稍后重试或缩小范围。";
                default: return "AI 网络请求失败（" + ex.Status + "），请检查网络或代理。";
            }
        }
        int status = (int)response.StatusCode;
        string detail = "";
        // Only structured, bounded service error fields; never echo HTML or entire responses.
        try {
            using (var stream = response.GetResponseStream()) {
                var obj = Obj(Json.DeserializeObject(ReadBounded(stream,16384)));
                object error;
                if (obj.TryGetValue("error",out error) && error is Dictionary<string,object>) {
                    var fields = (Dictionary<string,object>)error;
                    object code, message;
                    if (fields.TryGetValue("code",out code) && code is string) detail = (string)code;
                    if (fields.TryGetValue("message",out message) && message is string) detail += " " + (string)message;
                }
            }
        } catch { } finally { response.Close(); }
        if (!String.IsNullOrEmpty(config.Secret)) detail = detail.Replace(config.Secret,"[Key 已隐藏]");
        detail = Regex.Replace(detail,@"(?i)(?:bearer\s+\S+|sk-[A-Za-z0-9_-]+|(?:api[_-]?key|token|secret)\s*[:=]\s*[^\s,;]+)","[凭据已隐藏]");
        detail = Regex.Replace(detail,@"https?://\S+","[服务地址]");
        detail = Regex.Replace(detail,@"\s+"," ").Trim();
        if (detail.Length > 240) detail = detail.Substring(0,240) + "…";
        string advice;
        switch (status) {
            case 400: case 422: advice = "请求参数或协议不兼容；检查模型和 JSON 模式。"; break;
            case 401: advice = "Key 无效或未授权，请检查 Key。"; break;
            case 403: advice = "无访问权限；检查账号、模型权限和区域限制。"; break;
            case 404: advice = "接口路径或模型不存在；检查 API 地址及模型名称。"; break;
            case 429: advice = "请求频率、额度或余额受限，请检查服务商账户。"; break;
            default: advice = status >= 500 ? "服务端或代理异常，请稍后重试。" : "请检查服务商接口配置。"; break;
        }
        return "API 请求失败（HTTP " + status + "）：" + advice + (detail == "" ? "" : " 服务返回：" + detail);
    }
    static string TestConnection(Config config, string cancel) {
        string answer = Call(config, config.JsonMode ? "Reply with a JSON object: {\"status\":\"OK\"}." : "Reply with OK.", "Connection test.", cancel);
        if (String.IsNullOrWhiteSpace(answer)) throw new Exception("API 返回了空文本，连接测试未通过。");
        return answer;
    }
    static string FetchModels(Config config, string cancel) {
        var probe = new Config { Endpoint=config.Endpoint,Model="models-probe",Secret=config.Secret };
        string completion = Validate(probe).AbsoluteUri;
        string url = completion.Substring(0,completion.Length-"chat/completions".Length) + "models";
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        var request = (HttpWebRequest)WebRequest.Create(url);
        request.Method="GET"; request.Accept="application/json"; request.AllowAutoRedirect=false;
        request.Timeout=20000; request.ReadWriteTimeout=20000;
        if (!String.IsNullOrEmpty(config.Secret)) request.Headers["Authorization"]="Bearer "+config.Secret;
        try {
            using (var response = (HttpWebResponse)request.GetResponse()) {
                if ((int)response.StatusCode>=300) throw new Exception("API 模型列表返回重定向，请填写最终接口地址。");
                string body; using (var stream=response.GetResponseStream()) body=ReadBounded(stream,1024*1024);
                var obj=Obj(ParseApiResponse(body,response.ContentType,"模型列表")); object data;
                if (!obj.TryGetValue("data",out data)) throw new Exception("API 模型列表缺少 data 字段；该服务可能未提供兼容的 /models 接口，可手动填写模型。 ");
                var names=new SortedSet<string>(StringComparer.Ordinal);
                foreach (object item in ArrayValue(data)) {
                    object id; var model=item as Dictionary<string,object>;
                    if (model!=null && model.TryGetValue("id",out id) && id is string &&
                        ((string)id).Length>0 && ((string)id).Length<=160 && !((string)id).Any(Char.IsControl)) names.Add((string)id);
                    if (names.Count>=2000) break;
                }
                if (names.Count==0) throw new Exception("API 未返回可用模型，请检查 Key 权限或手动填写模型。");
                return String.Join("\n",names);
            }
        } catch (WebException ex) {
            var response = ex.Response as HttpWebResponse;
            bool unsupported = response != null && ((int)response.StatusCode == 404 || (int)response.StatusCode == 405);
            throw new Exception(HttpError(ex,config) + (unsupported ? " 若服务未提供 /models，可手动填写模型名称。" : ""));
        }
    }
}
