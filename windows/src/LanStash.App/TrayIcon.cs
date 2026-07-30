using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;

namespace LanStash.App;

internal sealed class TrayIcon : IDisposable
{
    private const uint CallbackMessage = 0x8001;
    private const uint WindowCommandMessage = 0x0111;
    private const uint LeftButtonUpMessage = 0x0202;
    private const uint LeftButtonDoubleClickMessage = 0x0203;
    private const uint RightButtonUpMessage = 0x0205;
    private const uint ContextMenuMessage = 0x007B;
    private const int OpenCommand = 1;
    private const int ToggleMappingsCommand = 2;
    private const int ShowIssuesCommand = 3;
    private const int ExitCommand = 4;
    private const int WindowProcedureIndex = -4;

    private readonly nint _windowHandle;
    private readonly nint _iconHandle;
    private readonly Action _showWindow;
    private readonly Action _toggleMappings;
    private readonly Action _showIssues;
    private readonly Action _exitApplication;
    private readonly Func<int> _mappingCount;
    private readonly Func<bool> _allMappingsPaused;
    private readonly Func<int> _issueCount;
    private readonly WindowProcedure _windowProcedure;
    private nint _previousWindowProcedure;
    private string _openText;
    private string _pauseText;
    private string _resumeText;
    private string _issuesText;
    private string _exitText;
    private bool _disposed;

    public TrayIcon(
        nint windowHandle,
        string iconPath,
        string tooltip,
        string openText,
        string pauseText,
        string resumeText,
        string issuesText,
        string exitText,
        Func<int> mappingCount,
        Func<bool> allMappingsPaused,
        Func<int> issueCount,
        Action showWindow,
        Action toggleMappings,
        Action showIssues,
        Action exitApplication)
    {
        _windowHandle = windowHandle;
        _showWindow = showWindow;
        _toggleMappings = toggleMappings;
        _showIssues = showIssues;
        _exitApplication = exitApplication;
        _mappingCount = mappingCount;
        _allMappingsPaused = allMappingsPaused;
        _issueCount = issueCount;
        _openText = openText;
        _pauseText = pauseText;
        _resumeText = resumeText;
        _issuesText = issuesText;
        _exitText = exitText;
        _windowProcedure = HandleWindowMessage;
        Marshal.SetLastPInvokeError(0);
        _previousWindowProcedure = SetWindowLongPtr(
            _windowHandle,
            WindowProcedureIndex,
            Marshal.GetFunctionPointerForDelegate(_windowProcedure));
        var windowProcedureError = Marshal.GetLastPInvokeError();
        if (_previousWindowProcedure == 0 && windowProcedureError != 0)
        {
            throw new Win32Exception(windowProcedureError);
        }

        _iconHandle = LoadImage(
            0,
            iconPath,
            1,
            0,
            0,
            0x0010 | 0x0040);
        if (_iconHandle == 0)
        {
            RestoreWindowProcedure();
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        var data = CreateData(tooltip);
        if (!ShellNotifyIcon(0, ref data))
        {
            DestroyIcon(_iconHandle);
            RestoreWindowProcedure();
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        data.TimeoutOrVersion = 4;
        _ = ShellNotifyIcon(4, ref data);
    }

    public void UpdateText(
        string tooltip,
        string openText,
        string pauseText,
        string resumeText,
        string issuesText,
        string exitText)
    {
        _openText = openText;
        _pauseText = pauseText;
        _resumeText = resumeText;
        _issuesText = issuesText;
        _exitText = exitText;
        var data = CreateData(tooltip);
        _ = ShellNotifyIcon(1, ref data);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        var data = CreateData(string.Empty);
        _ = ShellNotifyIcon(2, ref data);
        if (_iconHandle != 0)
        {
            DestroyIcon(_iconHandle);
        }
        RestoreWindowProcedure();
        GC.SuppressFinalize(this);
    }

    private NotificationIconData CreateData(string tooltip) =>
        new()
        {
            Size = (uint)Marshal.SizeOf<NotificationIconData>(),
            WindowHandle = _windowHandle,
            Id = 1,
            Flags = 0x0001 | 0x0002 | 0x0004,
            CallbackMessage = CallbackMessage,
            IconHandle = _iconHandle,
            Tooltip = tooltip.Length > 127 ? tooltip[..127] : tooltip,
            Info = string.Empty,
            InfoTitle = string.Empty,
        };

    private nint HandleWindowMessage(
        nint windowHandle,
        uint message,
        nint wordParameter,
        nint longParameter)
    {
        if (message == CallbackMessage)
        {
            var mouseMessage = unchecked((uint)(longParameter.ToInt64() & 0xFFFF));
            if (mouseMessage is LeftButtonUpMessage or LeftButtonDoubleClickMessage)
            {
                _showWindow();
                return 0;
            }
            if (mouseMessage is RightButtonUpMessage or ContextMenuMessage)
            {
                ShowContextMenu();
                return 0;
            }
        }
        else if (message == WindowCommandMessage)
        {
            HandleCommand(unchecked((int)(wordParameter.ToInt64() & 0xFFFF)));
            return 0;
        }
        return CallWindowProc(
            _previousWindowProcedure,
            windowHandle,
            message,
            wordParameter,
            longParameter);
    }

    private void ShowContextMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == 0)
        {
            return;
        }
        try
        {
            _ = AppendMenu(menu, 0, OpenCommand, _openText);
            var mappingCount = _mappingCount();
            _ = AppendMenu(
                menu,
                mappingCount == 0 ? 0x0001u : 0,
                ToggleMappingsCommand,
                _allMappingsPaused() ? _resumeText : _pauseText);
            var issueCount = _issueCount();
            _ = AppendMenu(
                menu,
                issueCount == 0 ? 0x0001u : 0,
                ShowIssuesCommand,
                string.Format(
                    CultureInfo.CurrentCulture,
                    _issuesText,
                    issueCount));
            _ = AppendMenu(menu, 0x0800, 0, null);
            _ = AppendMenu(menu, 0, ExitCommand, _exitText);
            _ = GetCursorPos(out var position);
            _ = SetForegroundWindow(_windowHandle);
            var command = TrackPopupMenu(
                menu,
                0x0002 | 0x0100,
                position.X,
                position.Y,
                0,
                _windowHandle,
                0);
            HandleCommand(command);
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    private void HandleCommand(int command)
    {
        switch (command)
        {
            case OpenCommand:
                _showWindow();
                break;
            case ToggleMappingsCommand:
                _toggleMappings();
                break;
            case ShowIssuesCommand:
                _showIssues();
                break;
            case ExitCommand:
                _exitApplication();
                break;
        }
    }

    private void RestoreWindowProcedure()
    {
        if (_previousWindowProcedure == 0)
        {
            return;
        }
        _ = SetWindowLongPtr(
            _windowHandle,
            WindowProcedureIndex,
            _previousWindowProcedure);
        _previousWindowProcedure = 0;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotificationIconData
    {
        public uint Size;
        public nint WindowHandle;
        public uint Id;
        public uint Flags;
        public uint CallbackMessage;
        public nint IconHandle;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string Tooltip;

        public uint State;
        public uint StateMask;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string Info;

        public uint TimeoutOrVersion;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string InfoTitle;

        public uint InfoFlags;
        public Guid ItemGuid;
        public nint BalloonIconHandle;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    private delegate nint WindowProcedure(
        nint windowHandle,
        uint message,
        nint wordParameter,
        nint longParameter);

    [DllImport("shell32.dll", EntryPoint = "Shell_NotifyIconW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShellNotifyIcon(
        uint message,
        ref NotificationIconData data);

    [DllImport("user32.dll", EntryPoint = "LoadImageW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint LoadImage(
        nint instance,
        string name,
        uint type,
        int desiredWidth,
        int desiredHeight,
        uint loadFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(nint iconHandle);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern nint SetWindowLongPtr(
        nint windowHandle,
        int index,
        nint newValue);

    [DllImport("user32.dll")]
    private static extern nint CallWindowProc(
        nint previousWindowProcedure,
        nint windowHandle,
        uint message,
        nint wordParameter,
        nint longParameter);

    [DllImport("user32.dll")]
    private static extern nint CreatePopupMenu();

    [DllImport("user32.dll", EntryPoint = "AppendMenuW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AppendMenu(
        nint menu,
        uint flags,
        uint id,
        string? text);

    [DllImport("user32.dll")]
    private static extern int TrackPopupMenu(
        nint menu,
        uint flags,
        int x,
        int y,
        int reserved,
        nint windowHandle,
        nint rectangle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyMenu(nint menu);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint windowHandle);
}
