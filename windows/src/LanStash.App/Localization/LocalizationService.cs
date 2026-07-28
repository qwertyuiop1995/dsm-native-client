using System.Globalization;
using LanStash.Domain;
using Microsoft.Windows.ApplicationModel.Resources;
using Windows.Globalization;
using Windows.System.UserProfile;

namespace LanStash.App.Localization;

public sealed record LanguageChoice(AppLanguageSelection Value, string DisplayName);

public sealed class LocalizationService
{
    public static LocalizationService Current { get; } = new();

    private readonly string _preferencePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LanStash",
        "language.txt");

    public event EventHandler? LanguageChanged;
    public AppLanguageSelection Selection { get; private set; } = AppLanguageSelection.System;
    public string ResolvedLanguage { get; private set; } = "en-US";

    private LocalizationService()
    {
    }

    public void Initialize()
    {
        if (File.Exists(_preferencePath) &&
            Enum.TryParse<AppLanguageSelection>(
                File.ReadAllText(_preferencePath),
                ignoreCase: true,
                out var saved))
        {
            Selection = saved;
        }
        ApplySelection();
    }

    public void SetSelection(AppLanguageSelection selection)
    {
        if (Selection == selection)
        {
            return;
        }
        Selection = selection;
        Directory.CreateDirectory(Path.GetDirectoryName(_preferencePath)!);
        File.WriteAllText(_preferencePath, selection.ToString());
        ApplySelection();
        LanguageChanged?.Invoke(this, EventArgs.Empty);
    }

    public string Get(string key)
    {
        var value = new ResourceLoader().GetString(key);
        return string.IsNullOrEmpty(value) ? key : value;
    }

    public string Format(string key, params object[] arguments) =>
        string.Format(CultureInfo.CurrentCulture, Get(key), arguments);

    public string ResolveUserText(string value) =>
        value.StartsWith(UserText.ResourcePrefix, StringComparison.Ordinal)
            ? Get(value[UserText.ResourcePrefix.Length..])
            : value;

    public string ErrorMessage(DsmException error) =>
        $"{ResolveUserText(error.Message)} {ResolveUserText(error.Recovery)}";

    public IReadOnlyList<LanguageChoice> Choices() =>
    [
        new(AppLanguageSelection.System, Get("LanguageFollowSystem")),
        new(AppLanguageSelection.English, Get("LanguageEnglish")),
        new(AppLanguageSelection.SimplifiedChinese, Get("LanguageSimplifiedChinese")),
    ];

    public string ModuleTitle(AppModule module) => Get(module switch
    {
        AppModule.Files => "ModuleFiles",
        AppModule.Photos => "ModulePhotos",
        AppModule.Chat => "ModuleChat",
        AppModule.Downloads => "ModuleDownloads",
        AppModule.Containers => "ModuleContainers",
        AppModule.VirtualMachines => "ModuleVirtualMachines",
        AppModule.NasSettings => "ModuleNasSettings",
        AppModule.Transfers => "ModuleTransfers",
        AppModule.Settings => "ModuleSettings",
        _ => throw new ArgumentOutOfRangeException(nameof(module)),
    });

    private void ApplySelection()
    {
        var systemLanguage = GlobalizationPreferences.Languages.FirstOrDefault();
        ResolvedLanguage = AppLanguageResolver.Resolve(Selection, systemLanguage);
        ApplicationLanguages.PrimaryLanguageOverride = ResolvedLanguage;
        var culture = CultureInfo.GetCultureInfo(ResolvedLanguage);
        CultureInfo.CurrentCulture = culture;
        CultureInfo.CurrentUICulture = culture;
        CultureInfo.DefaultThreadCurrentCulture = culture;
        CultureInfo.DefaultThreadCurrentUICulture = culture;
    }
}
