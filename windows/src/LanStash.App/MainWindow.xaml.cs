using LanStash.App.Localization;
using LanStash.App.ViewModels;
using LanStash.App.Views;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using System.IO;
using WinRT.Interop;

namespace LanStash.App;

public sealed partial class MainWindow : Window
{
    private readonly AppViewModel _viewModel = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = LocalizationService.Current.Get("AppName");
        var windowHandle = WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(windowHandle);
        var window = AppWindow.GetFromWindowId(windowId);
        window.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        window.Resize(new Windows.Graphics.SizeInt32(1280, 820));

        _viewModel.ConnectionChanged += OnConnectionChanged;
        LocalizationService.Current.LanguageChanged += OnLanguageChanged;
        RootFrame.Content = new LoginPage(_viewModel);
        _ = _viewModel.InitializeAsync();
    }

    private void OnLanguageChanged(object? sender, EventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            Title = LocalizationService.Current.Get("AppName");
            RootFrame.Content = _viewModel.Repository is null
                ? new LoginPage(_viewModel)
                : new ShellPage(_viewModel);
        });
    }

    private void OnConnectionChanged(object? sender, bool connected)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            RootFrame.Content = connected
                ? new ShellPage(_viewModel)
                : new LoginPage(_viewModel);
        });
    }
}
