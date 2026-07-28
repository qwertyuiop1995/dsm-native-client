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
        ProfileName.Text = app.ActiveProfile?.DisplayName ?? "NAS";

        foreach (var module in app.AvailableModules)
        {
            Navigation.MenuItems.Add(new NavigationViewItem
            {
                Content = module.Title(),
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
        if (args.SelectedItem == LogoutItem)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "退出登录？",
                Content = "将退出当前连接并关闭自动登录；已保存的 NAS 信息和密码会保留。",
                PrimaryButtonText = "退出登录",
                CloseButtonText = "取消",
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
