using LanStash.App.Localization;
using Microsoft.UI.Xaml.Controls;

namespace LanStash.App.Views;

public sealed partial class LanguageSettingsPage : Page
{
    private bool _isLoading = true;

    public LanguageSettingsPage()
    {
        InitializeComponent();
        var localization = LocalizationService.Current;
        TitleText.Text = localization.Get("ModuleSettings");
        FieldLabel.Text = localization.Get("LanguageTitle");
        NoteText.Text = localization.Get("LanguageFallbackNote");
        var choices = localization.Choices();
        LanguageSelector.ItemsSource = choices;
        LanguageSelector.SelectedItem = choices.First(choice =>
            choice.Value == localization.Selection);
        _isLoading = false;
    }

    private void LanguageSelector_SelectionChanged(
        object sender,
        SelectionChangedEventArgs e)
    {
        if (_isLoading || LanguageSelector.SelectedItem is not LanguageChoice choice)
        {
            return;
        }
        LocalizationService.Current.SetSelection(choice.Value);
    }
}
