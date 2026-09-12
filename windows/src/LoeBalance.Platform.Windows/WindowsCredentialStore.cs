using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;
using LoeBalance.Core.Persistence;

namespace LoeBalance.Platform.Windows;

/// <summary>
/// Stores the refresh token and the user id in the Windows Credential Manager.
/// The password is never persisted and the access token stays in memory only.
/// </summary>
public sealed class WindowsCredentialStore : IWindowsCredentialStore
{
    private const int CredTypeGeneric = 1;
    private const int CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    private readonly string _targetName;

    public WindowsCredentialStore(string? targetName = null)
        => _targetName = string.IsNullOrWhiteSpace(targetName)
            ? WindowsPlatformNotes.CredentialManagerTarget
            : targetName;

    public Task<StoredCredential?> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!Native.CredRead(_targetName, CredTypeGeneric, 0, out var handle))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound) return Task.FromResult<StoredCredential?>(null);
            throw CredentialError("read", error);
        }

        try
        {
            var credential = Marshal.PtrToStructure<Native.Credential>(handle);
            if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == IntPtr.Zero)
            {
                throw new AppException(AppErrorKind.CredentialStore, "The stored credential was empty.");
            }

            var json = Marshal.PtrToStringAnsi(credential.CredentialBlob, credential.CredentialBlobSize);
            return Task.FromResult(Deserialize(json));
        }
        finally
        {
            Native.CredFree(handle);
        }
    }

    public Task SaveAsync(StoredCredential credential, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(credential);
        if (string.IsNullOrWhiteSpace(credential.RefreshToken))
        {
            throw new AppException(AppErrorKind.CredentialStore, "The refresh token must not be empty.");
        }

        var payload = JsonSerializer.SerializeToUtf8Bytes(
            new StoredCredentialPayload(credential.RefreshToken, credential.UserId),
            PersistenceJson.Options);

        var blob = Marshal.AllocHGlobal(payload.Length);
        var target = Marshal.StringToCoTaskMemUni(_targetName);
        var user = Marshal.StringToCoTaskMemUni(WindowsPlatformNotes.CredentialUserName);
        try
        {
            Marshal.Copy(payload, 0, blob, payload.Length);
            var native = new Native.Credential
            {
                Type = CredTypeGeneric,
                TargetName = target,
                UserName = user,
                CredentialBlob = blob,
                CredentialBlobSize = payload.Length,
                Persist = CredPersistLocalMachine
            };

            if (!Native.CredWrite(ref native, 0))
            {
                throw CredentialError("write", Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
            Marshal.FreeCoTaskMem(target);
            Marshal.FreeCoTaskMem(user);
            Array.Clear(payload);
        }

        return Task.CompletedTask;
    }

    public Task DeleteAsync(CancellationToken cancellationToken = default)
    {
        if (Native.CredDelete(_targetName, CredTypeGeneric, 0))
        {
            return Task.CompletedTask;
        }

        var error = Marshal.GetLastWin32Error();
        if (error == ErrorNotFound) return Task.CompletedTask;
        throw CredentialError("delete", error);
    }

    private static StoredCredential? Deserialize(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            var payload = JsonSerializer.Deserialize<StoredCredentialPayload>(json, PersistenceJson.Options);
            if (payload is null || string.IsNullOrWhiteSpace(payload.RefreshToken)) return null;
            return new StoredCredential(payload.RefreshToken, payload.UserId);
        }
        catch (JsonException exception)
        {
            // Never echo the payload: it contains a credential.
            throw new AppException(AppErrorKind.CredentialStore, "The stored credential could not be decoded.", exception);
        }
    }

    private static AppException CredentialError(string operation, int error)
        => new(
            AppErrorKind.CredentialStore,
            $"The Windows Credential Manager {operation} failed with error {error}.");

    private sealed record StoredCredentialPayload(string RefreshToken, long UserId);

    private static class Native
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        internal struct Credential
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
        internal static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CredWrite([In] ref Credential userCredential, int flags);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CredDelete(string target, int type, int flags);

        [DllImport("advapi32.dll", EntryPoint = "CredFree", SetLastError = true)]
        internal static extern void CredFree([In] IntPtr buffer);
    }
}
