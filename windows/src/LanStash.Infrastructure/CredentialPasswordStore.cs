using LanStash.Domain;
using Windows.Security.Credentials;

namespace LanStash.Infrastructure;

public sealed class CredentialPasswordStore : ISecurePasswordStore
{
    private const string Resource = "LanStash.DsmPassword";
    private readonly PasswordVault _vault = new();

    public Task SaveAsync(
        Guid profileId,
        string password,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RemoveExisting(profileId);
        _vault.Add(new PasswordCredential(Resource, profileId.ToString("D"), password));
        return Task.CompletedTask;
    }

    public Task<string?> LoadAsync(
        Guid profileId,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            var credential = _vault.Retrieve(Resource, profileId.ToString("D"));
            credential.RetrievePassword();
            return Task.FromResult<string?>(credential.Password);
        }
        catch
        {
            return Task.FromResult<string?>(null);
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
            _vault.Remove(_vault.Retrieve(Resource, profileId.ToString("D")));
        }
        catch
        {
            // 不存在的密码无需处理。
        }
    }
}
