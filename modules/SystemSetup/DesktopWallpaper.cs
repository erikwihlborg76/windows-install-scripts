using System;
using System.Runtime.InteropServices;

namespace WindowsInstallScripts
{
    // SetWallpaper is the first method after IUnknown in IDesktopWallpaper.
    // Only that method is needed; Windows implements the rest of the interface.
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IDesktopWallpaper
    {
        void SetWallpaper(
            [MarshalAs(UnmanagedType.LPWStr)] string monitorId,
            [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    }

    public static class DesktopWallpaper
    {
        public static void Set(string path)
        {
            var instance = Activator.CreateInstance(Type.GetTypeFromCLSID(
                new Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD")));
            try
            {
                // A null monitor ID applies the image to every monitor.
                ((IDesktopWallpaper)instance).SetWallpaper(null, path);
            }
            finally
            {
                Marshal.FinalReleaseComObject(instance);
            }
        }
    }
}
