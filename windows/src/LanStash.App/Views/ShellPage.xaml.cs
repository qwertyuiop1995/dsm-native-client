using LanStash.App.Localization;
using LanStash.App.ViewModels;
using LanStash.Domain;
using Microsoft.UI.Xaml.Controls;

namespace LanStash.App.Views;

public sealed partial class ShellPage : Page
{
    private readonly AppViewModel _app;
    private readonly WorkspacePage _workspace;

    public ShellPage(AppViewModel app)
    {
        InitializeComponent();
        _app = app;
        _workspace = new WorkspacePage(app);
        ContentFrame.Content = _workspace;
        var localization = LocalizationService.Current;
        AppNameText.Text = localization.Get("AppName");
        LogoutItem.Content = localization.Get("ActionSignOut");
        if (Navigation.SettingsItem is NavigationViewItem settingsItem)
        {
            settingsItem.Content = localization.Get("ModuleSettings");
        }
        ProfileName.Text = app.ActiveProfile?.DisplayName ?? "NAS";

        foreach (var module in app.AvailableModules)
        {
            Navigation.MenuItems.Add(new NavigationViewItem
            {
                Content = localization.ModuleTitle(module),
                Icon = new FontIcon { Glyph = module.Glyph() },
                Tag = module,
            });
        }
        Navigation.SelectedItem = Navigation.MenuItems.FirstOrDefault();
    }

    private async void Navigation_SelectionChanged(
        NavigationView sender,
        NavigationViewSelectionChangedEventArgs args)
    {
        if (args.IsSettingsSelected)
        {
            ContentFrame.Content = new LanguageSettingsPage(_app);
            return;
        }
        if (args.SelectedItem == LogoutItem)
        {
            var localization = LocalizationService.Current;
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = localization.Get("DialogSignOutTitle"),
                Content = localization.Get("DialogSignOutMessage"),
                PrimaryButtonText = localization.Get("DialogSignOutAction"),
                CloseButtonText = localization.Get("ActionCancel"),
                DefaultButton = ContentDialogButton.Close,
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                await _app.LogoutAsync();
            }
            return;
        }
        if (args.SelectedItemContainer?.Tag is AppModule module)
        {
            await _workspace.ShowModuleAsync(module);
        }
    }
}
