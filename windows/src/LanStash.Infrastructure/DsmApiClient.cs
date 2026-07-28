using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using LanStash.Domain;

namespace LanStash.Infrastructure;

public sealed class DsmApiClient(HttpClient httpClient) : IDsmApiClient
{
    private readonly HttpClient _http = httpClient;

    public Uri GetBaseUri(NasProfile profile)
    {
        var input = profile.Host.Trim();
        if (!input.Contains("://", StringComparison.Ordinal))
        {
            input = $"https://{input}";
        }

        if (!Uri.TryCreate(input, UriKind.Absolute, out var uri) ||
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(uri.Host))
        {
            throw new DsmException(
                "NAS 地址格式不正确",
                "请输入有效的 HTTPS 地址后重试。");
        }

        var builder = new UriBuilder(uri);
        if (profile.Port is not null)
        {
            builder.Port = profile.Port.Value;
        }
        builder.Path = builder.Path.TrimEnd('/');
        return builder.Uri;
    }

    public async Task<IReadOnlyDictionary<string, ApiCapability>> DiscoverAsync(
        NasProfile profile,
        CancellationToken cancellationToken = default)
    {
        var data = await PostAsync(
            profile,
            "/webapi/query.cgi",
            new Dictionary<string, string>
            {
                ["api"] = "SYNO.API.Info",
                ["version"] = "1",
                ["method"] = "query",
                ["query"] = "all",
            },
            session: null,
            cancellationToken).ConfigureAwait(false);
        var result = new Dictionary<string, ApiCapability>(StringComparer.Ordinal);
        foreach (var (name, node) in data)
        {
            if (node is not JsonObject value ||
                value["path"]?.GetValue<string>() is not { Length: > 0 } path)
            {
                continue;
            }
            var minVersion = value["minVersion"]?.GetValue<int>() ?? 1;
            var maxVersion = value["maxVersion"]?.GetValue<int>() ?? minVersion;
            result[name] = new ApiCapability(
                name,
                path,
                minVersion,
                maxVersion,
                value["requestFormat"]?.GetValue<string>() ?? "FORM");
        }
        return result;
    }

    public async Task<DsmSession> LoginAsync(
        NasProfile profile,
        string password,
        string? otp,
        CancellationToken cancellationToken = default)
    {
        var parameters = new Dictionary<string, string>
        {
            ["api"] = "SYNO.API.Auth",
            ["version"] = "7",
            ["method"] = "login",
            ["account"] = profile.Username,
            ["passwd"] = password,
            ["session"] = "FileStation",
            ["format"] = "sid",
            ["enable_syno_token"] = "yes",
            ["enable_device_token"] = "yes",
            ["device_name"] = "岚仓 Windows",
        };
        if (!string.IsNullOrWhiteSpace(otp))
        {
            parameters["otp_code"] = otp.Trim();
        }
        var data = await PostAsync(
            profile,
            "/webapi/auth.cgi",
            parameters,
            session: null,
            cancellationToken).ConfigureAwait(false);
        var sid = data["sid"]?.GetValue<string>();
        if (string.IsNullOrWhiteSpace(sid))
        {
            throw new DsmException(
                "NAS 没有返回登录会话",
                "请重新登录。",
                authenticationFailure: true);
        }
        return new DsmSession(
            profile.Id,
            sid,
            data["synotoken"]?.GetValue<string>(),
            data["did"]?.GetValue<string>());
    }

    public async Task LogoutAsync(
        NasProfile profile,
        DsmSession session,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await PostAsync(
                profile,
                "/webapi/auth.cgi",
                new Dictionary<string, string>
                {
                    ["api"] = "SYNO.API.Auth",
                    ["version"] = "7",
                    ["method"] = "logout",
                    ["session"] = "FileStation",
                },
                session,
                cancellationToken).ConfigureAwait(false);
        }
        catch (DsmException)
        {
            // 本机仍应清除会话，远端退出失败不阻塞用户。
        }
    }

    public Task<JsonObject> CallAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string method,
        IReadOnlyDictionary<string, string>? parameters = null,
        CancellationToken cancellationToken = default)
    {
        var values = new Dictionary<string, string>
        {
            ["api"] = capability.Name,
            ["version"] = capability.MaxVersion.ToString(),
            ["method"] = method,
        };
        if (parameters is not null)
        {
            foreach (var (key, value) in parameters)
            {
                values[key] = value;
            }
        }
        var path = capability.Path.StartsWith('/') ? capability.Path : $"/webapi/{capability.Path}";
        return PostAsync(profile, path, values, session, cancellationToken);
    }

    private async Task<JsonObject> PostAsync(
        NasProfile profile,
        string path,
        IReadOnlyDictionary<string, string> parameters,
        DsmSession? session,
        CancellationToken cancellationToken)
    {
        var values = new Dictionary<string, string>(parameters, StringComparer.Ordinal);
        if (session is not null)
        {
            values["_sid"] = session.Sid;
        }
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            new Uri(GetBaseUri(profile), path))
        {
            Content = new FormUrlEncodedContent(values),
        };
        request.Headers.Accept.ParseAdd("application/json");
        request.Headers.UserAgent.ParseAdd("LanStash-Windows/0.1");
        if (session is not null)
        {
            request.Headers.TryAddWithoutValidation("Cookie", $"id={session.Sid}");
            if (!string.IsNullOrWhiteSpace(session.SynoToken))
            {
                request.Headers.TryAddWithoutValidation("X-SYNO-TOKEN", session.SynoToken);
            }
        }

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new DsmException(
                "连接 NAS 超时",
                "请检查网络和地址后重试。");
        }
        catch (HttpRequestException)
        {
            throw new DsmException(
                "无法连接到 NAS",
                "请检查网络、地址和证书后重试。");
        }
        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new DsmException(
                    "无法连接到 NAS",
                    "请检查网络、地址和证书后重试。",
                    (int)response.StatusCode,
                    response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden);
            }
            await using var stream = await response.Content
                .ReadAsStreamAsync(cancellationToken)
                .ConfigureAwait(false);
            var envelope = await JsonNode.ParseAsync(
                stream,
                cancellationToken: cancellationToken).ConfigureAwait(false) as JsonObject
                ?? throw new DsmException(
                    "NAS 返回了无法识别的内容",
                    "请确认地址指向 DSM 后重试。");
            if (envelope["success"]?.GetValue<bool>() == true)
            {
                return envelope["data"] as JsonObject ?? [];
            }
            var code = envelope["error"]?["code"]?.GetValue<int>();
            throw MapFailure(code);
        }
    }

    private static DsmException MapFailure(int? code) => code switch
    {
        102 => new("当前 NAS 不支持这项功能", "请更新 DSM 或相关套件。", code),
        103 => new("当前套件版本不支持这项操作", "请更新套件后重试。", code),
        104 => new("登录会话已失效", "请重新登录。", code, true),
        105 => new("当前账号没有权限", "请使用具备相应权限的账号。", code),
        406 => new("需要输入双重验证代码", "请输入验证器中的当前代码。", code, true),
        407 => new("双重验证代码不正确", "请使用最新代码重试。", code, true),
        400 or 401 or 402 or 403 or 404 =>
            new("账号或登录信息不正确", "请核对账号、密码和验证码。", code, true),
        _ => new("NAS 没有完成这次操作", "请刷新后重试。", code),
    };
}
