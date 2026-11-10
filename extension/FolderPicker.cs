using System;
using System.Runtime.InteropServices;

public static class AseLapsFolderPicker
{
    private const uint PickFolders = 0x20;
    private const uint ForceFileSystem = 0x40;
    private const uint PathMustExist = 0x800;
    private const uint FileSystemPath = 0x80058000;
    private const int Cancelled = unchecked((int)0x800704C7);

    public static string Choose(string initialFolder)
    {
        Guid dialogClass = new Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7");
        IFileDialog dialog = (IFileDialog)Activator.CreateInstance(Type.GetTypeFromCLSID(dialogClass));
        IShellItem initialItem = null;
        IShellItem selectedItem = null;
        try
        {
            uint options;
            dialog.GetOptions(out options);
            dialog.SetOptions(options | PickFolders | ForceFileSystem | PathMustExist);
            dialog.SetTitle("Select AseLaps output folder");
            dialog.SetOkButtonLabel("Select Folder");
            if (!string.IsNullOrEmpty(initialFolder))
            {
                Guid itemInterface = typeof(IShellItem).GUID;
                SHCreateItemFromParsingName(initialFolder, IntPtr.Zero, ref itemInterface, out initialItem);
                dialog.SetFolder(initialItem);
            }

            int result = dialog.Show(IntPtr.Zero);
            if (result == Cancelled)
                return null;

            Marshal.ThrowExceptionForHR(result);
            dialog.GetResult(out selectedItem);
            IntPtr name;
            selectedItem.GetDisplayName(FileSystemPath, out name);
            try { return Marshal.PtrToStringUni(name); }
            finally { Marshal.FreeCoTaskMem(name); }
        }
        finally
        {
            if (selectedItem != null)
                Marshal.ReleaseComObject(selectedItem);
            if (initialItem != null)
                Marshal.ReleaseComObject(initialItem);
            Marshal.ReleaseComObject(dialog);
        }
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        string path, IntPtr bindContext, ref Guid interfaceId, out IShellItem item);

    // COM method order must match the Windows interfaces, including unused entries.
    [ComImport, Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog
    {
        [PreserveSig] int Show(IntPtr owner);
        void SetFileTypes(uint count, IntPtr filters);
        void SetFileTypeIndex(uint index);
        void GetFileTypeIndex(out uint index);
        void Advise(IntPtr events, out uint cookie);
        void Unadvise(uint cookie);
        void SetOptions(uint options);
        void GetOptions(out uint options);
        void SetDefaultFolder(IShellItem folder);
        void SetFolder(IShellItem folder);
        void GetFolder(out IShellItem folder);
        void GetCurrentSelection(out IShellItem item);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetFileName(out IntPtr name);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        void GetResult(out IShellItem item);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid interfaceId, out IntPtr result);
        void GetParent(out IShellItem parent);
        void GetDisplayName(uint kind, out IntPtr name);
    }
}
