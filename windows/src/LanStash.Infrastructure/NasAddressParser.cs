using LanStash.Domain;

namespace LanStash.Infrastructure;

public enum NasAddressKind
{
    Direct,
    QuickConnect,
}

public sealed record ParsedNasAddress(
    string Host,
    int Port,
    NasAddressKind Kind,
    bool HasExplicitPort);

public static class NasAddressParser
{
    private const int DsmHttpsPort = 5001;

    public static ParsedNasAddress Parse(string input, int? portOverride = null)
    {
        if (portOverride is not null and (< 1 or > 65535))
        {
            throw InvalidAddress();
        }
        var trimmed = input.Trim();
        if (trimmed.Length == 0)
        {
            throw new DsmException(
                UserText.Key("WinShared2d790edfcf9d3321"),
                UserText.Key("WinShared2608798758baa746"),
                kind: DsmErrorKind.InvalidAddress);
        }

        var hasScheme = trimmed.Contains("://", StringComparison.Ordinal);
        if (!Uri.TryCreate(hasScheme ? trimmed : $"https://{trimmed}", UriKind.Absolute, out var uri) ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Query) ||
            !string.IsNullOrEmpty(uri.Fragment) ||
            string.IsNullOrWhiteSpace(uri.Host))
        {
            throw InvalidAddress();
        }

        var host = uri.Host.ToLowerInvariant();
        var portalId = QuickConnectId(host, uri.AbsolutePath);
        if (portalId is not null)
        {
            return IsPotentialQuickConnectId(portalId)
                ? new(portalId, portOverride ?? DsmHttpsPort, NasAddressKind.QuickConnect, portOverride is not null)
                : throw InvalidAddress();
        }
        if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase))
        {
            throw new DsmException(
                UserText.Key("WinSharedba22fbf3f7f63943"),
                UserText.Key("WinShared4234d503af1c54d5"),
                kind: DsmErrorKind.InsecureAddress);
        }
        if (IsPotentialQuickConnectId(host))
        {
            return new(host, portOverride ?? DsmHttpsPort, NasAddressKind.QuickConnect, portOverride is not null);
        }

        int? explicitPort = uri.IsDefaultPort ? null : uri.Port;
        var port = portOverride ?? explicitPort ?? (hasScheme ? 443 : DsmHttpsPort);
        return port is >= 1 and <= 65535
            ? new(host, port, NasAddressKind.Direct, portOverride is not null || explicitPort is not null)
            : throw InvalidAddress();
    }

    public static bool IsPotentialQuickConnectId(string value) =>
        value.Length is >= 1 and <= 64 &&
        !value.Contains('.') &&
        !value.Contains(':') &&
        value[0] != '-' &&
        value[^1] != '-' &&
        value.All(character =>
            character is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9' or '-');

    private static string? QuickConnectId(string host, string path)
    {
        if (host is "quickconnect.to" or "quickconnect.cn")
        {
            return path.Split('/', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.ToLowerInvariant();
        }
        foreach (var portal in new[] { "quickconnect.to", "quickconnect.cn" })
        {
            var suffix = $".{portal}";
            if (host.EndsWith(suffix, StringComparison.Ordinal) &&
                host.Count(character => character == '.') == 2)
            {
                return host[..^suffix.Length].ToLowerInvariant();
            }
        }
        return null;
    }

    private static DsmException InvalidAddress() => new(
        UserText.Key("WinSharedd69866d5c54d766d"),
        UserText.Key("WinShared07e42c78bef61378"),
        kind: DsmErrorKind.InvalidAddress);
}
