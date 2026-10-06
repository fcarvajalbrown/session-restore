Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WinXShortcut
{
    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore
    {
        void GetCount(out uint count);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, out PropVariant value);
        void SetValue(ref PropertyKey key, ref PropVariant value);
        void Commit();
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PropVariant
    {
        [FieldOffset(0)] public ushort VariantType;
        [FieldOffset(8)] public uint UInt32Value;
    }

    const ushort VtUInt32 = 19;
    const int GpsReadWrite = 2;
    static readonly Guid PropertyStoreId = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    static readonly PropertyKey HashKey = new PropertyKey { FormatId = new Guid("FB8D2D7B-90D1-4E34-BF60-6EAC09922BBF"), PropertyId = 2 };

    [DllImport("shlwapi.dll")]
    static extern int HashData(byte[] data, int dataLength, byte[] hash, int hashLength);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHGetPropertyStoreFromParsingName(string path, IntPtr bindContext, int flags, ref Guid interfaceId, out IPropertyStore store);

    public static uint ComputeHash(string generalizedTarget, string arguments)
    {
        string blob = (generalizedTarget + (arguments ?? "") + "do not prehash links.  this should only be done by the user.").ToLowerInvariant();
        byte[] data = System.Text.Encoding.Unicode.GetBytes(blob);
        byte[] hash = new byte[4];
        Marshal.ThrowExceptionForHR(HashData(data, data.Length, hash, hash.Length));
        return BitConverter.ToUInt32(hash, 0);
    }

    static IPropertyStore Open(string path, int flags)
    {
        Guid interfaceId = PropertyStoreId;
        IPropertyStore store;
        SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, flags, ref interfaceId, out store);
        return store;
    }

    public static uint ReadHash(string path)
    {
        IPropertyStore store = Open(path, 0);
        PropertyKey key = HashKey;
        PropVariant value;
        store.GetValue(ref key, out value);
        Marshal.ReleaseComObject(store);
        return value.VariantType == VtUInt32 ? value.UInt32Value : 0;
    }

    public static void WriteHash(string path, uint hash)
    {
        IPropertyStore store = Open(path, GpsReadWrite);
        PropertyKey key = HashKey;
        PropVariant value = new PropVariant { VariantType = VtUInt32, UInt32Value = hash };
        store.SetValue(ref key, ref value);
        store.Commit();
        Marshal.ReleaseComObject(store);
    }
}
'@

function Get-GeneralizedTarget([string]$Target) {
    $knownFolders = @(
        @{ Path = $env:ProgramW6432; Id = '{905E63B6-C1BF-494E-B29C-65B732D3D21A}' }
        @{ Path = (Join-Path $env:SystemRoot 'System32'); Id = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' }
        @{ Path = $env:SystemRoot; Id = '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' }
    )
    foreach ($folder in $knownFolders) {
        if ($folder.Path -and $Target.StartsWith($folder.Path + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $folder.Id + $Target.Substring($folder.Path.Length)
        }
    }
    $Target
}

function Get-WinXHash([string]$Target, [string]$Arguments) {
    [WinXShortcut]::ComputeHash((Get-GeneralizedTarget $Target), $Arguments)
}

function New-WinXShortcut([string]$Path, [string]$Target, [string]$Arguments, [string]$Icon, [string]$Description) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.IconLocation = $Icon
    $shortcut.Description = $Description
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    [WinXShortcut]::WriteHash($Path, (Get-WinXHash $Target $Arguments))
}
