using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Auth;

public interface ICredentialStore
{
    Task<StoredCredential?> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(StoredCredential credential, CancellationToken cancellationToken = default);
    Task DeleteAsync(CancellationToken cancellationToken = default);
}
