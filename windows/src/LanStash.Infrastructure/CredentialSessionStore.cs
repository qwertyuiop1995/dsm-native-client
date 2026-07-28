using System.Text.Json;
using LanStash.Domain;
using Windows.Security.Credentials;

namespace LanStash.Infrastructure;

public sealed class CredentialSessionStore : ISecureSessionStore
{
    private const string Resource = "LanStash.DsmSession";
    private readonly PasswordVault _vault = new();

    public Task SaveAsync(
        DsmSession session,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RemoveExisting(session.ProfileId);
        _vault.Add(new PasswordCredential(
            Resource,
            session.ProfileId.ToString("D"),
            JsonSerializer.Serialize(session)));
        return Task.CompletedTask;
    }

    public Task<DsmSession?> LoadAsync(
        Guid profileId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            var credential = _vault.Retrieve(
                Resource,
                profileId.ToString("D"));
            credential.RetrievePassword();
            return Task.FromResult(
                JsonSerializer.Deserialize<DsmSession>(credential.Password));
        }
        catch
        {
            return Task.FromResult<DsmSession?>(null);
        }
    }

    public Task RemoveAsync(
        Guid profileId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RemoveExisting(profileId);
        return Task.CompletedTask;
    }

    private void RemoveExisting(Guid profileId)
    {
        try
        {
            var credential = _vault.Retrieve(
                Resource,
                profileId.ToString("D"));
            _vault.Remove(credential);
        }
        catch
        {
            // 不存在的会话无需处理。
        }
    }
}
