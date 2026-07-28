using LanStash.App.Localization;
using Microsoft.UI.Xaml;

namespace LanStash.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        LocalizationService.Current.Initialize();
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}
