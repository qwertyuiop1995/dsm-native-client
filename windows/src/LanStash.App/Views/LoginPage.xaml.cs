using LanStash.App.ViewModels;
using LanStash.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace LanStash.App.Views;

public sealed partial class LoginPage : Page
{
    private readonly AppViewModel _viewModel;

    public LoginPage(AppViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;
        _viewModel.PropertyChanged += (_, _) => UpdateState();
        _viewModel.PasswordLoaded += (_, password) =>
            DispatcherQueue.TryEnqueue(() => PasswordInput.Password = password);
        UpdateState();
    }

    private async void ProfileList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ProfileList.SelectedItem is not NasProfile profile || _viewModel.IsBusy)
        {
            return;
        }
        await _viewModel.SelectProfileAsync(profile);
        PasswordInput.Password = _viewModel.Password;
        await _viewModel.RestoreAsync(profile);
    }

    private void NewProfile_Click(object sender, RoutedEventArgs e)
    {
        ProfileList.SelectedItem = null;
        PasswordInput.Password = string.Empty;
        OtpInput.Password = string.Empty;
        _viewModel.NewProfile();
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.Password = PasswordInput.Password;
        _viewModel.Otp = OtpInput.Password;
        await _viewModel.ConnectAsync();
    }

    private void UpdateState()
    {
        if (ConnectButton is null)
        {
            return;
        }
        ConnectButton.IsEnabled = !_viewModel.IsBusy;
        BusyIndicator.IsActive = _viewModel.IsBusy;
        ErrorBar.IsOpen = !string.IsNullOrWhiteSpace(_viewModel.ErrorMessage);
        StatusBar.IsOpen = !string.IsNullOrWhiteSpace(_viewModel.ConnectionStatus);
    }
}
