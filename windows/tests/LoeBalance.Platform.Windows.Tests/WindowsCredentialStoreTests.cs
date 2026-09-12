using System.Runtime.InteropServices;
using System.Text;
using LoeBalance.Core.Networking;
using LoeBalance.Platform.Windows;

namespace LoeBalance.Platform.Windows.Tests;

/// <summary>
/// Real Windows Credential Manager round-trip. These tests run on Windows only and clean
/// up after themselves with a per-run target name.
/// </summary>
public sealed class WindowsCredentialStoreTests
{
    private static string UniqueTarget() => $"LoeBalance:test-{Guid.NewGuid():N}";

    [Fact]
    public async Task MissingCredentialLoadsAsNull()
    {
        var store = new WindowsCredentialStore(UniqueTarget());

        Assert.Null(await store.LoadAsync());
        await store.DeleteAsync();
    }

    [Fact]
    public async Task RoundTripsTheRefreshTokenAndUserId()
    {
        var target = UniqueTarget();
        var store = new WindowsCredentialStore(target);
        try
        {
            await store.SaveAsync(new StoredCredential("refresh-token-value", 42));

            var loaded = await store.LoadAsync();

            Assert.NotNull(loaded);
            Assert.Equal("refresh-token-value", loaded!.RefreshToken);
            Assert.Equal(42, loaded.UserId);
        }
        finally
        {
            await store.DeleteAsync();
        }
    }

    [Fact]
    public async Task SavingReplacesTheExistingCredential()
    {
        var store = new WindowsCredentialStore(UniqueTarget());
        try
        {
            await store.SaveAsync(new StoredCredential("first", 1));
            await store.SaveAsync(new StoredCredential("second", 2));

            var loaded = await store.LoadAsync();

            Assert.Equal(new StoredCredential("second", 2), loaded);
        }
        finally
        {
            await store.DeleteAsync();
        }
    }

    [Fact]
    public async Task DeletingRemovesTheCredential()
    {
        var store = new WindowsCredentialStore(UniqueTarget());
        await store.SaveAsync(new StoredCredential("refresh", 7));

        await store.DeleteAsync();

        Assert.Null(await store.LoadAsync());
    }

    [Fact]
    public async Task StoredBlobContainsOnlyTheRefreshTokenAndUserId()
    {
        var target = UniqueTarget();
        var store = new WindowsCredentialStore(target);
        try
        {
            await store.SaveAsync(new StoredCredential("refresh-token-value", 42));

            var blob = ReadRawBlob(target);
            using var document = System.Text.Json.JsonDocument.Parse(blob);
            var properties = document.RootElement.EnumerateObject().Select(property => property.Name).ToArray();

            Assert.Contains("refresh-token-value", blob, StringComparison.Ordinal);
            // Strongest form of the security rule: the credential payload has exactly the
            // two allowed fields and nothing else.
            Assert.Equal(["refreshToken", "userId"], properties);
            Assert.Equal(42, document.RootElement.GetProperty("userId").GetInt64());
            Assert.DoesNotContain("password", blob, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("accessToken", blob, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            await store.DeleteAsync();
        }
    }

    private static string ReadRawBlob(string target)
    {
        Assert.True(CredRead(target, 1, 0, out var handle));
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(handle);
            var buffer = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, buffer, 0, buffer.Length);
            return Encoding.UTF8.GetString(buffer);
        }
        finally
        {
            CredFree(handle);
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public int Flags;
        public int Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(
        string target,
        int type,
        int reservedFlag,
        out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
    private static extern void CredFree([In] IntPtr buffer);
}
